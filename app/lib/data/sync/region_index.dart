/// 지역 색인 — "지금 보는 자리가 어느 시군구인가"를 푸는 유일한 근거.
///
/// 경계 폴리곤이 없어서 생긴 자리다. 서버가 **실제로 배포한 거래의 좌표**에서
/// 경계상자를 뽑아 올려 준다(`v1/regions/index.json`). 행정 경계는 아니지만
/// 앱이 필요한 것은 "어느 지역 데이터를 받을까"지 법정 경계가 아니다.
///
/// 앱에서 역지오코딩을 하지 않는 이유는 키다. 배포된 앱에서 키를 빼내는 것은
/// 막을 수 없고, 그러면 우리 쿼터를 아무나 쓰게 된다.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'remote.dart';

const int kSupportedIndexVersion = 1;

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

class BoundingBox {
  const BoundingBox({
    required this.south,
    required this.north,
    required this.west,
    required this.east,
  });

  final double south;
  final double north;
  final double west;
  final double east;

  bool contains(LatLng p) =>
      p.lat >= south && p.lat <= north && p.lng >= west && p.lng <= east;

  static BoundingBox? tryFrom(Map<String, dynamic>? json) {
    if (json == null) return null;
    final s = json['south'],
        n = json['north'],
        w = json['west'],
        e = json['east'];
    if (s is! num || n is! num || w is! num || e is! num) return null;
    return BoundingBox(
      south: s.toDouble(),
      north: n.toDouble(),
      west: w.toDouble(),
      east: e.toDouble(),
    );
  }
}

class RegionSummary {
  const RegionSummary({
    required this.sggCd,
    required this.name,
    required this.sidoName,
    required this.sggName,
    required this.records,
    required this.located,
    required this.refreshedAt,
    this.bbox,
    this.center,
  });

  final String sggCd;
  final String name;
  final String sidoName;
  final String sggName;
  final int records;

  /// 좌표가 붙은 거래 수. `records - located`가 지도에 못 그리는 건수다
  final int located;
  final String refreshedAt;

  /// 좌표가 하나도 없는 지역은 없다. 그때 지도를 열 자리가 없기 때문이다
  final BoundingBox? bbox;
  final LatLng? center;

  bool get hasMap => bbox != null && center != null;

  factory RegionSummary.fromJson(Map<String, dynamic> json) {
    final center = json['center'] as Map<String, dynamic>?;
    return RegionSummary(
      sggCd: json['sggCd'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sidoName: json['sidoName'] as String? ?? '',
      sggName: json['sggName'] as String? ?? '',
      records: (json['records'] as num?)?.toInt() ?? 0,
      located: (json['located'] as num?)?.toInt() ?? 0,
      refreshedAt: json['refreshedAt'] as String? ?? '',
      bbox: BoundingBox.tryFrom(json['bbox'] as Map<String, dynamic>?),
      center: center == null
          ? null
          : LatLng(
              (center['lat'] as num).toDouble(),
              (center['lng'] as num).toDouble(),
            ),
    );
  }
}

class RegionIndex {
  const RegionIndex(this.regions);

  final List<RegionSummary> regions;

  static const RegionIndex empty = RegionIndex(<RegionSummary>[]);

  bool get isEmpty => regions.isEmpty;

  RegionSummary? byCode(String sggCd) {
    for (final r in regions) {
      if (r.sggCd == sggCd) return r;
    }
    return null;
  }

  /// 시도 → 시군구. 지역 선택 화면이 이 순서로 보여준다.
  Map<String, List<RegionSummary>> get bySido {
    final grouped = <String, List<RegionSummary>>{};
    for (final r in regions) {
      (grouped[r.sidoName] ??= []).add(r);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.sggName.compareTo(b.sggName));
    }
    return grouped;
  }

  /// 이 자리를 담는 지역.
  ///
  /// 경계상자는 실제 경계가 아니라 **거래가 퍼져 있는 범위**라 이웃끼리 겹친다.
  /// 여럿이 걸리면 중심이 가장 가까운 것을 고른다 — 상자 한가운데 있을수록
  /// 그 지역일 가능성이 크다.
  ///
  /// 하나도 담지 못하면 `null`이다. **가장 가까운 것을 억지로 고르지 않는다.**
  /// 아직 배포하지 않은 지역 위에 있는 것인데 엉뚱한 지역 데이터를 보여주면
  /// 사용자는 그 자리의 실거래라고 믿는다.
  RegionSummary? at(LatLng point) {
    RegionSummary? best;
    var bestDistance = double.infinity;

    for (final region in regions) {
      final box = region.bbox;
      final center = region.center;
      if (box == null || center == null || !box.contains(point)) continue;

      final d = _squaredDistance(point, center);
      if (d < bestDistance) {
        bestDistance = d;
        best = region;
      }
    }
    return best;
  }

