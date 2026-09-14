/// 검색 — 친 글자로 갈 곳을 고른다.
///
/// **세 갈래를 한 목록에 섞는다.** 사용자는 자기가 치는 것이 시군구인지 법정동인지
/// 단지 이름인지 구분해서 치지 않는다. "중곡"은 동 이름이고 "해운대"는 구 이름인데,
/// 그것을 먼저 고르게 하면 검색이 아니라 분류 작업이 된다.
///
///   1. **시군구** — 전국. 이미 받아 둔 지역 색인에서.
///   2. **법정동** — 전국. 따로 받는 색인에서(`umd_index.dart`).
///   3. **단지·지번** — **지금 보는 지역만.** 그 지역의 거래에서 뽑는다.
///
/// 3번이 현재 지역에 갇히는 것은 거래 자료가 그렇기 때문이다. 앱은 사용자가 연
/// 지역만 내려받는다 — 전국 단지명을 검색하려면 전국 거래를 다 들고 있어야 하고,
/// 그것은 이 앱이 하지 않기로 한 일이다.
///
/// **도로명은 풀리지 않는다.** "테헤란로 123"은 지오코딩이 필요하고, 그 길은 키
/// 유출과 응답 저장 금지로 이미 접었다. 여기서 답할 수 있는 것은 동 이름까지다.
library;

// `geo.dart`(LatLng)는 region_index.dart가 다시 내보낸다.
import '../sync/region_index.dart';
import 'text_match.dart';
import 'umd_index.dart';

export 'text_match.dart';

/// 무엇을 고른 것인가. 고른 뒤에 하는 일이 갈린다.
enum PlaceKind {
  /// 시군구. 지역을 바꾸고 그 지역 전체가 보이게 연다
  region,

  /// 법정동. 다른 지역이면 지역까지 바꾸고, 그 동 중심으로 간다
  umd,

  /// 이 지역 안의 단지·지번. 그 좌표로 간다
  place,
}

class PlaceHit {
  const PlaceHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.sggCd,
    required this.center,
    required this.score,
  });

  final PlaceKind kind;

  /// 굵게 나오는 줄. 사용자가 친 것과 맞은 이름이다
  final String title;

  /// 어디에 있는 것인지. 같은 이름의 동이 전국에 여럿이라 이것이 없으면 고를 수 없다
  final String subtitle;

  final String sggCd;
  final LatLng center;
  final int score;
}

/// 이 지역 거래에서 뽑아 둔 갈 만한 자리 하나.
class LocalPlace {
  LocalPlace({
    required this.umdNm,
    required this.jibun,
    required this.name,
    required this.center,
  });

  final String umdNm;

  /// 가려진 지번(`3**`)은 여기까지 오지 않는다 — 좌표가 없기 때문이다
  final String jibun;

  /// 단지·건물명. 없는 거래가 많다
  final String name;
  final LatLng center;

  /// 맞춰 볼 글자. 동·지번·이름을 한 줄로 이어 "중곡동 12-3"과 "아델리아"가
  /// 같은 후보에서 둘 다 걸리게 한다.
  ///
  /// **한 번만 만든다.** 강남구 한 곳이 수천 줄인데 글자마다 다시 다듬으면
  /// 그 비용이 키를 누를 때마다 든다. 초성은 자음만 친 검색어에서만 쓰이므로
  /// 그때까지 미뤄 둔다.
  late final String normalized = normalizeQuery('$umdNm $jibun $name');
  late final String choseong = choseongOf(normalized);

  String get label => name.isNotEmpty ? name : '$umdNm $jibun';
  String get where => name.isNotEmpty ? '$umdNm $jibun' : umdNm;
}

/// 한 번에 보여줄 수. 넘치면 스크롤이 되는데, 검색 결과를 스크롤해 찾을 바에는
/// 글자를 한 자 더 치는 편이 빠르다.
const int kMaxHits = 12;

