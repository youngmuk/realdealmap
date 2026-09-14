/// 건물 외곽선 — 상세창이 "이 거래가 어느 건물인가"를 보여 주는 근거.
///
/// **왜 필요한가.** 지도의 핀은 점 하나다. 건물이 맞닿은 주거지에서는 그 점이
/// 어느 건물을 가리키는지 사람이 구별할 수 없고, 실거래가라는 정보의 성격상
/// 그 오해는 값을 잘못 읽는 것으로 이어진다. 배경지도의 OSM 건물로는 광진구에서
/// 거래 건물의 13.5%만 덮었다. 행정안전부 도로명주소 건물 도형은 같은 곳에서
/// **99.9%**다(`Doc/건물외곽선-파이프라인.html`).
///
/// **어떻게 오나.** 시군구마다 목차 하나, 법정동마다 조각 하나다.
///
///     v1/shapes/{시군구}/index.json          ← 법정동명 → 조각들
///     v1/shapes/{시군구}/{법정동}.{n}.json.gz ← 지번 → 바깥 링
///
/// 큰 동은 지번을 **사전 순**으로 끊어 여러 조각이 된다. 어느 조각인지는 목차의
/// `from`~`to`가 정한다 — **문자열 비교 그대로다.** `산 12`·`12-3`을 숫자로 읽는
/// 규칙을 굽는 쪽과 앱이 따로 두면 어긋나는 날 조각을 잘못 골라
/// **멀쩡한 건물이 "도형 없음"으로 보인다.** 화면에서는 자료가 없는 것과 구별되지 않는다.
///
/// **없으면 없는 대로 둔다.** 아직 올리지 않은 자료이므로(국외 반출 답변 대기)
/// 404·오프라인·형식 오류는 전부 `null`이고, 상세창은 그 자리를 통째로 감춘다.
/// 빈 상자를 남기면 "불러오지 못했다"로 읽힌다.
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';

import 'geo.dart';
import 'remote.dart';

export 'geo.dart';

/// 아는 판. 앞으로 나온 판은 통째로 버린다 — 반쯤 읽으면 무엇이 옛 규칙으로
/// 들어왔는지 알 수 없다.
const int kSupportedShapeVersion = 1;

/// 링 하나. `[경도, 위도, 경도, 위도, ...]`로 평평하다.
typedef Outline = Float64List;

/// 목차에 적힌 조각 하나.
class ShapePart {
  const ShapePart({required this.file, required this.from, required this.to});

  final String file;

  /// 이 조각이 담은 첫 지번(사전 순, 포함)
  final String from;

  /// 마지막 지번(포함)
  final String to;

  bool holds(String jibun) =>
      from.compareTo(jibun) <= 0 && jibun.compareTo(to) <= 0;

  static ShapePart? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final file = raw['file'];
    final from = raw['from'];
    final to = raw['to'];
    if (file is! String || from is! String || to is! String) return null;
    if (file.isEmpty) return null;
    return ShapePart(file: file, from: from, to: to);
  }
}

/// 법정동 하나의 조각 목록.
class ShapeDong {
  const ShapeDong({required this.bjdCd, required this.parts});

  final String bjdCd;
  final List<ShapePart> parts;

  /// 지번이 든 조각. 없으면 `null` — 그 동에 그 지번이 없는 것이다.
  ShapePart? partFor(String jibun) {
    for (final part in parts) {
      if (part.holds(jibun)) return part;
    }
    return null;
  }
}

/// 시군구 하나의 목차.
class ShapeCatalog {
  const ShapeCatalog({
    required this.sggCd,
    required this.source,
    required this.dongs,
  });

  final String sggCd;

  /// 원자료 시점(`20260901`). 화면에 "언제 자료인지"를 밝히는 데 쓴다
  final String source;

  /// 법정동명 → 조각들
  final Map<String, ShapeDong> dongs;

  ShapePart? partFor(String umdNm, String jibun) =>
      dongs[umdNm]?.partFor(jibun);

  static ShapeCatalog? decode(Uint8List bytes) {
    final decoded = _readJson(bytes);
    if (decoded == null) return null;
    if (decoded['schemaVersion'] != kSupportedShapeVersion) return null;

    final sggCd = decoded['sggCd'];
    final dongs = decoded['dongs'];
    if (sggCd is! String || dongs is! Map) return null;

    final table = <String, ShapeDong>{};
    for (final entry in dongs.entries) {
      final name = entry.key;
      final value = entry.value;
      if (name is! String || value is! Map<String, dynamic>) continue;
      final bjdCd = value['bjdCd'];
      final parts = value['parts'];
      if (bjdCd is! String || parts is! List) continue;
      final read = parts
          .map(ShapePart.fromJson)
          .whereType<ShapePart>()
          .toList(growable: false);
      if (read.isEmpty) continue;
      table[name] = ShapeDong(bjdCd: bjdCd, parts: read);
    }
    if (table.isEmpty) return null;

    final source = decoded['source'];
    return ShapeCatalog(
      sggCd: sggCd,
      source: source is String ? source : '',
      dongs: table,
    );
  }
}