  /// 내 위치에서 가장 가까운 지역. 첫 진입에서 어디를 열지 정할 때만 쓴다(T5.9).
  ///
  /// [maxDegrees]는 대략 1도 = 111 km다. 기본 1.0도면 부산에 있는데 서울을
  /// 열어 주는 일은 없다 — 그 경우 `null`이고 앱은 지역 선택을 띄운다.
  RegionSummary? nearest(LatLng point, {double maxDegrees = 1.0}) {
    final inside = at(point);
    if (inside != null) return inside;

    RegionSummary? best;
    var bestDistance = maxDegrees * maxDegrees;

    for (final region in regions) {
      final center = region.center;
      if (center == null) continue;
      final d = _squaredDistance(point, center);
      if (d < bestDistance) {
        bestDistance = d;
        best = region;
      }
    }
    return best;
  }
}

/// 경도 1도는 위도에 따라 짧아진다. 그것을 무시하면 남북으로 긴 나라에서
/// 동서 거리를 과대평가해 엉뚱한 지역이 "가깝다"고 나온다.
double _squaredDistance(LatLng a, LatLng b) {
  final dLat = a.lat - b.lat;
  final dLng = (a.lng - b.lng) * math.cos(a.lat * math.pi / 180);
  return dLat * dLat + dLng * dLng;
}

class RegionIndexLoader {
  const RegionIndexLoader(this._remote);
  final RemoteSource _remote;

  static const String key = 'v1/regions/index.json';

  /// 오프라인에서도 지역 이름을 보여주려면 마지막 색인을 기기에 남겨야 한다.
  /// 원문 JSON을 그대로 저장한다 — 별도 직렬화를 만들면 서버 형식이 바뀔 때
  /// 두 곳을 고쳐야 하고, 한쪽을 잊으면 캐시가 조용히 어긋난다.
  static String encode(RegionIndex index) => jsonEncode({
    'version': kSupportedIndexVersion,
    'regions': index.regions.map(_toJson).toList(),
  });

  static RegionIndex? decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final regions = decoded['regions'];
    if (regions is! List) return null;
    return RegionIndex(
      regions
          .whereType<Map<String, dynamic>>()
          .map(RegionSummary.fromJson)
          .toList(growable: false),
    );
  }

  /// 색인을 받는다. 못 받으면 `null` — 호출자가 마지막으로 쓰던 것을 이어 쓴다.
  ///
  /// 여기서 던지지 않는 이유는 **색인이 없다고 앱이 멈추면 안 되기 때문이다.**
  /// 이미 받아 둔 지역이 있으면 오프라인에서도 그 지역은 그대로 보여야 한다(FR-7).
  Future<RegionIndex?> load() async {
    final Object? decoded;
    try {
      final bytes = await _remote.get(key);
      if (bytes == null) return RegionIndex.empty;
      decoded = jsonDecode(utf8.decode(bytes));
    } on RemoteException {
      return null;
    } on FormatException {
      return null;
    }

    if (decoded is! Map<String, dynamic>) return null;
    final version = decoded['version'];
    // 앞으로 나온 판을 반쯤 읽으면 무엇이 옛 규칙으로 들어왔는지 알 수 없다.
    if (version is! int || version > kSupportedIndexVersion) return null;

    final regions = decoded['regions'];
    if (regions is! List) return null;

    return RegionIndex(
      regions
          .whereType<Map<String, dynamic>>()
          .map(RegionSummary.fromJson)
          .where((r) => r.sggCd.length == 5)
          .toList(growable: false),
    );
  }
}

Map<String, dynamic> _toJson(RegionSummary r) => {
  'sggCd': r.sggCd,
  'name': r.name,
  'sidoName': r.sidoName,
  'sggName': r.sggName,
  'records': r.records,
  'located': r.located,
  'refreshedAt': r.refreshedAt,
  if (r.bbox != null)
    'bbox': {
      'south': r.bbox!.south,
      'north': r.bbox!.north,
      'west': r.bbox!.west,
      'east': r.bbox!.east,
    },
  if (r.center != null) 'center': {'lat': r.center!.lat, 'lng': r.center!.lng},
};