/// 한 글자로는 찾지 않는다. "동"을 치면 전국이 다 걸려 목록이 무의미해지고,
/// 18,696개를 훑는 일이 글자마다 일어난다.
const int kMinQueryLength = 2;

/// 아직 **답할 수 없는** 상태인가 — 찾은 것이 없는 것과 다르다.
///
/// 지역 목록을 아직 못 받았으면 시군구도 법정동도 통째로 빠진다. 그때 "찾는 것이
/// 없습니다"라고 하면 거짓말이 된다. 사용자는 동 이름을 잘못 안 줄 알고 다시 치는데,
/// 몇 번을 쳐도 같은 답이 나온다.
bool searchUnavailable(RegionIndex? regions) =>
    regions == null || regions.regions.isEmpty;

/// 검색어로 갈 곳을 고른다.
///
/// [regions]는 전국 시군구, [umds]는 전국 법정동, [local]은 **지금 보는 지역**의
/// 단지·지번이다.
///
/// **법정동은 [regions]가 있어야 나온다.** 같은 이름의 동이 전국에 여럿이라
/// (효자동·사직동…) 어느 구인지 못 붙이면 목록에서 고를 수가 없다. 시군구 코드를
/// 대신 보여주는 것은 답이 아니다 — 다섯 자리 숫자는 사용자에게 아무 뜻이 없다.
/// 그래서 지역 색인을 아직 못 받았으면 동은 **없는 것이 아니라 답할 수 없는 것**이고,
/// 화면은 그 둘을 다르게 말한다([searchUnavailable]).
List<PlaceHit> searchPlaces({
  required String query,
  RegionIndex? regions,
  UmdIndex? umds,
  List<LocalPlace> local = const [],
  int limit = kMaxHits,
}) {
  final q = Query(query);
  if (q.length < kMinQueryLength) return const [];

  final hits = <PlaceHit>[];

  for (final region in regions?.regions ?? const <RegionSummary>[]) {
    if (!region.hasMap) continue;
    // 시군구는 "강남구"로도 "서울특별시 강남구"로도 친다.
    final score = _best(q, [region.displayName, region.name]);
    if (score == 0) continue;
    hits.add(
      PlaceHit(
        kind: PlaceKind.region,
        title: region.displayName,
        subtitle: region.sidoName,
        sggCd: region.sggCd,
        center: region.center!,
        score: score,
      ),
    );
  }

  for (final umd in umds?.entries ?? const <UmdEntry>[]) {
    final score = scoreOn(umd.normalized, umd.choseong, q);
    if (score == 0) continue;
    // 같은 이름의 동이 전국에 여럿이다(효자동·사직동…). 어느 구인지 못 붙이면
    // 고를 수가 없으므로, 지역 색인에 없는 시군구의 동은 내보내지 않는다.
    final region = regions?.byCode(umd.sggCd);
    if (region == null) continue;
    hits.add(
      PlaceHit(
        kind: PlaceKind.umd,
        title: umd.name,
        subtitle: '${region.sidoName} ${region.displayName}'.trim(),
        sggCd: umd.sggCd,
        center: umd.center,
        score: score,
      ),
    );
  }

  for (final place in local) {
    final score = scoreOn(place.normalized, place.choseong, q);
    if (score == 0) continue;
    hits.add(
      PlaceHit(
        kind: PlaceKind.place,
        title: place.label,
        subtitle: place.where,
        sggCd: '',
        center: place.center,
        score: score,
      ),
    );
  }

  hits.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    // 점수가 같으면 넓은 것부터. 지역을 찾는 사람에게 단지 이름을 먼저 보이면
    // 목록 맨 위가 늘 엉뚱한 것이 된다.
    if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
    return a.title.compareTo(b.title);
  });
  return hits.length > limit ? hits.sublist(0, limit) : hits;
}

int _best(Query query, List<String> texts) {
  var best = 0;
  for (final text in texts) {
    final score = scoreOn(normalizeQuery(text), null, query);
    if (score > best) best = score;
  }
  return best;
}
