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

/// 한 화면에 그릴 최대 건수. 넘으면 잘리고, 잘렸다는 사실을 화면이 밝힌다.
const int kPinLimit = 5000;

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
  ///
  /// **정렬을 붙인 이유**: 없으면 어느 것이 잘릴지가 R*Tree 순회 순서에 달려
  /// 호출마다 달라진다. 같은 자리를 봐도 묶음 개수가 미세하게 흔들린다.
  /// 결과가 [limit]과 같으면 잘린 것이고, 화면은 그 사실을 밝혀야 한다.
  /// 경계상자와 필터를 SQL 조각과 바인딩으로 만든다.
  ///
  /// 마커 조회와 건수 조회가 **같은 조건**을 써야 한다. 조건이 갈라지면
  /// "화면 안 N건 중 5,000건" 같은 문장이 거짓이 되는데, 그 거짓은 화면만
  /// 봐서는 알아챌 수 없다.
  (String, List<Variable<Object>>) _boundsQuery({
    required double south,
    required double north,
    required double west,
    required double east,
    required String? sggCd,
    Set<String>? datasetKeys,
    bool includeCancelled = true,
    int? minAmount,
    int? maxAmount,
    Set<String>? months,
  }) {
    final filters = <String>[];
    final vars = <Variable<Object>>[
      Variable<double>(south),
      Variable<double>(north),
      Variable<double>(west),
      Variable<double>(east),
    ];

    // 화면 범위만 보면 **고른 지역 밖의 거래가 섞인다.** 좌표가 하나도 없는
    // 지역을 고르면 카메라가 움직이지 않아 이전 지역 위에 그대로 머무는데,
    // 그때 머리말은 제주시인데 화면에는 동대문구 마커가 찍혀 있었다.
    // 핀을 누르면 동대문구 거래 상세가 열렸다 — 실기기에서 그렇게 잡았다.
    if (sggCd != null) {
      filters.add('AND t.sgg_cd = ?');
      vars.add(Variable<String>(sggCd));
    }
    if (datasetKeys != null && datasetKeys.isNotEmpty) {
      final holes = List.filled(datasetKeys.length, '?').join(',');
      filters.add('AND t.dataset_key IN ($holes)');
      vars.addAll(datasetKeys.map(Variable<String>.new));
    }
    if (!includeCancelled) filters.add('AND t.cancelled = 0');
    if (months != null && months.isNotEmpty) {
      final holes = List.filled(months.length, '?').join(',');
      filters.add('AND t.period IN ($holes)');
      vars.addAll(months.map(Variable<String>.new));
    }
    // 매매는 amount, 전월세는 deposit에 값이 있다. 목록 조회와 같은 규칙이라야
    // **목록에는 있는데 지도에 없는** 거래가 좌표 탓임이 분명해진다.
    if (minAmount != null) {
      filters.add('AND (t.amount >= ? OR t.deposit >= ?)');
      vars.addAll([Variable<int>(minAmount), Variable<int>(minAmount)]);
    }
    if (maxAmount != null) {
      filters.add('AND (t.amount <= ? OR t.deposit <= ?)');
      vars.addAll([Variable<int>(maxAmount), Variable<int>(maxAmount)]);
    }
    return (filters.join(' '), vars);
  }

  /// 화면 안에 좌표가 있는 거래가 **모두 몇 건인지**.
  ///
  /// 상한에 걸렸을 때만 부른다. 마커에 찍히는 숫자는 불러온 것만 센 값이라,
  /// 진짜 총계를 같이 말하지 않으면 사용자가 그 숫자를 전부로 읽는다.
  Future<int> countPinsInBounds({
    required double south,
    required double north,
    required double west,
    required double east,
    required String? sggCd,
    Set<String>? datasetKeys,
    bool includeCancelled = true,
    int? minAmount,
    int? maxAmount,
    Set<String>? months,
  }) async {
    final (filters, vars) = _boundsQuery(
      south: south,
      north: north,
      west: west,
      east: east,
      sggCd: sggCd,
      datasetKeys: datasetKeys,
      includeCancelled: includeCancelled,
      minAmount: minAmount,
      maxAmount: maxAmount,
      months: months,
    );

    final row = await customSelect(
      '''
      SELECT COUNT(*) AS n
      FROM tx_geo g
      JOIN tx_rows t ON t.rid = g.id
      WHERE g.maxLat >= ? AND g.minLat <= ? AND g.maxLng >= ? AND g.minLng <= ?
      $filters
      ''',
      variables: vars,
      readsFrom: {txRows},
    ).getSingle();

    return row.read<int>('n');
  }

  Future<List<MapPin>> pinsInBounds({
    required double south,
    required double north,
    required double west,
    required double east,
    required String? sggCd,
    Set<String>? datasetKeys,
    bool includeCancelled = true,
    int? minAmount,
    int? maxAmount,
    Set<String>? months,
    int limit = kPinLimit,
  }) async {
    final (filters, vars) = _boundsQuery(
      south: south,
      north: north,
      west: west,
      east: east,
      sggCd: sggCd,
      datasetKeys: datasetKeys,
      includeCancelled: includeCancelled,
      minAmount: minAmount,
      maxAmount: maxAmount,
      months: months,
    );
    vars.add(Variable<int>(limit));

    final rows = await customSelect(
      '''
      SELECT t.tx_id, t.lat, t.lng, t.precision, t.dataset_key,
             t.amount, t.deposit, t.monthly_rent, t.cancelled
      FROM tx_geo g
      JOIN tx_rows t ON t.rid = g.id
      WHERE g.maxLat >= ? AND g.minLat <= ? AND g.maxLng >= ? AND g.minLng <= ?
      $filters
      ORDER BY t.rid
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

  /// 이 지역에 실제로 들어 있는 계약 연월 (`YYYYMM`), 최신순.
  ///
  /// **달력에서 고르게 하지 않는다.** 데이터가 없는 달을 고를 수 있으면 사용자는
  /// 빈 화면을 보고 앱이 고장 났다고 읽는다. 있는 달만 보여준다.
  Future<List<String>> availableMonths(String sggCd) async {
    final rows = await customSelect(
      'SELECT DISTINCT period FROM tx_rows WHERE sgg_cd = ? '
      'ORDER BY period DESC',
      variables: [Variable<String>(sggCd)],
      readsFrom: {txRows},
    ).get();
    return rows.map((r) => r.read<String>('period')).toList();
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

  /// 이 지역에서 **실제로 받아 본** 자료 유형.
  ///
  /// "받았는데 0건"과 "아직 못 받았다"를 가르는 유일한 근거다. 청크 행은
  /// 매니페스트에 실린 파일마다 하나씩 남으므로, 0건짜리 유형도 행이 있고
  /// 매니페스트에 아예 없던 유형만 빠진다.
  ///
  /// 이 구별이 필요해진 것은 수집 쪽 사정 때문이다. 한 유형의 일일 쿼터가
  /// 바닥나면 그 유형만 빠진 채로 배포된다(나머지를 버리지 않으려고 그렇게 했다).
  /// 그때 화면이 "조건에 맞는 거래가 없습니다"라고만 하면, 사용자는 그 지역에
  /// 그런 거래가 없다고 읽는다. 실제로는 우리가 아직 못 받은 것이다.
  Future<Set<String>> coveredDatasetKeys(String sggCd) async {
    final rows = await customSelect(
      'SELECT DISTINCT dataset_key AS k FROM chunk_rows WHERE sgg_cd = ?',
      variables: [Variable<String>(sggCd)],
      readsFrom: {chunkRows},
    ).get();
    return rows.map((r) => r.read<String>('k')).toSet();
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
