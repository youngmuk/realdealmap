/// 화면에 숫자를 내는 규칙.
///
/// 원천은 금액을 **만원 단위 정수**로 준다(`320000` = 32억). 그대로 보여주면
/// 아무도 못 읽고, 억 단위로만 줄이면 "3억 2천"과 "3억 2백"이 같아 보인다.
library;

/// 만원 단위 금액을 사람이 읽는 문자열로.
///
///   320000 → 32억
///   325000 → 32억 5,000만원
///   9500   → 9,500만원
///   0      → 0원  (해제 거래 등에서 실제로 나온다)
String formatMoney(int? manwon) {
  if (manwon == null) return '';
  if (manwon == 0) return '0원';

  final negative = manwon < 0;
  final value = manwon.abs();
  final eok = value ~/ 10000;
  final rest = value % 10000;

  final String text;
  if (eok == 0) {
    text = '${_comma(rest)}만원';
  } else if (rest == 0) {
    text = '$eok억';
  } else {
    text = '$eok억 ${_comma(rest)}만원';
  }
  return negative ? '-$text' : text;
}

/// 전월세 한 줄. 월세가 0이면 전세다 — 원천이 그렇게 표현한다.
String formatRent(int? deposit, int? monthlyRent) {
  final d = formatMoney(deposit);
  if (monthlyRent == null || monthlyRent == 0) {
    return d.isEmpty ? '' : '전세 $d';
  }
  return '$d / ${_comma(monthlyRent)}만원';
}

/// 면적. 제곱미터가 원문이고 평은 참고로 붙인다.
String formatArea(double? sqm) {
  if (sqm == null) return '';
  final pyeong = sqm / 3.305785;
  return '${_trim(sqm)}m² (${pyeong.toStringAsFixed(1)}평)';
}

/// 갱신 계약의 인상폭 (§상세정보명세). 이 화면에서 가장 값어치 있는 한 줄이다.
///
/// 종전 값이 없거나 0이면 계산하지 않는다 — 0에서 오른 것을 무한대로 쓸 수는 없다.
String? formatChange(int? before, int? after) {
  if (before == null || after == null || before == 0) return null;
  final delta = after - before;
  if (delta == 0) return '동결';
  final percent = delta / before * 100;
  final sign = delta > 0 ? '+' : '';
  return '$sign${formatMoney(delta)} ($sign${percent.toStringAsFixed(1)}%)';
}

/// `20260814` 또는 `2026-08-14` → `2026.08.14`
String formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 8) return raw;
  return '${digits.substring(0, 4)}.${digits.substring(4, 6)}.${digits.substring(6)}';
}

/// `202608` → `2026년 8월`
String formatMonth(String period) {
  if (period.length != 6) return period;
  final month = int.tryParse(period.substring(4));
  if (month == null) return period;
  return '${period.substring(0, 4)}년 $month월';
}

/// 기준 시각을 "몇 분 전"으로. 절대 시각도 같이 보여줄 것이라 여기는 짧게 쓴다.
String formatAge(DateTime refreshedAt, DateTime now) {
  final diff = now.difference(refreshedAt);
  if (diff.isNegative || diff.inMinutes < 1) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}

String _comma(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i += 1) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// 소수점 뒤 0을 지운다. `84.97` → `84.97`, `84.00` → `84`
String _trim(double value) {
  final text = value.toStringAsFixed(2);
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 천 단위로 끊는다.
///
/// 20648과 20,648은 읽는 속도가 다르다. 지도 위 문장은 스치듯 읽히므로
/// 자릿수를 셀 필요가 없어야 한다.
String formatCount(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i += 1) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