/// 법정동 조각 하나의 알맹이.
///
/// 모양을 따로 두고 지번이 번호로 가리킨다. 한 건물에 지번이 여럿 딸리는 일이
/// 흔해서(관련지번) 지번마다 모양을 복사하면 같은 건물이 파일 안에 여러 번 들어간다.
class DongShapes {
  const DongShapes({
    required this.shapes,
    required this.buildings,
    required this.attribution,
    required this.source,
  });

  final List<Outline> shapes;

  /// 지번 → [shapes]의 번호들. **한 지번이 여럿을 가리키는 것이 정상이다** —
  /// 아파트 단지이고, 거래 자료에는 동 번호가 없으므로 단지의 동을 다 그린다.
  final Map<String, List<int>> buildings;

  /// 공공누리 제1유형의 조건. 화면에 그대로 내보인다
  final String attribution;
  final String source;

  List<Outline> outlinesFor(String jibun) {
    final ids = buildings[jibun];
    if (ids == null) return const [];
    return [
      for (final id in ids)
        if (id >= 0 && id < shapes.length) shapes[id],
    ];
  }

  static DongShapes? decode(Uint8List bytes) {
    final decoded = _readJson(bytes);
    if (decoded == null) return null;
    if (decoded['schemaVersion'] != kSupportedShapeVersion) return null;

    final rawShapes = decoded['shapes'];
    final rawBuildings = decoded['buildings'];
    if (rawShapes is! List || rawBuildings is! Map) return null;

    final shapes = <Outline>[];
    for (final ring in rawShapes) {
      if (ring is! List) return null;
      // 점 하나는 좌표 둘이다. 홀수면 그 뒤가 전부 한 칸씩 밀린다 —
      // 그림은 그려지는데 자리가 틀린다.
      if (ring.length < 6 || ring.length.isOdd) return null;
      final flat = Float64List(ring.length);
      for (var i = 0; i < ring.length; i++) {
        final value = ring[i];
        if (value is! num) return null;
        flat[i] = value.toDouble();
      }
      shapes.add(flat);
    }

    final buildings = <String, List<int>>{};
    for (final entry in rawBuildings.entries) {
      final jibun = entry.key;
      final ids = entry.value;
      if (jibun is! String || ids is! List) continue;
      buildings[jibun] = [
        for (final id in ids)
          if (id is int && id >= 0 && id < shapes.length) id,
      ];
    }
    if (buildings.isEmpty) return null;

    final attribution = decoded['attribution'];
    final source = decoded['source'];
    return DongShapes(
      shapes: shapes,
      buildings: buildings,
      attribution: attribution is String ? attribution : '',
      source: source is String ? source : '',
    );
  }
}

/// 그림 하나에 들어갈 것. 이 거래의 건물과, 자리를 알아볼 만큼의 이웃.
class BuildingOutlines {
  const BuildingOutlines({
    required this.target,
    required this.neighbours,
    required this.attribution,
    required this.source,
  });

  /// 이 거래의 건물들. 비면 그릴 것이 없다
  final List<Outline> target;

  /// 둘레의 건물들. **옅게 그린다** — 없으면 외곽선 하나가 허공에 뜬 것처럼 보여
  /// 어느 방향이 길인지조차 알 수 없다
  final List<Outline> neighbours;

  final String attribution;
  final String source;

  bool get isEmpty => target.isEmpty;
}

/// 링의 경계상자.
BoundingBox outlineBounds(Iterable<Outline> outlines) {
  var south = double.infinity;
  var north = double.negativeInfinity;
  var west = double.infinity;
  var east = double.negativeInfinity;
  for (final ring in outlines) {
    for (var i = 0; i < ring.length; i += 2) {
      final lng = ring[i];
      final lat = ring[i + 1];
      if (lng < west) west = lng;
      if (lng > east) east = lng;
      if (lat < south) south = lat;
      if (lat > north) north = lat;
    }
  }
  return BoundingBox(south: south, north: north, west: west, east: east);
}

/// 이웃으로 칠 만큼의 여유. 위도 1도는 약 111km다.
const double _neighbourMarginDegrees = 0.0007; // 약 78m

