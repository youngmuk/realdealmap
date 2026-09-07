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

  /// 계약 연월 하나를 켜고 끈다.
  ///
  /// 비어 있는 상태가 "전부"라, 마지막 하나를 끄면 전부가 켜진 것처럼 보인다.
  /// 그래서 **끄는 대신 그것만 남긴다** — 전부 켜진 상태에서 한 달을 누르면
  /// 그 달만 보겠다는 뜻이지, 그 달을 빼겠다는 뜻이 아니다.
  TxFilter toggleMonth(String month, List<String> available) {
    if (months.isEmpty) return copyWith(months: {month});
    final next = Set<String>.from(months);
    if (!next.remove(month)) next.add(month);
    // 있는 달을 전부 고른 것은 아무것도 안 고른 것과 같다. 같은 뜻은 한 값으로 둔다
    if (next.isEmpty || next.length == available.length) {
      return copyWith(months: const {});
    }
    return copyWith(months: next);
  }

  TxFilter withAmountRange({int? min, int? max}) =>
      copyWith(minAmount: min, maxAmount: max);

  /// 화면은 9종을 늘어놓지 않고 **매물 유형 × 거래 종류**로 나눠 고르게 한다.
  /// 9줄이 5줄+2줄이 되고, 사람이 실제로 생각하는 단위와도 맞는다.
  ///
  /// 저장은 그대로 9종 집합이다. 두 축을 따로 저장하면 "아파트 매매만"처럼
  /// 곱집합으로 표현되지 않는 조합을 담을 수 없게 된다.
  Set<String> get selectedProperties => datasetKeys.isEmpty
      ? kPropertyLabels.keys.toSet()
      : {for (final k in datasetKeys) k.split('/').first};

  Set<String> get selectedTrades => datasetKeys.isEmpty
      ? kTradeLabels.keys.toSet()
      : {for (final k in datasetKeys) k.split('/').last};

  TxFilter withTypes({Set<String>? properties, Set<String>? trades}) {
    final p = properties ?? selectedProperties;
    final t = trades ?? selectedTrades;
    final keys = kDatasetKeys
        .where(
          (k) =>
              p.contains(k.split('/').first) && t.contains(k.split('/').last),
        )
        .toSet();
    // **하나도 안 남는 조합은 받지 않는다.** 빈 집합은 "전부"라는 뜻이라,
    // 그대로 넣으면 전부 끈 사용자에게 전부가 보인다. 토지×전월세처럼
    // 존재하지 않는 조합도 여기서 걸린다.
    if (keys.isEmpty) return this;
    return copyWith(
      datasetKeys: keys.length == kDatasetKeys.length ? const {} : keys,
    );
  }

  /// 지금 고른 거래 종류로 **고를 수 있는** 매물 유형.
  ///
  /// 토지는 전월세가 없다. 전월세만 켠 상태에서 토지 칩을 누를 수 있게 두면
  /// 눌러도 아무 일이 없어 고장으로 읽힌다 — 아예 못 누르게 하고 이유를 밝힌다.
  Set<String> get availableProperties => {
    for (final k in kDatasetKeys)
      if (selectedTrades.contains(k.split('/').last)) k.split('/').first,
  };

  Set<String> get availableTrades => {
    for (final k in kDatasetKeys)
      if (selectedProperties.contains(k.split('/').first)) k.split('/').last,
  };

  TxFilter toggleProperty(String property) =>
      withTypes(properties: _flip(selectedProperties, property));

  TxFilter toggleTrade(String trade) =>
      withTypes(trades: _flip(selectedTrades, trade));

  Set<String> _flip(Set<String> from, String value) {
    final next = Set<String>.from(from);
    if (!next.remove(value)) next.add(value);
    return next;
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
