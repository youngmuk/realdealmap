/// 상세 정보의 내용을 만든다 (T5.6 · FR-3).
///
/// 화면 구성은 `Doc/상세정보명세.html`을 따른다 — 도면(있을 때) → 요약 → 표.
/// 여기서는 **표의 내용**만 만든다. 위젯이 아니라 순수 함수라 테스트로 9종을
/// 전부 확인할 수 있다.
///
/// 원칙 하나: **값이 없는 행은 넣지 않는다.** 원천은 잘못된 요청에도 오류 대신
/// 빈 값을 준다(R-14). "—"로 채운 행을 늘어놓으면 원천이 안 준 것인지 우리가
/// 못 읽은 것인지 구별되지 않고, 화면만 길어진다.
library;

import 'dart:convert';

import '../../data/db/database.dart';
import '../../format.dart';
import '../../state/filters.dart';

class DetailRow {
  const DetailRow(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;

  /// 눈에 띄게 낼 행. 인상폭처럼 이 화면에만 있는 값에 쓴다
  final bool emphasis;
}

class DetailSection {
  const DetailSection(this.title, this.rows);
  final String title;
  final List<DetailRow> rows;
}

/// 상세 화면 머리에 크게 나가는 요약.
class DetailHeader {
  const DetailHeader({
    required this.title,
    required this.address,
    required this.price,
    required this.summary,
    required this.datasetLabel,
    required this.cancelled,
    required this.approximate,
  });

  /// 단지·건물명. 토지처럼 이름이 없으면 법정동이 대신 온다
  final String title;
  final String address;

  /// 매매면 거래금액, 전월세면 보증금/월세
  final String price;

  /// `전용 84.97m² (25.7평) · 12층 · 2004년`
  final String summary;
  final String datasetLabel;
  final bool cancelled;

  /// 좌표가 법정동 중심점이다. 지도의 위치를 믿으면 안 된다는 뜻이라 반드시 표시한다
  final bool approximate;
}

class TxDetail {
  const TxDetail({
    required this.header,
    required this.sections,
    required this.raw,
  });

  final DetailHeader header;
  final List<DetailSection> sections;

