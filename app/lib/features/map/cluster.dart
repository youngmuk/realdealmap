/// 마커 묶기 (T5.4).
///
/// **네이티브 클러스터링을 쓰지 않는다.** maplibre_gl의 `setGeoJsonSource`는
/// `addGeoJsonSource`로 만든 소스에서만 동작하는데(라이브러리 문서에 명시되어 있고
/// 실기기에서 확인했다 — 갱신 후 렌더링되는 점이 1,782개 중 1개였다),
/// 클러스터 옵션은 `addSource` 경로에만 있다. 둘을 동시에 가질 수 없다.
///
/// 잃는 것보다 얻는 것이 많다. **근사 좌표는 줌과 무관하게 항상 묶어야 하는데**
/// 네이티브 옵션으로는 그 규칙을 표현할 수 없다. 여기서는 규칙이 코드라 테스트할 수 있고,
/// 몇천 점을 묶는 비용은 밀리초 단위다.
library;

import 'dart:math' as math;

import '../../data/db/database.dart';

/// 지도에 실제로 그려지는 한 점. 낱개일 수도, 여러 건을 묶은 것일 수도 있다.
class MapFeature {
  const MapFeature({
    required this.lat,
    required this.lng,
    required this.count,
    required this.propertyType,
    required this.approximate,
    this.txId,
    this.sameSpot = false,
  });

  final double lat;
  final double lng;

  /// 묶인 건수. 1이면 낱개다
  final int count;

  /// 대표 매물 유형. 섞여 있으면 가장 많은 것
  final String propertyType;

  /// 하나라도 근사 좌표면 true. **묶음의 위치를 믿으면 안 된다는 뜻이라
  /// 섞였을 때도 경고 쪽으로 기운다** — 조용히 정확한 척하는 것보다 낫다
  final bool approximate;

  /// 낱개일 때만 있다. 탭하면 이것으로 상세를 연다
  final String? txId;

  /// 묶인 것들이 **정확히 같은 좌표**에 있는가.
  ///
  /// 이러면 아무리 확대해도 갈라지지 않는다. 확대로 파고드는 대신 목록을
  /// 열어야 한다는 표시다. 낱개일 때는 의미가 없어 false다.
  final bool sameSpot;

  bool get isCluster => count > 1;
}

/// 한 칸의 크기(논리 픽셀). 이보다 가까운 점들은 한 덩어리로 본다.
///
/// 실기기 화면 폭이 393 논리 픽셀이라 64로 잡으면 가로로 여섯 칸밖에 안 나온다 —
/// 강남구 전체가 스물몇 개의 커다란 원으로 뭉개졌다. 36이면 열한 칸이라
/// 동네 단위의 밀도가 드러난다.
const double kClusterCellPx = 36;

/// 이 줌을 넘으면 묶지 않는다. 낱개를 봐야 하는 배율이다.
const double kClusterMaxZoom = 16;

/// 래스터 타일 한 변의 픽셀. 스타일의 `tileSize`와 같아야 줌 계산이 맞는다.
const double kTileSize = 256;

/// 점들을 화면 격자에 담아 묶는다.
///
/// 격자는 웹 메르카토르 픽셀 좌표 위에 놓는다. 위경도 격자로 나누면 위도가 높을수록
/// 칸이 가로로 늘어나서, 같은 화면 거리인데 남쪽에서는 묶이고 북쪽에서는 안 묶인다.
List<MapFeature> clusterPins(
  List<MapPin> pins,
  double zoom, {
  double cellPx = kClusterCellPx,
  double maxZoom = kClusterMaxZoom,
}) {
  if (pins.isEmpty) return const [];

  // 줌이 충분히 크면 낱개로 그린다. 다만 **근사 좌표는 예외다** —
  // 법정동 중심점이라 같은 동의 수백 건이 정확히 같은 자리에 있고,
  // 낱개로 그리면 한 점에 수백 개가 쌓여 가장 위의 하나만 눌린다.
  final exact = <MapPin>[];
  final approximate = <MapPin>[];
  for (final pin in pins) {
    (pin.isApproximate ? approximate : exact).add(pin);
  }

  final features = <MapFeature>[];
  if (zoom >= maxZoom) {
    // **낱개로 흩어 놓지 않는다.** 좌표 사전은 `법정동|지번 → 한 점`이라
    // 한 아파트 단지의 거래는 전부 같은 좌표를 갖는다. 실제 데이터로 재 보니
    // 동대문구 아파트 전월세 939건이 좌표 155개에 앉아 있고, 한 점에 132건이
    // 겹친 곳도 있었다 — 정확좌표 거래의 94%가 누군가와 자리를 나눠 쓴다.
    //
    // 그것을 낱개로 그리면 39개가 정확히 포개져 **한 개로 보이고**, 탭하면 맨
    // 위 하나만 열려 나머지는 닿을 길이 없다. 겹친 것은 묶는다.
    features.addAll(_sameSpot(exact));
  } else {
    features.addAll(_grid(exact, zoom, cellPx));
  }
  // 근사 좌표는 줌과 무관하게 묶는다. 좌표가 같으니 칸 크기와 상관없이 한 덩어리다.
  features.addAll(_grid(approximate, zoom, cellPx));

  return features;
}