/// 한 그림에 그릴 이웃의 상한.
///
/// 없으면 신림동 같은 조각에서 수천 개를 그린다. 상세창을 여는 동안 프레임이
/// 끊기는데, 원인이 그림이라는 것은 화면만 봐서는 알 수 없다.
///
/// **이웃은 같은 조각 안에서만 고른다.** 조각은 지번 순으로 끊은 것이라 경계 너머의
/// 옆 건물은 다른 파일에 있다. 그것까지 받으려면 상세창 하나에 수백 KB를 더 쓰는데,
/// 이 그림이 말하는 것은 "이 건물이 어느 것인가"이지 "동네에 건물이 몇 채인가"가
/// 아니다. 옅은 회색은 자리를 가늠하라고 깔아 둔 바탕이다.
const int _maxNeighbours = 600;

/// [target] 둘레의 건물을 고른다.
///
/// 여유는 **대상의 크기에 맞춰 넓힌다.** 고정폭으로 두면 단지처럼 큰 대상에서는
/// 그림 범위가 여유보다 넓어져 가장자리가 텅 빈 채로 나온다 — 실제로 자양동
/// 단지에서 그랬다. 그러면 이웃을 그리는 값어치(자리를 알아보게 하는 것)가 사라진다.
List<Outline> neighboursAround(
  List<Outline> shapes,
  List<Outline> target, {
  double? margin,
  int limit = _maxNeighbours,
}) {
  if (target.isEmpty) return const [];
  final box = outlineBounds(target);
  final span = math.max(box.north - box.south, box.east - box.west);
  final pad = margin ?? math.max(_neighbourMarginDegrees, span * 0.6);
  final south = box.south - pad;
  final north = box.north + pad;
  final west = box.west - pad;
  final east = box.east + pad;

  final centreLat = (box.south + box.north) / 2;
  final centreLng = (box.west + box.east) / 2;

  final picked = <({Outline ring, double distance})>[];
  for (final ring in shapes) {
    if (target.contains(ring)) continue;
    final bounds = outlineBounds([ring]);
    if (bounds.north < south ||
        bounds.south > north ||
        bounds.east < west ||
        bounds.west > east) {
      continue;
    }
    final dLat = (bounds.south + bounds.north) / 2 - centreLat;
    final dLng = (bounds.west + bounds.east) / 2 - centreLng;
    picked.add((ring: ring, distance: dLat * dLat + dLng * dLng));
  }

  // **가까운 것부터 남긴다.** 파일에 담긴 차례로 자르면 상한에 걸렸을 때
  // 이웃이 한쪽에만 남아, 건물이 동네 가장자리에 있는 것처럼 보인다.
  if (picked.length > limit) {
    picked.sort((a, b) => a.distance.compareTo(b.distance));
    picked.removeRange(limit, picked.length);
  }
  return [for (final entry in picked) entry.ring];
}

/// 큰 대상과 작은 대상을 가르는 선. 약 166m다.
const double _largeTargetDegrees = 0.0015;

/// 그림이 담을 범위. 건물이 화면을 꽉 채우면 어디에 붙어 있는지 안 보인다.
///
/// 여백 비율을 대상 크기에 따라 달리 두는 이유는, **큰 단지에 같은 비율을 주면
/// 창이 500m를 넘어** 그림이 동네 지도가 되기 때문이다. 그쯤 되면 정작
/// 이 거래의 건물이 작아져 무엇을 가리키는지 흐려진다.
BoundingBox outlineWindow(List<Outline> target, {double? padRatio}) {
  final box = outlineBounds(target);
  final height = math.max(box.north - box.south, 1e-6);
  final width = math.max(box.east - box.west, 1e-6);
  final span = math.max(height, width);
  final ratio = padRatio ?? (span > _largeTargetDegrees ? 0.3 : 0.55);
  final pad = math.max(span * ratio, 0.00012);
  return BoundingBox(
    south: box.south - pad,
    north: box.north + pad,
    west: box.west - pad,
    east: box.east + pad,
  );
}

/// gzip이면 풀어서 JSON으로 읽는다. 형식이 어긋나면 `null`.
///
/// R2에 `content-encoding: gzip`으로 올리므로 **대개** HTTP 클라이언트가 알아서
/// 푼다. 그러나 중간 프록시나 다른 호스트를 거치면 압축된 채로 오기도 한다 —
/// 앞 두 바이트를 보고 우리가 푼다. `sync_engine.dart`가 청크에 쓰는 것과 같은 규칙이다.
Map<String, dynamic>? _readJson(Uint8List bytes) {
  try {
    final raw = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        ? Uint8List.fromList(gzip.decode(bytes))
        : bytes;
    final decoded = jsonDecode(utf8.decode(raw));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  } on Exception {
    // gzip.decode는 깨진 바이트에 FormatException이 아닌 것도 던진다.
    return null;
  }
}

