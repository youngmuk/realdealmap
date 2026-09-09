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

  /// 한 번에 몇 개가 떠 있었는지. 동시 수신을 재는 자다.
  int inFlight = 0;
  int peakInFlight = 0;

  /// 참이면 응답을 한 박자 늦춘다 — 늦추지 않으면 전부 즉시 끝나서
  /// 순차든 동시든 최고 동시 수가 1로 나온다.
  bool slow = false;

  @override
  Future<Uint8List?> get(String key) async {
    fetched.add(key);
    inFlight += 1;
    if (inFlight > peakInFlight) peakInFlight = inFlight;
    try {
      if (slow) await Future<void>.delayed(const Duration(milliseconds: 5));
      if (offline.contains(key)) throw RemoteException(key, '네트워크에 닿지 않는다');
      return objects[key];
    } finally {
      inFlight -= 1;
    }
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

  /// 12개월 지역은 9종 × 12달 = 108개다. 하나씩 받으면 왕복 지연이 108번
  /// 그대로 쌓여 지도가 20~30초 비어 있고, 사용자에게 그것은 고장이다.
  group('동시 수신', () {
    _Fixture manyChunks(int count) {
      final f = _Fixture('11680');
      for (var i = 0; i < count; i += 1) {
        f.addChunk(
          propertyType: 'apartment',
          tradeType: 'sale',
          month: '2026${(i % 12 + 1).toString().padLeft(2, '0')}',
          records: [record('tx-$i', lat: 37.5, lng: 127.0)],
        );
      }
      f.publish();
      return f;
    }

    test('여러 청크를 한꺼번에 받는다', () async {
      final f = manyChunks(20);
      final remote = _FakeRemote(f.objects)..slow = true;

      final result = await SyncEngine(db, remote).sync('11680');

      expect(result.status, SyncStatus.updated);
      expect(result.downloaded, 20);
      expect(remote.peakInFlight, greaterThan(1), reason: '하나씩 받고 있다');
    });

    // 회선을 다 열어 버리면 모바일에서 서로를 밀어내고 타임아웃이 늘어난다.
    test('동시에 여는 수에 상한이 있다', () async {
      final f = manyChunks(20);
      final remote = _FakeRemote(f.objects)..slow = true;

      await SyncEngine(db, remote).sync('11680');

      expect(remote.peakInFlight, lessThanOrEqualTo(kChunkConcurrency));
    });

    // 병렬로 받으면 실패가 도착하는 순서가 매번 달라진다. 그때그때 다른 것을
    // 보고하면 같은 고장이 실행할 때마다 다른 메시지로 보인다.
    // 같은 배치 안에서 두 가지 고장이 함께 나면, 도착 순서가 아니라
    // **매니페스트 순서**가 결과를 정해야 한다. 아니면 같은 고장이 실행할
    // 때마다 다른 메시지로 보이고, 사용자 제보로는 원인을 좁힐 수 없다.
    test('같은 배치에서 고장이 겹치면 앞선 것을 보고한다', () async {
      final f = _Fixture('11680');
      for (var i = 0; i < 6; i += 1) {
        f.addChunk(
          propertyType: 'apartment',
          tradeType: 'sale',
          month: '2026${(i + 1).toString().padLeft(2, '0')}',
          records: [record('tx-$i', lat: 37.5, lng: 127.0)],
          // 두 번째 것의 해시를 틀리게 둔다
          forgeHash: i == 1 ? 'f' * 64 : null,
        );
      }
      f.publish();
      final paths = f.files.map((x) => x.path).toList();

      for (var run = 0; run < 3; run += 1) {
        final remote = _FakeRemote(f.objects)
          ..slow = true
          // 네 번째는 네트워크가 끊긴다. 순서상 두 번째가 이겨야 한다
          ..offline = {paths[3]};

        final result = await SyncEngine(db, remote).sync('11680');

        expect(result.status, SyncStatus.rejected, reason: '실행 $run');
        expect(result.message, contains(paths[1]));
      }
    });
  });

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
        sggCd: null, // 지역을 가리지 않는다
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

    // 이 줄들은 우리가 만든 자료라 이런 모양이 올 리 없다. 그래도 왔을 때
    // 무엇이 되는지는 정해 둬야 한다 — 형변환이 그냥 터지면 그 예외는
    // 어느 catch에도 안 걸리고 화면까지 올라간다.
    test('숫자 자리에 문자열이 오면 거부한다', () async {
      final good = goodFixture();
      await SyncEngine(db, _FakeRemote(good.objects)).sync('11680');

      final f = _Fixture('11680');
      f.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202609',
        records: [
          {...record('z'), 'amount': '삼억이천'},
        ],
      );
      f.publish(refreshedAt: DateTime.utc(2026, 9, 7, 13));

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      expect(result.status, SyncStatus.rejected);
      expect(result.keptExisting, isTrue);
      expect(result.message, contains('amount'));
      expect(await rowCount(), 2, reason: '거부됐는데 데이터가 바뀌었다');
    });

    test('id가 없으면 거부한다', () async {
      final f = _Fixture('11680');
      f.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [
          {...record('a')}..remove('id'),
        ],
      );
      f.publish();

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      expect(result.status, SyncStatus.rejected);
      expect(result.message, contains('id'));
      expect(await rowCount(), 0);
    });

    test('records 안에 객체가 아닌 것이 있으면 거부한다', () async {
      final f = _Fixture('11680');
      f.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('a')],
      );
      f.publish();
      // 청크를 다시 만들면 해시가 안 맞으므로, 해시까지 같이 고친다.
      final path = f.files.first.path;
      final json = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'sggCd': '11680',
            'datasetKey': 'apartment/sale',
            'period': '202608',
            'count': 1,
            'records': ['이건 객체가 아니다'],
          }),
        ),
      );
      f.objects[path] = Uint8List.fromList(gzip.encode(json));
      f.files[0] = ManifestFile(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        path: path,
        sha256: sha256.convert(json).toString(),
        bytes: f.objects[path]!.length,
        records: 1,
      );
      f.publish();

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      expect(result.status, SyncStatus.rejected);
      expect(await rowCount(), 0);
    });

    // 지우는 열쇠와 넣는 열쇠가 갈리는 자리다. 조용히 넘기면 옛 행이 남은 채
    // 새 행이 쌓인다.
    test('다른 지역의 매니페스트는 거부한다', () async {
      final f = _Fixture('11680');
      f.addChunk(
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        records: [record('a')],
      );
      f.publish();
      // 내용은 그대로 두고 열쇠만 옮긴다 — 서버가 잘못 만든 모양이다.
      f.objects['v1/regions/11110/manifest.json'] =
          f.objects['v1/regions/11680/manifest.json']!;

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11110');

      expect(result.status, SyncStatus.rejected);
      expect(result.keptExisting, isTrue);
      expect(result.message, contains('11680'));
      expect(await rowCount(), 0);
    });

    test('매니페스트에 sggCd가 없어도 거부한다', () async {
      final f = goodFixture();
      final key = 'v1/regions/11680/manifest.json';
      final json =
          jsonDecode(utf8.decode(f.objects[key]!)) as Map<String, dynamic>;
      json.remove('sggCd');
      f.objects[key] = Uint8List.fromList(utf8.encode(jsonEncode(json)));

      final result = await SyncEngine(db, _FakeRemote(f.objects)).sync('11680');

      expect(result.status, SyncStatus.rejected);
      expect(result.message, contains('비어 있음'));
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
