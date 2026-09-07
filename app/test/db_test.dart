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

  /// 상한에 걸렸을 때 화면 안 **진짜 총계**를 세는 조회.
  ///
  /// 군집에 찍히는 숫자는 불러온 것만 센 값이다. 두 조회가 같은 조건을 써야
  /// "N건 중 M건만 표시"라는 문장이 참이 된다. 조건이 갈라지면 그 거짓은
  /// 화면만 봐서는 알아챌 수 없다.
  group('화면 안 건수', () {
    Future<void> seed(int n) async {
      for (var i = 0; i < n; i += 1) {
        await db
            .into(db.txRows)
            .insert(
              tx(
                'tx-$i',
                lat: 37.5,
                lng: 127.0,
                cancelled: i % 2 == 1,
                period: i % 3 == 0 ? '202606' : '202608',
              ),
            );
      }
    }

    test('상한과 무관하게 전부 센다', () async {
      await seed(30);

      final pins = await db.pinsInBounds(
        south: 37,
        north: 38,
        west: 126,
        east: 128,
        limit: 10,
      );
      final total = await db.countPinsInBounds(
        south: 37,
        north: 38,
        west: 126,
        east: 128,
      );

      expect(pins, hasLength(10));
      expect(total, 30);
    });

    test('마커 조회와 같은 조건을 쓴다', () async {
      await seed(30);

      for (final args in [
        (cancelled: true, months: <String>{}),
        (cancelled: false, months: <String>{}),
        (cancelled: true, months: {'202608'}),
        (cancelled: false, months: {'202606'}),
      ]) {
        final pins = await db.pinsInBounds(
          south: 37,
          north: 38,
          west: 126,
          east: 128,
          includeCancelled: args.cancelled,
          months: args.months,
        );
        final total = await db.countPinsInBounds(
          south: 37,
          north: 38,
          west: 126,
          east: 128,
          includeCancelled: args.cancelled,
          months: args.months,
        );

        expect(total, pins.length, reason: '조건 $args에서 갈라졌다');
      }
    });

    test('경계 밖은 세지 않는다', () async {
      await db.into(db.txRows).insert(tx('in', lat: 37.5, lng: 127.0));
      await db.into(db.txRows).insert(tx('out', lat: 35.0, lng: 129.0));

      expect(
        await db.countPinsInBounds(south: 37, north: 38, west: 126, east: 128),
        1,
      );
    });
  });

  group('지도 필터', () {
    // 지도와 목록이 같은 규칙을 써야 "목록에는 있는데 지도에 없다"가
    // 좌표 탓임이 분명해진다.
    test('연월로 거른다', () async {
      await db.into(db.txRows).insert(tx('a', lat: 37.5, lng: 127.0));
      await db
          .into(db.txRows)
          .insert(tx('b', lat: 37.5, lng: 127.0, period: '202606'));

      final pins = await db.pinsInBounds(
        south: 37.4,
        north: 37.6,
        west: 126.9,
        east: 127.1,
        months: {'202606'},
      );

      expect(pins.map((p) => p.txId), ['b']);
    });

    test('전월세는 보증금으로 걸린다', () async {
      await db
          .into(db.txRows)
          .insert(
            tx(
              'rent',
              lat: 37.5,
              lng: 127.0,
              datasetKey: 'apartment/rent',
            ).copyWith(deposit: const Value(20000)),
          );
      await db
          .into(db.txRows)
          .insert(
            tx(
              'sale',
              lat: 37.5,
              lng: 127.0,
            ).copyWith(amount: const Value(150000)),
          );

      final cheap = await db.pinsInBounds(
        south: 37.4,
        north: 37.6,
        west: 126.9,
        east: 127.1,
        maxAmount: 50000,
      );

      expect(cheap.map((p) => p.txId), ['rent']);
    });

    test('있는 연월만 돌려준다', () async {
      await db.into(db.txRows).insert(tx('a', lat: 37.5, lng: 127.0));
      await db.into(db.txRows).insert(tx('b', period: '202606'));
      await db.into(db.txRows).insert(tx('c', period: '202606'));

      expect(await db.availableMonths('11680'), ['202608', '202606']);
    });
  });

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
