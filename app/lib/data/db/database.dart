import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

/// 지도 조회용 R*Tree 가상 테이블 (T5.2).
///
/// 화면에 보이는 사각형 안의 거래만 뽑는 것이 지도의 유일한 무거운 질의다.
/// 위도·경도에 각각 B-tree를 걸면 한쪽만 범위 스캔하고 나머지는 걸러내야 하는데,
/// 전국을 담으면 그 "나머지"가 수십만 건이 된다. R*Tree는 두 축을 함께 색인한다.
const _createRtree = '''
CREATE VIRTUAL TABLE IF NOT EXISTS tx_geo
USING rtree(id, minLat, maxLat, minLng, maxLng)
''';

/// 색인을 **트리거로** 유지한다.
///
/// 삽입·삭제 코드에서 손으로 맞추면 언젠가 한 경로가 빠지고, 그때 지도에서
/// 거래가 조용히 사라진다. 조용한 실패는 원천 쪽에서 이미 겪었다(R-14).
/// 트리거는 잊을 수가 없다.
const _createTriggers = [
  '''
CREATE TRIGGER IF NOT EXISTS tx_geo_ai AFTER INSERT ON tx_rows
WHEN new.lat IS NOT NULL AND new.lng IS NOT NULL
BEGIN
  INSERT INTO tx_geo(id, minLat, maxLat, minLng, maxLng)
  VALUES (new.rid, new.lat, new.lat, new.lng, new.lng);
END
''',
  '''
CREATE TRIGGER IF NOT EXISTS tx_geo_ad AFTER DELETE ON tx_rows
BEGIN
  DELETE FROM tx_geo WHERE id = old.rid;
END
''',
  '''
CREATE TRIGGER IF NOT EXISTS tx_geo_au AFTER UPDATE OF lat, lng ON tx_rows
BEGIN
  DELETE FROM tx_geo WHERE id = old.rid;
  INSERT INTO tx_geo(id, minLat, maxLat, minLng, maxLng)
  SELECT new.rid, new.lat, new.lat, new.lng, new.lng WHERE new.lat IS NOT NULL AND new.lng IS NOT NULL;
END
''',
];

/// 지도 한 화면에 그릴 거래.
///
/// 상세화면이 쓰는 `raw`는 싣지 않는다. 마커 3,000개를 그리는데 원문 JSON까지
/// 끌고 오면 대부분이 버려질 문자열을 옮기는 데 쓰인다.
class MapPin {
  const MapPin({
    required this.txId,
    required this.lat,
    required this.lng,
    required this.precision,
    required this.datasetKey,
    required this.amount,
    required this.deposit,
    required this.monthlyRent,
    required this.cancelled,
  });

  final String txId;
  final double lat;
  final double lng;
  final String precision;
  final String datasetKey;
  final int? amount;
  final int? deposit;
  final int? monthlyRent;
  final bool cancelled;

  /// 법정동 중심점이라 같은 동의 거래가 모두 같은 좌표에 있다.
  /// 개별 핀으로 그리면 한 점에 수백 개가 쌓이므로 **반드시 묶어서** 그린다.
  bool get isApproximate => precision == 'partial' || precision == 'umd';
}