MapFeature _single(MapPin pin) => MapFeature(
  lat: pin.lat,
  lng: pin.lng,
  count: 1,
  propertyType: pin.datasetKey.split('/').first,
  approximate: pin.isApproximate,
  txId: pin.txId,
);

/// 좌표가 **완전히 같은** 것끼리만 묶는다. 격자와 달리 줌을 보지 않는다 —
/// 같은 점은 어떤 배율에서도 같은 점이다.
List<MapFeature> _sameSpot(List<MapPin> pins) {
  if (pins.isEmpty) return const [];

  final buckets = <String, List<MapPin>>{};
  for (final pin in pins) {
    buckets.putIfAbsent('${pin.lat},${pin.lng}', () => []).add(pin);
  }

  return [
    for (final group in buckets.values)
      if (group.length == 1) _single(group.first) else _merge(group),
  ];
}

List<MapFeature> _grid(List<MapPin> pins, double zoom, double cellPx) {
  if (pins.isEmpty) return const [];

  final worldSize = kTileSize * math.pow(2, zoom);
  final buckets = <int, List<MapPin>>{};

  for (final pin in pins) {
    final cx = (_mercatorX(pin.lng) * worldSize / cellPx).floor();
    final cy = (_mercatorY(pin.lat) * worldSize / cellPx).floor();
    // 한 정수로 접는다. 경도 방향 칸 수는 2^zoom * tileSize / cellPx라
    // 줌 16에서도 26만이므로 100만 배수면 충돌하지 않는다.
    buckets.putIfAbsent(cx * 1000000 + cy, () => []).add(pin);
  }

  return [
    for (final group in buckets.values)
      if (group.length == 1) _single(group.first) else _merge(group),
  ];
}

MapFeature _merge(List<MapPin> group) {
  var lat = 0.0;
  var lng = 0.0;
  var approximate = false;
  // 전부 한 자리인가. 그러면 확대해도 갈라지지 않으니 목록을 열어야 한다.
  var sameSpot = true;
  final first = group.first;
  final byType = <String, int>{};

  for (final pin in group) {
    lat += pin.lat;
    lng += pin.lng;
    if (pin.isApproximate) approximate = true;
    if (pin.lat != first.lat || pin.lng != first.lng) sameSpot = false;
    final type = pin.datasetKey.split('/').first;
    byType[type] = (byType[type] ?? 0) + 1;
  }

  var top = group.first.datasetKey.split('/').first;
  var best = 0;
  // 같은 수면 이름 순으로 고정한다. 실행마다 색이 바뀌면 사용자가 패턴으로 못 읽는다.
  for (final key in byType.keys.toList()..sort()) {
    final count = byType[key]!;
    if (count > best) {
      best = count;
      top = key;
    }
  }

  return MapFeature(
    // 한 자리에 모인 것이면 평균이 곧 그 자리다. 다만 부동소수 나눗셈이
    // 원래 값과 미세하게 어긋날 수 있어, 그때는 **원래 좌표를 그대로 쓴다** —
    // 이 좌표로 다시 조회해 목록을 열기 때문이다.
    lat: sameSpot ? first.lat : lat / group.length,
    lng: sameSpot ? first.lng : lng / group.length,
    count: group.length,
    propertyType: top,
    approximate: approximate,
    sameSpot: sameSpot,
  );
}

double _mercatorX(double lng) => (lng + 180) / 360;

double _mercatorY(double lat) {
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final radians = clamped * math.pi / 180;
  return (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
      2;
}
