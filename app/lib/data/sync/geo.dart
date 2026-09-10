/// 좌표와 상자 — 지역 색인과 경계 폴리곤이 함께 쓰는 최소한의 것.
///
/// 따로 둔 이유는 **서로를 부르지 않게** 하기 위해서다. 색인은 경계를 써서
/// 자리를 풀고, 경계는 좌표와 상자를 쓴다. 이 둘이 한 파일에 있으면 두 파일이
/// 서로를 import 하게 된다.
library;

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