@DriftDatabase(tables: [TxRows, RegionRows, ChunkRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'realdealmap'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _ensureGeoIndex();
    },
    beforeOpen: (details) async {
      // 외래키가 없어도 트리거는 켜 둔다. 가상 테이블은 `createAll`이 만들지 않으므로
      // 열 때마다 존재를 확인한다 — 사용자가 앱 데이터를 지우고 되살릴 수도 있다.
      await _ensureGeoIndex();
    },
  );

  Future<void> _ensureGeoIndex() async {
    await customStatement(_createRtree);
    for (final trigger in _createTriggers) {
      await customStatement(trigger);
    }
  }

  /// 화면 사각형 안의 거래를 뽑는다.
  ///
  /// 점이라 `min == max`지만 겹침 조건으로 쓴다 — 나중에 면적을 가진 도형을
  /// 넣더라도 질의를 고칠 필요가 없다.
  ///
  /// [limit]은 그리기 폭주를 막는 안전장치다. 서울 전역을 한 화면에 담으면
  /// 수만 건이 나오는데, 그 줌에서는 어차피 개별 마커를 그리지 않는다.
  Future<List<MapPin>> pinsInBounds({
    required double south,
    required double north,
    required double west,
    required double east,
    Set<String>? datasetKeys,
    bool includeCancelled = true,
    int limit = 5000,
  }) async {
    final filters = <String>[];
    final vars = <Variable<Object>>[
      Variable<double>(south),
      Variable<double>(north),
      Variable<double>(west),
      Variable<double>(east),
    ];

    if (datasetKeys != null && datasetKeys.isNotEmpty) {
      final holes = List.filled(datasetKeys.length, '?').join(',');
      filters.add('AND t.dataset_key IN ($holes)');
      vars.addAll(datasetKeys.map(Variable<String>.new));
    }
    if (!includeCancelled) filters.add('AND t.cancelled = 0');
    vars.add(Variable<int>(limit));

    final rows = await customSelect(
      '''
      SELECT t.tx_id, t.lat, t.lng, t.precision, t.dataset_key,
             t.amount, t.deposit, t.monthly_rent, t.cancelled
      FROM tx_geo g
      JOIN tx_rows t ON t.rid = g.id
      WHERE g.maxLat >= ? AND g.minLat <= ? AND g.maxLng >= ? AND g.minLng <= ?
      ${filters.join(' ')}
      LIMIT ?
      ''',
      variables: vars,
      readsFrom: {txRows},
    ).get();

    return rows
        .map(
          (r) => MapPin(
            txId: r.read<String>('tx_id'),
            lat: r.read<double>('lat'),
            lng: r.read<double>('lng'),
            precision: r.read<String>('precision'),
            datasetKey: r.read<String>('dataset_key'),
            amount: r.readNullable<int>('amount'),
            deposit: r.readNullable<int>('deposit'),
            monthlyRent: r.readNullable<int>('monthly_rent'),
            cancelled: r.read<int>('cancelled') != 0,
          ),
        )
        .toList();
  }

  /// 좌표가 없어 지도에 못 그리는 건수. 목록 탭의 "지도 미표시 N건" 배지가 쓴다(FR-2).
  ///
  /// 이 숫자를 감추면 사용자는 데이터가 없는 것으로 오해한다. 실제로는 원천이
  /// 지번을 가려 좌표를 만들 수 없었을 뿐이고, 목록에는 전부 있다.
  Future<int> unmappedCount(String sggCd) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM tx_rows WHERE sgg_cd = ? AND lat IS NULL',
      variables: [Variable<String>(sggCd)],
      readsFrom: {txRows},
    ).getSingle();
    return row.read<int>('c');
  }

  /// 목록 탭이 쓰는 조회 (T5.7).
  ///
  /// **좌표가 없는 거래도 나온다.** 지도에 못 그리는 것과 데이터가 없는 것은
  /// 다르고, 목록은 그 차이를 메우는 자리다 — 단독·토지처럼 원천이 지번을
  /// 가리는 유형은 목록에서만 볼 수 있다(FR-2).
  ///
  /// 최신 계약일 순으로 준다. 실거래는 "지금 얼마인가"를 보는 데이터라
  /// 오래된 것을 먼저 보여줄 이유가 없다.
  Future<List<TxRow>> listTransactions({
    required String sggCd,
    Set<String>? datasetKeys,
    bool includeCancelled = true,
    int? minAmount,
    int? maxAmount,
    Set<String>? months,
    int limit = 200,
    int offset = 0,
  }) {
    final query = select(txRows)..where((t) => t.sggCd.equals(sggCd));

    if (datasetKeys != null && datasetKeys.isNotEmpty) {
      query.where((t) => t.datasetKey.isIn(datasetKeys));
    }
    if (months != null && months.isNotEmpty) {
      query.where((t) => t.period.isIn(months));
    }
    if (!includeCancelled) query.where((t) => t.cancelled.equals(false));

    // 매매는 amount, 전월세는 deposit에 값이 있다. 가격 필터는 둘 중 있는 쪽을 본다 —
    // amount만 보면 전월세가 통째로 걸러지고, 사용자는 필터가 고장 났다고 느낀다.
    if (minAmount != null) {
      query.where(
        (t) =>
            t.amount.isBiggerOrEqualValue(minAmount) |
            t.deposit.isBiggerOrEqualValue(minAmount),
      );
    }
    if (maxAmount != null) {
      query.where(
        (t) =>
            t.amount.isSmallerOrEqualValue(maxAmount) |
            t.deposit.isSmallerOrEqualValue(maxAmount),
      );
    }

    query
      ..orderBy([
        (t) =>
            OrderingTerm(expression: t.contractedOn, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.txId),
      ])
      ..limit(limit, offset: offset);

    return query.get();
  }

  Future<TxRow?> byTxId(String txId) =>
      (select(txRows)..where((t) => t.txId.equals(txId))).getSingleOrNull();

  Future<RegionRow?> region(String sggCd) => (select(
    regionRows,
  )..where((r) => r.sggCd.equals(sggCd))).getSingleOrNull();

  Future<Set<String>> appliedChunkPaths(String sggCd) async {
    final rows = await (select(
      chunkRows,
    )..where((c) => c.sggCd.equals(sggCd))).get();
    return rows.map((c) => c.path).toSet();
  }
}