/// 목차와 조각을 받아 두고 필요한 것만 내주는 곳.
///
/// **같은 것을 두 번 받지 않는다.** 상세창은 목록에서 연달아 열리는데, 그때마다
/// 같은 법정동 조각을 다시 받으면 사용자 회선으로 수십 KB씩 흘린다.
/// 진행 중인 요청도 함께 담아 둔다 — 빠르게 두 번 열면 요청도 두 번 나간다.
class BuildingShapeStore {
  BuildingShapeStore(this._remote);

  final RemoteSource _remote;

  /// 목차는 작다(중앙값 12KB). 앱이 사는 동안 들고 있는다
  final Map<String, Future<ShapeCatalog?>> _catalogs = {};

  /// 조각은 수십~수백 KB다. 최근 것만 남긴다
  final Map<String, Future<DongShapes?>> _parts = {};

  /// 들고 있을 조각 수. 사용자는 대개 한 동네를 훑는다
  static const int maxCachedParts = 4;

  static String catalogKey(String sggCd) => 'v1/shapes/$sggCd/index.json';
  static String partKey(String sggCd, String file) => 'v1/shapes/$sggCd/$file';

  /// 이 지번으로 건물을 짚을 수 있나.
  ///
  /// 원천이 지번을 가린 거래가 있다(`3**`). 단독다가구·토지가 그렇고 강남구
  /// 표본에서 14.3%였다. 가려진 번호로는 건물을 고를 수 없으므로 **아예 묻지 않는다** —
  /// 비슷한 번호의 남의 건물을 그리는 것이 빈자리보다 나쁘다.
  static bool canLocate(String? jibun) =>
      jibun != null && jibun.trim().isNotEmpty && !jibun.contains('*');

  /// 이 거래의 건물 외곽선. 없거나 못 받으면 `null`.
  Future<BuildingOutlines?> outlines({
    required String sggCd,
    required String umdNm,
    required String? jibun,
  }) async {
    if (!canLocate(jibun)) return null;
    final key = jibun!.trim();

    final catalog = await _catalog(sggCd);
    if (catalog == null) return null;
    final part = catalog.partFor(umdNm, key);
    if (part == null) return null;

    final dong = await _part(sggCd, part.file);
    if (dong == null) return null;

    final target = dong.outlinesFor(key);
    if (target.isEmpty) return null;

    return BuildingOutlines(
      target: target,
      neighbours: neighboursAround(dong.shapes, target),
      attribution: dong.attribution,
      source: dong.source.isNotEmpty ? dong.source : catalog.source,
    );
  }

  Future<ShapeCatalog?> _catalog(String sggCd) {
    final cached = _catalogs[sggCd];
    if (cached != null) return cached;
    final fetching = _fetch(
      catalogKey(sggCd),
      ShapeCatalog.decode,
      onFail: () => _catalogs.remove(sggCd),
    );
    _catalogs[sggCd] = fetching;
    return fetching;
  }

  Future<DongShapes?> _part(String sggCd, String file) {
    final key = partKey(sggCd, file);
    final cached = _parts[key];
    if (cached != null) return cached;

    final fetching = _fetch(
      key,
      DongShapes.decode,
      onFail: () => _parts.remove(key),
    );
    _parts[key] = fetching;
    // 가장 오래 전에 담은 것부터 버린다. Dart의 Map은 넣은 차례를 지킨다.
    while (_parts.length > maxCachedParts) {
      _parts.remove(_parts.keys.first);
    }
    return fetching;
  }

  /// 받아서 해석한다. **어떤 실패도 밖으로 던지지 않는다** — 이 그림은 있으면
  /// 좋은 것이지, 없다고 상세창이 열리지 않아야 할 이유가 아니다.
  ///
  /// **못 받은 것은 기억하지 않는다.** 지하철에서 한 번 끊긴 것을 캐시에 남기면
  /// 그 지역의 그림이 앱을 다시 켤 때까지 영영 안 나온다. 반면 404(아직 올리지
  /// 않은 지역)는 기억한다 — 다시 물어도 답이 같다.
  Future<T?> _fetch<T>(
    String key,
    T? Function(Uint8List) decode, {
    required void Function() onFail,
  }) async {
    try {
      final bytes = await _remote.get(key);
      if (bytes == null) return null;
      return decode(bytes);
    } on RemoteException {
      onFail();
      return null;
    }
  }
}
