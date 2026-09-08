@Tags(['live'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/data/sync/region_index.dart';
import 'package:realdealmap/data/sync/remote.dart';
import 'package:realdealmap/data/sync/sync_engine.dart';

/// 실제 R2를 상대로 도는 통합 테스트.
///
/// 기본으로는 **건너뛴다.** 네트워크가 필요하고 서버 상태에 따라 결과가 달라지므로
/// CI의 회귀 판정에 섞으면 안 된다. 대신 배포 경로를 통째로 확인할 수 있는 유일한
/// 자리라, 서버를 손댈 때마다 손으로 돌린다:
///
///   flutter test test/live_sync_test.dart --dart-define=DATA_BASE_URL=https://...
///
/// 확인하는 것은 "받아진다"가 아니라 **서버와 앱이 같은 규칙을 쓰는가**다.
/// 해시 기준(압축 전 JSON), gzip 처리, 매니페스트 판, 필드 이름 — 어느 하나만
/// 어긋나도 앱은 조용히 빈 화면이 된다.
const _baseUrl = String.fromEnvironment('DATA_BASE_URL');

void main() {
  if (_baseUrl.isEmpty) {
    test('DATA_BASE_URL이 없어 건너뛴다', () {}, skip: 'DATA_BASE_URL을 주면 돈다');
    return;
  }

  late AppDatabase db;
  late HttpRemote remote;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remote = HttpRemote(_baseUrl);
  });
  tearDown(() async {
    remote.close();
    await db.close();
  });

  test('지역 색인을 받는다', () async {
    final index = await RegionIndexLoader(remote).load();

    expect(index, isNotNull, reason: '색인을 못 받았다');
    expect(index!.regions, isNotEmpty, reason: '배포된 지역이 없다');
    for (final region in index.regions) {
      expect(region.sggCd, hasLength(5));
      expect(region.name, isNotEmpty);
    }
  });

  test('배포된 지역을 통째로 동기화한다', () async {
    final index = await RegionIndexLoader(remote).load();
    final region = index!.regions.first;

    final outcome = await SyncEngine(db, remote).sync(region.sggCd);

    expect(
      outcome.status,
      SyncStatus.updated,
      reason: '동기화 실패: ${outcome.message}',
    );
    expect(outcome.applied, region.records);

    final stored = await db.select(db.txRows).get();
    expect(stored, hasLength(region.records));

    // 좌표가 붙은 건수가 서버가 말한 것과 같아야 한다. 다르면 굽는 쪽과 읽는 쪽의
    // 규칙이 어긋난 것이고, 지도에서 마커가 조용히 사라진다.
    final located = stored.where((t) => t.lat != null).length;
    expect(located, region.located);
  });

  test('두 번째 동기화는 청크를 다시 받지 않는다', () async {
    final index = await RegionIndexLoader(remote).load();
    final sggCd = index!.regions.first.sggCd;

    await SyncEngine(db, remote).sync(sggCd);
    final again = await SyncEngine(db, remote).sync(sggCd);

    expect(again.status, SyncStatus.unchanged);
  });

  test('지도 조회가 실좌표를 집는다', () async {
    final index = await RegionIndexLoader(remote).load();
    final region = index!.regions.firstWhere((r) => r.hasMap);
    await SyncEngine(db, remote).sync(region.sggCd);

    final box = region.bbox!;
    final pins = await db.pinsInBounds(
      sggCd: null, // 지역을 가리지 않는다
      south: box.south,
      north: box.north,
      west: box.west,
      east: box.east,
      limit: 100000,
    );

    expect(pins, hasLength(region.located));
    for (final pin in pins) {
      expect(pin.lat, inInclusiveRange(box.south, box.north));
      expect(pin.lng, inInclusiveRange(box.west, box.east));
    }
  });

  test('상세에 원문이 실려 있다', () async {
    final index = await RegionIndexLoader(remote).load();
    await SyncEngine(db, remote).sync(index!.regions.first.sggCd);

    final rows = await db.select(db.txRows).get();
    final withRaw = rows.where((r) => r.raw.length > 2);
    expect(withRaw, isNotEmpty, reason: '원문이 비어 있다 (FR-3)');
  });
}
