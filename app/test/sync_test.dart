import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/data/sync/manifest.dart';
import 'package:realdealmap/data/sync/remote.dart';
import 'package:realdealmap/data/sync/sync_engine.dart';

/// 서버가 만드는 것과 같은 모양의 청크를 만든다.
///
/// 해시는 **압축 전 JSON**에 대해 낸다. 서버가 그렇게 하기 때문이고(§5.3),
/// 여기서 다르게 하면 테스트가 통과해도 실제로는 전부 거부된다.
class _Fixture {
  _Fixture(this.sggCd);
  final String sggCd;
  final Map<String, Uint8List> objects = {};
  final List<ManifestFile> files = [];

  void addChunk({
    required String propertyType,
    required String tradeType,
    required String month,
    required List<Map<String, dynamic>> records,
    bool gzipped = true,
    String? forgeHash,
  }) {
    final payload = {
      'sggCd': sggCd,
      'datasetKey': '$propertyType/$tradeType',
      'period': month,
      'count': records.length,
      'records': records,
    };
    final json = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final digest = sha256.convert(json).toString();
    final path =
        'v1/data/$sggCd/$month/$propertyType-$tradeType.${digest.substring(0, 16)}.json.gz';

    objects[path] = gzipped ? Uint8List.fromList(gzip.encode(json)) : json;
    files.add(
      ManifestFile(
        propertyType: propertyType,
        tradeType: tradeType,
        month: month,
        path: path,
        sha256: forgeHash ?? digest,
        bytes: objects[path]!.length,
        records: records.length,
      ),
    );
  }

  void publish({
    DateTime? refreshedAt,
    int ttlSeconds = 3600,
    int schemaVersion = 1,
  }) {
    final manifest = {
      'schemaVersion': schemaVersion,
      'sggCd': sggCd,
      'refreshedAt': (refreshedAt ?? DateTime.utc(2026, 9, 7, 12))
          .toIso8601String(),
      'ttlSeconds': ttlSeconds,
      'files': files
          .map(
            (f) => {
              'propertyType': f.propertyType,
              'tradeType': f.tradeType,
              'month': f.month,
              'path': f.path,
              'sha256': f.sha256,
              'bytes': f.bytes,
              'records': f.records,
            },
          )
          .toList(),
    };
    objects['v1/regions/$sggCd/manifest.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest)),
    );
  }
}

class _FakeRemote implements RemoteSource {
  _FakeRemote(this.objects);
  Map<String, Uint8List> objects;
  final List<String> fetched = [];
  Set<String> offline = {};

  @override
  Future<Uint8List?> get(String key) async {
    fetched.add(key);
    if (offline.contains(key)) throw RemoteException(key, '네트워크에 닿지 않는다');
    return objects[key];
  }
}