  /// 표에 싣지 못한 나머지 원문. "원문 전체" 펼치기에서 보여준다 —
  /// 우리가 이름을 붙이지 못한 항목도 사용자에게 도달해야 한다
  final Map<String, String> raw;
}

const Map<String, String> _precisionLabels = {
  'exact': '지번 기준',
  'jibun': '지번 기준',
  'partial': '법정동 근사 (지번 비공개)',
  'umd': '법정동 근사 (지번 없음)',
};

/// 원문 필드의 한글 이름표. 여기 없는 항목은 "원문 전체"에 원래 이름으로 남는다.
const Map<String, String> _rawLabels = {
  'dealingGbn': '거래유형',
  'estateAgentSggNm': '중개사 소재지',
  'rgstDate': '등기일자',
  'slerGbn': '매도자',
  'buyerGbn': '매수자',
  'aptDong': '동',
  'landLeaseholdGbn': '토지임대부',
  'contractTerm': '계약기간',
  'contractType': '계약구분',
  'useRRRight': '갱신요구권 사용',
  'jimok': '지목',
  'landUse': '용도지역',
  'shareDealingType': '지분거래',
  'totalFloorAr': '연면적',
  'plottageAr': '대지면적',
  'landAr': '대지권면적',
  'houseType': '주택유형',
};

/// 해제 정보. 정규화된 `cancelled`로 이미 행을 만들었을 때만 원문에서 뺀다.
///
/// 이름표만 달아 두고 렌더링하지 않았더니 해제 거래가 아닌 행에서 이 값이
/// 통째로 사라졌다. 표에 자리를 못 잡은 원문은 반드시 "원문 전체"로 나가야 한다.
const Set<String> _cancelFields = {'cdealType', 'cdealDay'};

/// 표에 실었으므로 "원문 전체"에서 뺄 항목. 같은 값을 두 번 보여줄 이유가 없다.
const Set<String> _shownElsewhere = {
  'dealYear',
  'dealMonth',
  'dealDay',
  'dealAmount',
  'deposit',
  'monthlyRent',
  'preDeposit',
  'preMonthlyRent',
  'floor',
  'buildYear',
  'excluUseAr',
  'dealArea',
  'umdNm',
  'jibun',
  'sggCd',
  'aptNm',
  'offiNm',
  'mhouseNm',
};

bool _blank(String? value) => value == null || value.trim().isEmpty;

String _text(Map<String, dynamic> raw, String key) {
  final value = raw[key];
  return value == null ? '' : value.toString().trim();
}

/// 원문의 `Y`/`N`·`O` 같은 표시를 사람 말로. 모르는 값은 원문 그대로 낸다 —
/// 우리가 못 읽는 값이라고 감추면 사용자도 못 본다.
String _yesNo(String value) => switch (value.toUpperCase()) {
  'Y' || 'O' => '예',
  'N' || 'X' => '아니오',
  _ => value,
};

void _add(
  List<DetailRow> rows,
  String label,
  String value, {
  bool emphasis = false,
}) {
  if (_blank(value)) return;
  rows.add(DetailRow(label, value, emphasis: emphasis));
}

TxDetail buildDetail(TxRow tx) {
  final raw = _decodeRaw(tx.raw);
  final isRent = tx.datasetKey.endsWith('/rent');

  return TxDetail(
    header: _header(tx, isRent),
    sections: [
      _dealSection(tx, raw, isRent),
      _buildingSection(tx, raw),
      _locationSection(tx),
      if (isRent) _rentSection(tx, raw) else _saleSection(raw),
    ].where((s) => s.rows.isNotEmpty).toList(),
    raw: _leftover(raw, cancelShown: tx.cancelled),
  );
}

Map<String, dynamic> _decodeRaw(String encoded) {
  try {
    final decoded = jsonDecode(encoded);
    return decoded is Map<String, dynamic> ? decoded : {};
  } on FormatException {
    // 원문을 못 읽어도 정규화된 필드는 멀쩡하다. 상세화면을 통째로 잃지 않는다.
    return {};
  }
}

DetailHeader _header(TxRow tx, bool isRent) {
  final area = formatArea(tx.areaSqm);
  final bits = <String>[
    if (area.isNotEmpty) '${isRent ? '' : '전용 '}$area',
    if (tx.floor != null) '${tx.floor}층',
    if (tx.builtYear != null) '${tx.builtYear}년',
  ];

  return DetailHeader(
    title: _blank(tx.name) ? tx.umdNm : tx.name!,
    address: [tx.umdNm, tx.jibun].where((s) => !_blank(s)).join(' '),
    price: isRent
        ? formatRent(tx.deposit, tx.monthlyRent)
        : formatMoney(tx.amount),
    summary: bits.join(' · '),
    datasetLabel: datasetLabel(tx.datasetKey),
    cancelled: tx.cancelled,
    approximate: tx.precision == 'partial' || tx.precision == 'umd',
  );
}

DetailSection _dealSection(TxRow tx, Map<String, dynamic> raw, bool isRent) {
  final rows = <DetailRow>[];
  if (isRent) {
    _add(rows, '보증금', formatMoney(tx.deposit));
    if ((tx.monthlyRent ?? 0) > 0) {
      _add(rows, '월세', formatMoney(tx.monthlyRent));
    }
  } else {
    _add(rows, '거래금액', formatMoney(tx.amount));
  }
  _add(rows, '계약일', formatDate(tx.contractedOn));

  if (tx.cancelled) {
    _add(
      rows,
      '해제',
      formatDate(tx.cancelledOn).isEmpty
          ? '해제된 거래'
          : '해제 (${formatDate(tx.cancelledOn)})',
    );
  }
  return DetailSection('거래', rows);
}

DetailSection _buildingSection(TxRow tx, Map<String, dynamic> raw) {
  final rows = <DetailRow>[];
  _add(rows, '단지 · 건물명', tx.name ?? '');
  _add(rows, '면적', formatArea(tx.areaSqm));
  _add(rows, '연면적', _areaText(_text(raw, 'totalFloorAr')));
  _add(rows, '대지면적', _areaText(_text(raw, 'plottageAr')));
  _add(rows, '대지권면적', _areaText(_text(raw, 'landAr')));
  if (tx.floor != null) _add(rows, '층', '${tx.floor}층');
  if (tx.builtYear != null) _add(rows, '건축년도', '${tx.builtYear}년');
  _add(rows, '주택유형', _text(raw, 'houseType'));
  _add(rows, '지목', _text(raw, 'jimok'));
  _add(rows, '용도지역', _text(raw, 'landUse'));
  return DetailSection('건물', rows);
}

String _areaText(String value) {
  if (_blank(value)) return '';
  final parsed = double.tryParse(value);
  return parsed == null ? value : formatArea(parsed);
}

DetailSection _locationSection(TxRow tx) {
  final rows = <DetailRow>[];
  _add(rows, '주소', [tx.umdNm, tx.jibun].where((s) => !_blank(s)).join(' '));
  _add(
    rows,
    '좌표 정확도',
    tx.lat == null
        ? '미확인 (지도에 표시하지 않음)'
        : _precisionLabels[tx.precision] ?? tx.precision,
  );
  return DetailSection('위치', rows);
}

DetailSection _saleSection(Map<String, dynamic> raw) {
  final rows = <DetailRow>[];
  _add(rows, '거래유형', _text(raw, 'dealingGbn'));
  _add(rows, '중개사 소재지', _text(raw, 'estateAgentSggNm'));
  _add(rows, '등기일자', formatDate(_text(raw, 'rgstDate')));
  _add(rows, '매도자', _text(raw, 'slerGbn'));
  _add(rows, '매수자', _text(raw, 'buyerGbn'));
  _add(rows, '동', _text(raw, 'aptDong'));
  final leasehold = _text(raw, 'landLeaseholdGbn');
  if (!_blank(leasehold)) _add(rows, '토지임대부', _yesNo(leasehold));
  _add(rows, '지분거래', _text(raw, 'shareDealingType'));
  return DetailSection('거래 상세', rows);
}

DetailSection _rentSection(TxRow tx, Map<String, dynamic> raw) {
  final rows = <DetailRow>[];
  _add(rows, '계약기간', _text(raw, 'contractTerm'));
  _add(rows, '계약구분', _text(raw, 'contractType'));

  final renewal = _text(raw, 'useRRRight');
  if (!_blank(renewal)) _add(rows, '갱신요구권 사용', _yesNo(renewal));

  final preDeposit = int.tryParse(_text(raw, 'preDeposit').replaceAll(',', ''));
  final preRent = int.tryParse(
    _text(raw, 'preMonthlyRent').replaceAll(',', ''),
  );
  _add(rows, '종전 보증금', formatMoney(preDeposit));
  if ((preRent ?? 0) > 0) _add(rows, '종전 월세', formatMoney(preRent));

  // 이 화면에서 가장 값어치 있는 한 줄이다. 다른 앱이 잘 안 보여주는데 원천에는 있다.
  final change = formatChange(preDeposit, tx.deposit);
  if (change != null) _add(rows, '보증금 변동', change, emphasis: true);
  final rentChange = formatChange(preRent, tx.monthlyRent);
  if (rentChange != null) _add(rows, '월세 변동', rentChange, emphasis: true);

  return DetailSection('계약 조건', rows);
}

/// 표에 못 실은 원문. 우리가 이름을 붙이지 못한 항목도 사용자에게 도달해야 한다.
Map<String, String> _leftover(
  Map<String, dynamic> raw, {
  required bool cancelShown,
}) {
  final left = <String, String>{};
  for (final entry in raw.entries) {
    if (_shownElsewhere.contains(entry.key)) continue;
    if (cancelShown && _cancelFields.contains(entry.key)) continue;
    if (_rawLabels.containsKey(entry.key)) continue;
    final value = entry.value?.toString().trim() ?? '';
    if (value.isEmpty) continue;
    left[entry.key] = value;
  }
  return left;
}
