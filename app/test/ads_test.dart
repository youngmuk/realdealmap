import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/ads/ad_policy.dart';
import 'package:realdealmap/features/ads/admob.dart';
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
  _idPairing();

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

/// 광고 ID 짝 맞추기 (T6.2).
///
/// 이 검사가 있는 이유는 실패 모양 때문이다. 앱 ID와 단위 ID 중 **한쪽만**
/// 바꾸거나 서로 바꿔 넣으면 앱은 멀쩡히 돌고 광고만 안 나온다. 크래시도
/// 로그도 없고 수익만 0이라, 한참 지나서야 알아차린다. 사람 눈으로 두 파일을
/// 대조하는 일은 언젠가 빠뜨리므로 여기서 기계가 본다.
void _idPairing() {
  group('광고 ID', () {
    // 매니페스트를 문자열로 읽는다. XML 파서를 붙일 만큼의 일이 아니다.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    /// `ca-app-pub-<게시자>~<앱>` / `ca-app-pub-<게시자>/<단위>`에서 게시자만.
    String publisherOf(String id) =>
        RegExp(r'ca-app-pub-(\d+)[~/]').firstMatch(id)!.group(1)!;

    test('앱 ID와 단위 ID의 게시자 번호가 같다', () {
      final appId = RegExp(
        r'ca-app-pub-\d+~\d+',
      ).firstMatch(manifest)?.group(0);
      expect(appId, isNotNull, reason: '매니페스트에 AdMob 앱 ID가 없다');

      expect(
        publisherOf(appId!),
        publisherOf(kInterstitialUnitId),
        reason:
            '앱 ID와 광고 단위 ID의 게시자 번호가 다르다. '
            '한쪽만 바꿨거나 서로 다른 계정의 값을 섞었다',
      );
    });

    test('매니페스트에 구글 테스트 앱 ID가 남아 있지 않다', () {
      // 3940256099942544는 구글이 공개한 테스트 계정이다. 이것으로 출시하면
      // 광고는 뜨지만 수익이 0이다.
      expect(
        manifest,
        isNot(contains('ca-app-pub-3940256099942544')),
        reason: '매니페스트가 아직 구글 테스트 앱 ID를 쓴다',
      );
    });

    test('실제 단위와 테스트 단위는 서로 다르다', () {
      expect(kInterstitialUnitId, isNot(kTestInterstitialUnitId));
      expect(kInterstitialUnitId, startsWith('ca-app-pub-'));
      expect(kInterstitialUnitId, contains('/'));
    });

    test('테스트 실행(=릴리스 아님)에서는 테스트 단위를 쓴다', () {
      // 개발 중에 실제 광고를 받아 자기 광고를 자기가 누르면 계정이 정지된다.
      // 이 기대가 깨졌다면 kReleaseMode 분기가 사라진 것이다.
      expect(kActiveInterstitialUnitId, kTestInterstitialUnitId);
    });
  });
}