Map<String, dynamic> record(
  String id, {
  double? lat,
  double? lng,
  String precision = 'exact',
  int? amount = 320000,
}) => {
  'id': id,
  'umdNm': '논현동',
  'jibun': '123',
  'name': '테스트아파트',
  'contractedOn': '2026-08-14',
  'areaSqm': 84.97,
  'floor': 12,
  'builtYear': 2004,
  'amount': amount,
  'deposit': null,
  'monthlyRent': null,
  'cancelled': false,
  'cancelledOn': null,
  'lat': lat,
  'lng': lng,
  'precision': precision,
  'raw': {'aptNm': '테스트아파트', 'dealAmount': '320,000'},
};

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> rowCount() async => (await db.select(db.txRows).get()).length;

  _Fixture goodFixture() {
    final f = _Fixture('11680');
    f.addChunk(
      propertyType: 'apartment',
      tradeType: 'sale',
      month: '202608',
      records: [record('a', lat: 37.5, lng: 127.0), record('b')],
    );
    f.publish();
    return f;
  }

  group('첫 동기화', () {
    test('청크를 받아 반영한다', () async {
      final f = goodFixture();
      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      expect(result.status, SyncStatus.updated);
      expect(result.applied, 2);
      expect(await rowCount(), 2);
    });

    test('좌표가 있는 건만 지도에 오른다', () async {
      final f = goodFixture();
      await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      final pins = await db.pinsInBounds(
        south: 37.0,
        north: 38.0,
        west: 126.0,
        east: 128.0,
      );
      expect(pins.map((p) => p.txId), ['a']);
      expect(await db.unmappedCount('11680'), 1);
    });

    test('원문을 보존한다', () async {
      final f = goodFixture();
      await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      final row = await db.byTxId('a');
      final raw = jsonDecode(row!.raw) as Map<String, dynamic>;
      expect(raw['dealAmount'], '320,000');
    });

    test('기준 시각을 지역에 남긴다', () async {
      final f = goodFixture();
      await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      final region = await db.region('11680');
      expect(region!.refreshedAt, contains('2026-09-07'));
      expect(region.ttlSeconds, 3600);
    });

    test('배포된 적 없는 지역은 오류가 아니다', () async {
      final result = await SyncEngine(db, _FakeRemote({})).sync('99999');
      expect(result.status, SyncStatus.absent);
    });
  });

  group('무결성 (FR-7)', () {
    // 이것이 이 엔진의 존재 이유다. 깨진 데이터를 반영하느니 옛것을 그대로 둔다.
    test('해시가 다르면 기존 데이터를 건드리지 않는다', () async {
      final good = goodFixture();
      await SyncEngine(db, _FakeRemote(good.objects)).sync('11680');
      expect(await rowCount(), 2);

      final bad = _Fixture('11680');
      bad.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202609',
        records: [record('c'), record('d'), record('e')],
        forgeHash: 'f' * 64,
      );
      bad.publish(refreshedAt: DateTime.utc(2026, 9, 7, 13));

      final result = await SyncEngine(
        db,
        _FakeRemote(bad.objects),
      ).sync('11680');

      expect(result.status, SyncStatus.rejected);
      expect(result.keptExisting, isTrue);
      expect(result.message, contains('해시가 다르다'));
      expect(await rowCount(), 2, reason: '거부됐는데 데이터가 바뀌었다');
      expect(await db.byTxId('a'), isNotNull);
    });

    test('여러 청크 중 하나만 깨져도 전부 반영하지 않는다', () async {
      final f = _Fixture('11680');
      f.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('a')],
      );
      f.addChunk(
        propertyType: 'officetel',
        tradeType: 'sale',
        month: '202608',
        records: [record('b')],
        forgeHash: '0' * 64,
      );
      f.publish();

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      expect(result.status, SyncStatus.rejected);
      expect(await rowCount(), 0, reason: '멀쩡한 청크만 반쯤 반영됐다');
    });

    test('JSON이 깨지면 거부한다', () async {
      final f = goodFixture();
      final chunkPath = f.files.first.path;
      f.objects[chunkPath] = Uint8List.fromList(
        gzip.encode(utf8.encode('{ not json')),
      );

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');
      expect(result.status, SyncStatus.rejected);
    });

    test('매니페스트가 가리키는 청크가 없으면 거부한다', () async {
      final f = goodFixture();
      f.objects.remove(f.files.first.path);

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');
      expect(result.status, SyncStatus.rejected);
      expect(result.message, contains('청크가 없다'));
    });

    // 앞으로 나온 판을 반쯤 읽어 쓰면 무엇이 옛 규칙으로 들어왔는지 알 수 없다.
    test('모르는 판은 읽지 않는다', () async {
      final f = goodFixture();
      f.publish(schemaVersion: 99);

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');
      expect(result.status, SyncStatus.rejected);
      expect(result.message, contains('99'));
    });
  });

  group('오프라인 (FR-7)', () {
    test('닿지 못하면 옛 데이터를 그대로 둔다', () async {
      final f = goodFixture();
      await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      final remote = _FakeRemote(f.objects)
        ..offline = {SyncEngine.manifestKey('11680')};
      final result = await SyncEngine(db, remote).sync('11680');

      expect(result.status, SyncStatus.offline);
      expect(await rowCount(), 2);
    });

    test('청크 중간에 끊겨도 옛 데이터를 그대로 둔다', () async {
      final first = goodFixture();
      await SyncEngine(db, _FakeRemote(first.objects)).sync('11680');

      final next = _Fixture('11680');
      next.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202609',
        records: [record('z')],
      );
      next.publish(refreshedAt: DateTime.utc(2026, 9, 7, 14));

      final remote = _FakeRemote(next.objects)
        ..offline = {next.files.first.path};
      final result = await SyncEngine(db, remote).sync('11680');

      expect(result.status, SyncStatus.offline);
      expect(await rowCount(), 2);
      expect(await db.byTxId('z'), isNull);
    });
  });

  group('두 번째 동기화', () {
    test('내용이 그대로면 다시 받지 않는다', () async {
      final f = goodFixture();
      await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      final remote = _FakeRemote(f.objects);
      final result = await SyncEngine(db, remote).sync('11680');

      expect(result.status, SyncStatus.unchanged);
      expect(result.reused, 1);
      expect(remote.fetched, [
        SyncEngine.manifestKey('11680'),
      ], reason: '매니페스트만 봐야 하는데 청크까지 받았다');
    });

    test('바뀐 청크만 받는다', () async {
      final first = goodFixture();
      await SyncEngine(db, _FakeRemote(first.objects)).sync('11680');

      // 아파트는 그대로 두고 오피스텔만 새로 붙는다.
      final next = _Fixture('11680');
      next.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('a', lat: 37.5, lng: 127.0), record('b')],
      );
      next.addChunk(
        propertyType: 'officetel',
        tradeType: 'sale',
        month: '202608',
        records: [record('c', lat: 37.51, lng: 127.01)],
      );
      next.publish(refreshedAt: DateTime.utc(2026, 9, 7, 15));

      final remote = _FakeRemote(next.objects);
      final result = await SyncEngine(db, remote).sync('11680');

      expect(result.status, SyncStatus.updated);
      expect(result.downloaded, 1, reason: '안 바뀐 청크까지 받았다');
      expect(await rowCount(), 3);
    });

    // 원천이 정정으로 거래를 지우는 일이 있다. 남겨 두면 영원히 지워지지 않는다.
    test('같은 유형·월이 바뀌면 옛 행을 지우고 넣는다', () async {
      final first = goodFixture();
      await SyncEngine(db, _FakeRemote(first.objects)).sync('11680');

      final next = _Fixture('11680');
      next.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('a', lat: 37.5, lng: 127.0)],
      );
      next.publish(refreshedAt: DateTime.utc(2026, 9, 7, 16));

      await SyncEngine(db, _FakeRemote(next.objects)).sync('11680');

      expect(await rowCount(), 1);
      expect(await db.byTxId('b'), isNull, reason: '사라진 거래가 남았다');
    });

    // 최근 N개월만 올리므로 창이 밀리면 옛 달이 매니페스트에서 빠진다.
    test('매니페스트에서 빠진 청크의 행을 지운다', () async {
      final first = _Fixture('11680');
      first.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202606',
        records: [record('old')],
      );
      first.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('new')],
      );
      first.publish();
      await SyncEngine(db, _FakeRemote(first.objects)).sync('11680');
      expect(await rowCount(), 2);

      final next = _Fixture('11680');
      next.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('new')],
      );
      next.publish(refreshedAt: DateTime.utc(2026, 9, 7, 17));

      await SyncEngine(db, _FakeRemote(next.objects)).sync('11680');
      expect(await rowCount(), 1);
      expect(await db.byTxId('old'), isNull);
    });
  });

  group('압축', () {
    // 클라이언트가 content-encoding을 알아서 푸는지는 보장이 아니라 관측이다.
    test('풀린 채로 와도 받아들인다', () async {
      final f = _Fixture('11680');
      f.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('a', lat: 37.5, lng: 127.0)],
        gzipped: false,
      );
      f.publish();

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');
      expect(result.status, SyncStatus.updated);
      expect(await rowCount(), 1);
    });
  });

  group('신선도 (§5.2)', () {
    // 받은 시각을 기준으로 삼으면 오래 꺼 뒀던 앱이 켜자마자 "신선함"으로 판정한다.
    test('서버가 만든 시각을 기준으로 판정한다', () {
      final manifest = Manifest(
        schemaVersion: 1,
        sggCd: '11680',
        refreshedAt: DateTime.utc(2026, 9, 7, 12),
        ttlSeconds: 3600,
        files: const [],
      );

      expect(manifest.isStale(DateTime.utc(2026, 9, 7, 12, 59)), isFalse);
      expect(manifest.isStale(DateTime.utc(2026, 9, 7, 13, 1)), isTrue);
    });
  });
}
