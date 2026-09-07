/// 목록·지도에 함께 걸리는 필터 (T5.7).
///
/// 지도와 목록이 같은 필터를 본다. 둘이 따로 놀면 "목록에는 있는데 지도에 없다"가
/// 필터 때문인지 좌표가 없어서인지 사용자가 구별할 수 없다.
library;

/// 원천이 주는 9종. 화면에는 매물 유형과 거래 종류로 나눠 보여준다.
const List<String> kDatasetKeys = [
  'apartment/sale',
  'apartment/rent',
  'officetel/sale',
  'officetel/rent',
  'rowhouse/sale',
  'rowhouse/rent',
  'detached/sale',
  'detached/rent',
  'land/sale',
];

const Map<String, String> kPropertyLabels = {
  'apartment': '아파트',
  'officetel': '오피스텔',
  'rowhouse': '연립다세대',
  'detached': '단독다가구',
  'land': '토지',
};

const Map<String, String> kTradeLabels = {'sale': '매매', 'rent': '전월세'};

String datasetLabel(String datasetKey) {
  final parts = datasetKey.split('/');
  if (parts.length != 2) return datasetKey;
  final property = kPropertyLabels[parts[0]] ?? parts[0];
  final trade = kTradeLabels[parts[1]] ?? parts[1];
  return '$property $trade';
}

class TxFilter {
  const TxFilter({
    this.datasetKeys = const {},
    this.includeCancelled = true,
    this.minAmount,
    this.maxAmount,
    this.months = const {},
  });

  /// 비어 있으면 **전부**다. "아무것도 안 보임"과 "전부 보임"을 같은 값으로 두면
  /// 필터를 다 끈 사용자가 빈 지도를 보게 된다.
  final Set<String> datasetKeys;

  /// 해제된 거래를 포함할지. 기본은 포함이다 — 해제도 사실이고,
  /// 감추면 "왜 그 거래가 안 보이지"가 된다.
  final bool includeCancelled;

  /// 만원 단위. 원천이 그렇게 준다
  final int? minAmount;
  final int? maxAmount;

  /// 계약 연월 `YYYYMM`. 비어 있으면 전부
  final Set<String> months;

  bool get isEmpty =>
      datasetKeys.isEmpty &&
      includeCancelled &&
      minAmount == null &&
      maxAmount == null &&
      months.isEmpty;

  /// 지도 조회에 넘길 유형 집합. 비어 있으면 `null`(= 전부)로 바꾼다
  Set<String>? get datasetKeysOrNull =>
      datasetKeys.isEmpty ? null : datasetKeys;

  TxFilter copyWith({
    Set<String>? datasetKeys,
    bool? includeCancelled,
    Object? minAmount = _keep,
    Object? maxAmount = _keep,
    Set<String>? months,
  }) => TxFilter(
    datasetKeys: datasetKeys ?? this.datasetKeys,
    includeCancelled: includeCancelled ?? this.includeCancelled,
    minAmount: minAmount == _keep ? this.minAmount : minAmount as int?,
    maxAmount: maxAmount == _keep ? this.maxAmount : maxAmount as int?,
    months: months ?? this.months,
  );

  TxFilter toggleDataset(String key) {
    final next = Set<String>.from(datasetKeys);
    if (!next.remove(key)) next.add(key);
    return copyWith(datasetKeys: next);
  }

  /// 매물 유형 하나(아파트 등)의 매매·전월세를 한꺼번에 켜고 끈다.
  TxFilter toggleProperty(String property) {
    final keys = kDatasetKeys.where((k) => k.startsWith('$property/'));
    final allOn = keys.every(datasetKeys.contains);
    final next = Set<String>.from(datasetKeys);
    if (allOn) {
      next.removeAll(keys);
    } else {
      next.addAll(keys);
    }
    return copyWith(datasetKeys: next);
  }

  @override
  bool operator ==(Object other) =>
      other is TxFilter &&
      other.includeCancelled == includeCancelled &&
      other.minAmount == minAmount &&
      other.maxAmount == maxAmount &&
      _sameSet(other.datasetKeys, datasetKeys) &&
      _sameSet(other.months, months);

  @override
  int get hashCode => Object.hash(
    includeCancelled,
    minAmount,
    maxAmount,
    Object.hashAllUnordered(datasetKeys),
    Object.hashAllUnordered(months),
  );
}

const Object _keep = Object();

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
