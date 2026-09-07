import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/ads/ad_policy.dart';
import 'package:realdealmap/features/ads/ads.dart';
import 'package:realdealmap/state/ads.dart';
import 'package:realdealmap/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 광고 시점 규칙 (T6.2 · FR-6).
///
/// 광고는 눈으로 확인하기 가장 어려운 기능이다. 실기기에서 "안 떴다"는 것이
/// 규칙을 지킨 것인지 배선이 끊어진 것인지 구별되지 않는다. 그래서 규칙을
/// 순수하게 떼어 두고 여기서 시험한다.
class _FakeAds implements InterstitialAds {
  bool succeeds = true;
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<bool> show() async {
    calls++;
    final g = gate;
    if (g != null) await g.future;
    return succeeds;
  }
}

void main() {
  final t0 = DateTime.utc(2026, 9, 8, 12);

  group('규칙', () {
    const policy = AdPolicy();

    bool due({
      Duration sinceLast = const Duration(hours: 2),
      Duration sinceLaunch = const Duration(minutes: 10),
      bool busy = false,
    }) => policy.isDue(
      now: t0,
      since: t0.subtract(sinceLast),
      launchedAt: t0.subtract(sinceLaunch),
      busy: busy,
    );

    test('한 주기가 지나면 보여준다', () {
      expect(due(), isTrue);
    });

    test('한 주기가 안 지났으면 안 보여준다', () {
      expect(due(sinceLast: const Duration(minutes: 59)), isFalse);
      expect(due(sinceLast: const Duration(minutes: 60)), isTrue);
    });

    // 로딩 위에 광고를 얹으면 사용자는 광고를 로딩 실패로 읽는다.
    test('갱신 중에는 안 보여준다', () {
      expect(due(busy: true), isFalse);
    });

    // 사용자는 무언가를 보러 앱을 열었다. 그 앞을 막으면 앱을 여는 일이 손해가 된다.
    test('켠 직후에는 안 보여준다', () {
      expect(due(sinceLaunch: const Duration(seconds: 30)), isFalse);
      expect(due(sinceLaunch: const Duration(seconds: 91)), isTrue);
    });
  });

  // 이것이 "지도 제스처 중 노출 0회"를 지키는 방식이다. 호출부에서 조심하는
  // 것이 아니라, 지도 제스처에서 부를 수 있는 이름 자체를 두지 않는다.
  test('물어볼 수 있는 자리는 안전 전환 지점뿐이다', () {
    expect(AdMoment.values, hasLength(4));
    expect(AdMoment.values, [
      AdMoment.detailClosed,
      AdMoment.tabSwitched,
      AdMoment.filterApplied,
      AdMoment.resumed,
    ]);
  });

  group('노출 시각', () {
    late AppDatabase db;
    late _FakeAds ads;
    var now = t0;

    Future<ProviderContainer> boot(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          prefsProvider.overrideWithValue(prefs),
          adsProvider.overrideWithValue(ads),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      // 실제 앱에서는 실행과 동시에 만들어진다. 여기서 미리 만들지 않으면
      // launchedAt이 "첫 물음이 온 시각"이 되어 켠 직후 제한이 늘 걸린다.
      container.read(adsControllerProvider);
      return container;
    }

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      ads = _FakeAds();
      now = t0;
    });
    tearDown(() => db.close());

    // 안 남기면 앱을 여닫을 때마다 주기가 처음부터 시작된다.
    test('보여준 시각을 저장한다', () async {
      final c = await boot({
        'ad.first_run_at': t0
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'ad.last_at': t0.subtract(const Duration(hours: 2)).toIso8601String(),
      });
      now = t0.add(const Duration(minutes: 5));

      expect(
        await c
            .read(adsControllerProvider.notifier)
            .onMoment(AdMoment.tabSwitched),
        isTrue,
      );

      final saved = c.read(prefsProvider).getString('ad.last_at');
      expect(DateTime.parse(saved!), now);
      expect(c.read(adsControllerProvider).lastShownAt, now);
    });

    // 못 보여줬는데 보여준 것으로 치면 광고는 안 나오고 주기만 소모된다.
    test('못 보여줬으면 시각을 건드리지 않는다', () async {
      ads.succeeds = false;
      final before = t0.subtract(const Duration(hours: 2));
      final c = await boot({
        'ad.first_run_at': t0
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'ad.last_at': before.toIso8601String(),
      });
      now = t0.add(const Duration(minutes: 5));

      expect(
        await c
            .read(adsControllerProvider.notifier)
            .onMoment(AdMoment.tabSwitched),
        isFalse,
      );

      expect(
        DateTime.parse(c.read(prefsProvider).getString('ad.last_at')!),
        before,
      );
      expect(c.read(adsControllerProvider).lastShownAt, before);
    });

    // 설치하자마자 광고가 뜨면 그것이 이 앱의 첫인상이 된다.
    test('설치 직후 첫 주기는 기다린다', () async {
      final c = await boot({});
      // 켠 직후 제한만 넘기고 한 주기는 안 지난 시점
      now = t0.add(const Duration(minutes: 5));

      expect(
        await c
            .read(adsControllerProvider.notifier)
            .onMoment(AdMoment.tabSwitched),
        isFalse,
      );
      expect(ads.calls, 0);

      expect(
        c.read(prefsProvider).getString('ad.first_run_at'),
        isNotNull,
        reason: '기준점을 안 남기면 다음 실행에서 곧바로 광고가 뜬다',
      );
    });

    test('설치 후 한 주기가 지나면 보여준다', () async {
      final c = await boot({});
      now = t0.add(const Duration(hours: 1, minutes: 1));

      expect(
        await c.read(adsControllerProvider.notifier).onMoment(AdMoment.resumed),
        isTrue,
      );
    });

    // 탭 전환 직후 포그라운드 복귀처럼 두 자리에서 동시에 물어올 수 있다.
    test('겹쳐 들어와도 한 편만 보여준다', () async {
      final c = await boot({
        'ad.first_run_at': t0
            .subtract(const Duration(days: 3))
            .toIso8601String(),
        'ad.last_at': t0.subtract(const Duration(hours: 2)).toIso8601String(),
      });
      now = t0.add(const Duration(minutes: 5));
      ads.gate = Completer<void>();
      final notifier = c.read(adsControllerProvider.notifier);

      final first = notifier.onMoment(AdMoment.tabSwitched);
      await Future<void>.delayed(Duration.zero);
      expect(await notifier.onMoment(AdMoment.resumed), isFalse);

      ads.gate!.complete();
      expect(await first, isTrue);
      expect(ads.calls, 1);
    });

    // 광고 단위가 없는 지금 상태에서 시각이 갱신되면, 나중에 광고를 붙여도
    // 첫 한 시간이 통째로 사라진다.
    test('광고 단위가 없으면 아무 일도 일어나지 않는다', () async {
      ads = _FakeAds();
      const none = NoInterstitialAds();

      expect(await none.show(), isFalse);
    });
  });
}
