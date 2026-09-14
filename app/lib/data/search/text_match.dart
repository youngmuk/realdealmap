/// 친 글자와 후보 이름을 맞추는 규칙.
///
/// 검색(`place_search.dart`)과 동 색인(`umd_index.dart`)이 **둘 다** 쓴다.
/// 한쪽에 두면 두 파일이 서로를 import하게 되어, 어느 쪽이 규칙의 주인인지
/// 알 수 없어진다.
///
/// 굽는 쪽(`packages/ingest/src/search.ts`)과 같은 규칙이어야 한다. 둘이
/// 어긋나면 색인을 확인한 결과와 화면에 나오는 결과가 달라진다.
library;

/// 정규식은 **한 번만 만든다.** 함수 안에 두면 후보 하나마다 새로 컴파일되는데,
/// 후보가 18,696개다.
final RegExp _spaces = RegExp(r'\s+');
final RegExp _onlyChoseong = RegExp('^[ㄱ-ㅎ]+\$');

/// 검색어와 후보를 같은 모양으로 만든다. 공백을 지우는 이유는 사람이
/// "중곡 동"과 "중곡동"을 같은 것으로 치기 때문이다.
String normalizeQuery(String s) => s.toLowerCase().replaceAll(_spaces, '');

const List<String> _choseong = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', //
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

const int _hangulBase = 0xac00;
const int _hangulLast = 0xd7a3;

/// 한 초성이 거느리는 음절 수 = 중성 21 × 종성 28
const int _perChoseong = 588;

/// "중곡동" → "ㅈㄱㄷ".
///
/// 초성 검색은 오타 보정이 아니라 **속도**다. 휴대폰에서 "ㅈㄱㄷ"은 세 번
/// 두드리면 끝나는데 "중곡동"은 여덟 번이다.
String choseongOf(String s) {
  final out = StringBuffer();
  for (final rune in s.runes) {
    if (rune >= _hangulBase && rune <= _hangulLast) {
      out.write(_choseong[(rune - _hangulBase) ~/ _perChoseong]);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// 자음만 친 검색어인가.
bool isChoseongQuery(String q) => q.isNotEmpty && _onlyChoseong.hasMatch(q);

/// 해석해 둔 검색어.
///
/// **한 번 치는 동안 한 번만 만든다.** 이것이 없을 때는 "자음만 친 검색어인가"를
/// 후보마다 다시 따졌다 — 후보가 18,696개이므로 정규식을 그만큼 돌린 셈이다.
class Query {
  factory Query(String raw) {
    final text = normalizeQuery(raw);
    return Query._(text, isChoseongQuery(text));
  }

  const Query._(this.text, this.isChoseong);

  /// 공백을 지우고 소문자로 만든 글자
  final String text;

  /// 자음만 쳤는가. 그렇다면 초성으로도 맞춰 본다
  final bool isChoseong;

  int get length => text.length;
  bool get isEmpty => text.isEmpty;
}

/// 후보 하나의 점수. 0이면 안 맞는 것이다.
///
/// **앞에서 맞는 것을 위로 올린다.** "중곡"을 쳤을 때 "중곡동"이 "용중곡리"보다
/// 위에 있어야 한다 — 사람은 이름의 앞을 치지 가운데를 치지 않는다.
///
/// 굽는 쪽(`packages/ingest/src/search.ts`)과 같은 규칙이다. 둘이 어긋나면
/// 색인을 확인한 결과와 화면에 나오는 결과가 달라진다.
int scoreOf(String text, String query) =>
    scoreOn(normalizeQuery(text), null, Query(query));

/// [normalized]는 이미 다듬은 글자, [choseong]은 미리 뽑아 둔 초성이다.
///
/// **후보 쪽에서 미리 만들어 두는 것이 핵심이다.** 전국 법정동 18,696개로 실측하니
/// 한 번 검색이 10.1ms였는데, 다듬기·초성 뽑기를 후보가 들고 있게 하고(`late final`)
/// 검색어 해석을 한 번으로 줄이자 0.92ms가 됐다. 치는 동안 매 글자 드는 비용이라
/// 그 차이가 그대로 손끝에 온다.
///
/// [choseong]이 `null`이면 필요할 때만 그 자리에서 뽑는다 — 시군구는 256개뿐이라
/// 미리 만들어 둘 값어치가 없다.
int scoreOn(String normalized, String? choseong, Query query) {
  final q = query.text;
  if (q.isEmpty) return 0;
  if (normalized == q) return 1000;
  if (normalized.startsWith(q)) {
    return 700 - (normalized.length > 99 ? 99 : normalized.length);
  }
  if (normalized.contains(q)) {
    return 400 - (normalized.length > 99 ? 99 : normalized.length);
  }

  // 초성은 글자로 맞지 않을 때만 본다. 그러지 않으면 "ㄱㄴ" 같은 짧은 검색어가
  // 온 나라를 다 끌어온다.
  if (query.isChoseong) {
    final cho = choseong ?? choseongOf(normalized);
    final penalty = cho.length > 99 ? 99 : cho.length;
    if (cho.startsWith(q)) return 300 - penalty;
    if (cho.contains(q)) return 150 - penalty;
  }
  return 0;
}
