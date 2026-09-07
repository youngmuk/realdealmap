import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';

TxRowsCompanion tx(
  String id, {
  double? lat,
  double? lng,
  String precision = 'exact',
  String datasetKey = 'apartment/sale',
  String sggCd = '11680',
  String period = '202608',
  bool cancelled = false,
}) => TxRowsCompanion.insert(
  txId: id,
  sggCd: sggCd,
  datasetKey: datasetKey,
  period: period,
  umdNm: '논현동',
  contractedOn: '2026-08-14',
  cancelled: cancelled,
  precision: precision,
  raw: '{}',
  lat: Value(lat),
  lng: Value(lng),
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<String>> inBox(
    double s,
    double n,
    double w,
    double e, {
    Set<String>? keys,
    bool cancelled = true,
  }) async => (await db.pinsInBounds(
    south: s,
    north: n,
    west: w,
    east: e,
    datasetKeys: keys,
    includeCancelled: cancelled,
  )).map((p) => p.txId).toList();

  group('공간 색인', () {
    test('사각형 안의 것만 나온다', () async {
      await db.into(db.txRows).insert(tx('a', lat: 37.50, lng: 127.03));
      await db.into(db.txRows).insert(tx('b', lat: 37.90, lng: 127.03));

      expect(await inBox(37.4, 37.6, 126.9, 127.1), ['a']);
    });

    // 색인을 손으로 맞추면 언젠가 한 경로가 빠지고, 그때 지도에서 거래가 조용히 사라진다.
    test('지운 거래는 색인에서도 빠진다', () async {
      await db.into(db.txRows).insert(tx('a', lat: 37.5, lng: 127.0));
      await (db.delete(db.txRows)..where((t) => t.txId.equals('a'))).go();

      expect(await inBox(37.0, 38.0, 126.0, 128.0), isEmpty);
      final left = await db
          .customSelect('SELECT COUNT(*) c FROM tx_geo')
          .getSingle();
      expect(left.read<int>('c'), 0, reason: '색인에 유령 행이 남았다');
    });

    test('좌표가 붙으면 색인에 들어간다', () async {
      await db.into(db.txRows).insert(tx('a'));
      expect(await inBox(37.0, 38.0, 126.0, 128.0), isEmpty);

      await (db.update(db.txRows)..where((t) => t.txId.equals('a'))).write(
        const TxRowsCompanion(lat: Value(37.5), lng: Value(127.0)),
      );
      expect(await inBox(37.0, 38.0, 126.0, 128.0), ['a']);
    });

    test('좌표가 없는 거래는 색인에 넣지 않는다', () async {
      await db.into(db.txRows).insert(tx('a'));
      final rows = await db
          .customSelect('SELECT COUNT(*) c FROM tx_geo')
          .getSingle();
      expect(rows.read<int>('c'), 0);
    });

    // 가상 테이블이 만들어져도 풀스캔이면 전국 데이터에서 의미가 없다.
    test('질의가 R*Tree 색인을 탄다', () async {
      final plan = await db.customSelect('''
        EXPLAIN QUERY PLAN
        SELECT t.tx_id FROM tx_geo g JOIN tx_rows t ON t.rid = g.id
        WHERE g.maxLat >= 37.0 AND g.minLat <= 38.0
          AND g.maxLng >= 126.0 AND g.minLng <= 128.0
      ''').get();

      final details = plan.map((r) => r.read<String>('detail')).toList();
      expect(
        details.any((d) => d.contains('VIRTUAL TABLE INDEX')),
        isTrue,
        reason: '풀스캔한다: $details',
      );
    });
  });

  group('필터', () {
    test('유형으로 거른다', () async {
      await db.into(db.txRows).insert(tx('a', lat: 37.5, lng: 127.0));
      await db
          .into(db.txRows)
          .insert(tx('b', lat: 37.5, lng: 127.0, datasetKey: 'land/sale'));

      expect(await inBox(37.0, 38.0, 126.0, 128.0, keys: {'land/sale'}), ['b']);
    });

    test('해제된 거래를 뺄 수 있다', () async {
      await db.into(db.txRows).insert(tx('a', lat: 37.5, lng: 127.0));
      await db
          .into(db.txRows)
          .insert(tx('b', lat: 37.5, lng: 127.0, cancelled: true));

      expect(await inBox(37.0, 38.0, 126.0, 128.0, cancelled: false), ['a']);
    });
  });

  group('지도에 못 그리는 건수', () {
    // 이 숫자를 감추면 사용자는 데이터가 없는 것으로 오해한다. 목록에는 전부 있다.
    test('좌표 없는 건수를 센다', () async {
      await db.into(db.txRows).insert(tx('a', lat: 37.5, lng: 127.0));
      await db.into(db.txRows).insert(tx('b'));
      await db.into(db.txRows).insert(tx('c'));

      expect(await db.unmappedCount('11680'), 2);
      expect(await db.unmappedCount('11650'), 0);
    });
  });

  group('근사 좌표', () {
    test('등급으로 근사 여부를 안다', () {
      for (final p in ['partial', 'umd']) {
        expect(
          MapPin(
            txId: 'x',
            lat: 0,
            lng: 0,
            precision: p,
            datasetKey: 'k',
            amount: null,
            deposit: null,
            monthlyRent: null,
            cancelled: false,
          ).isApproximate,
          isTrue,
        );
      }
      for (final p in ['exact', 'jibun']) {
        expect(
          MapPin(
            txId: 'x',
            lat: 0,
            lng: 0,
            precision: p,
            datasetKey: 'k',
            amount: null,
            deposit: null,
            monthlyRent: null,
            cancelled: false,
          ).isApproximate,
          isFalse,
        );
      }
    });
  });
}
