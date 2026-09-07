import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/data/sync/manifest.dart';
import 'package:realdealmap/data/sync/refresh_trigger.dart';
import 'package:realdealmap/data/sync/sync_engine.dart';
import 'package:realdealmap/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 겹쳐 들어온 동기화를 어떻게 다루는가.
///
/// 예전에는 도는 중이면 새 요청을 그냥 버렸다. 지도를 밀어 다른 지역으로 넘어가면
/// **그 지역의 동기화가 조용히 사라졌고**, 지역 선택은 이미 바뀌어 있어 재시도도
/// 걸리지 않았다. 사용자에게는 "데이터가 없는 지역"과 똑같이 보였다.
/// 이 파일은 그 실패가 돌아오지 못하게 막는다.
class _FakeEngine implements SyncEngine {
  _FakeEngine();

  /// 부른 순서대로 쌓인다
  final calls = <String>[];

  /// 이 지역의 동기화를 여기서 붙잡아 둔다 — 겹침을 만들어내는 장치
  final gates = <String, Completer<void>>{};

  Manifest? manifestFor;

  @override
  Future<SyncOutcome> sync(String sggCd) async {
    calls.add(sggCd);
    final gate = gates[sggCd];
    if (gate != null) await gate.future;
    return SyncOutcome(
      sggCd: sggCd,
      status: SyncStatus.updated,
      applied: 1,
      manifest: manifestFor,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTrigger implements RefreshTrigger {
  final requested = <String>[];

  @override
  Future<TriggerResult> request(
    String sggCd, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    requested.add(sggCd);
    return TriggerResult.accepted;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late _FakeEngine engine;
  late _FakeTrigger trigger;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    engine = _FakeEngine();
    trigger = _FakeTrigger();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        prefsProvider.overrideWithValue(prefs),
        syncEngineProvider.overrideWithValue(engine),
        refreshTriggerProvider.overrideWithValue(trigger),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('한 지역을 동기화한다', () async {
    await container.read(syncProvider.notifier).syncRegion('11680');

    expect(engine.calls, ['11680']);
    expect(container.read(syncProvider).running, isFalse);
  });

  // 이것이 핵심이다. 버려지면 그 지역은 앱을 다시 켜기 전까지 빈 화면이다.
  test('도는 중에 들어온 다른 지역을 버리지 않는다', () async {
    engine.gates['11680'] = Completer<void>();
    final notifier = container.read(syncProvider.notifier);

    final first = notifier.syncRegion('11680');
    await Future<void>.delayed(Duration.zero);
    // 지도를 밀어 다른 지역으로 넘어간 상황
    await notifier.syncRegion('26230');

    expect(engine.calls, ['11680'], reason: '아직 첫 번째가 끝나지 않았다');

    engine.gates['11680']!.complete();
    await first;

    expect(engine.calls, ['11680', '26230'], reason: '끝난 뒤에 이어서 해야 한다');
  });

  test('같은 지역이 겹쳐 들어오면 한 번만 한다', () async {
    engine.gates['11680'] = Completer<void>();
    final notifier = container.read(syncProvider.notifier);

    final first = notifier.syncRegion('11680');
    await Future<void>.delayed(Duration.zero);
    await notifier.syncRegion('11680');

    engine.gates['11680']!.complete();
    await first;

    expect(engine.calls, ['11680']);
  });

  test('마지막으로 들어온 지역만 이어서 한다', () async {
    engine.gates['a'] = Completer<void>();
    final notifier = container.read(syncProvider.notifier);

    final first = notifier.syncRegion('a');
    await Future<void>.delayed(Duration.zero);
    // 빠르게 스와이프하며 여러 지역을 지나갔다. 지나친 곳까지 다 받을 이유는 없다
    await notifier.syncRegion('b');
    await notifier.syncRegion('c');

    engine.gates['a']!.complete();
    await first;

    expect(engine.calls, ['a', 'c']);
  });

  test('전부 끝나야 도는 중 표시가 꺼진다', () async {
    engine.gates['a'] = Completer<void>();
    final notifier = container.read(syncProvider.notifier);

    final first = notifier.syncRegion('a');
    await Future<void>.delayed(Duration.zero);
    await notifier.syncRegion('b');

    expect(container.read(syncProvider).running, isTrue);

    engine.gates['a']!.complete();
    await first;

    expect(container.read(syncProvider).running, isFalse);
  });

  // 지역을 바꾼 직후에는 들고 있던 기준 시각이 이전 지역의 것이다.
  // 앞세우면 새 지역에 남의 시각을 붙이게 된다.
  test('서버에 못 닿으면 그 지역에 저장된 기준 시각을 쓴다', () async {
    await db
        .into(db.regionRows)
        .insert(
          RegionRowsCompanion.insert(
            sggCd: '26230',
            refreshedAt: '2026-09-01T00:00:00Z',
            ttlSeconds: 3600,
            syncedAt: '2026-09-01T00:10:00Z',
          ),
        );
    final notifier = container.read(syncProvider.notifier);

    await notifier.syncRegion('26230');

    expect(container.read(syncProvider).refreshedAt, DateTime.utc(2026, 9, 1));
  });
}
