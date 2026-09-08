/// 상세창 위쪽의 지도 미니뷰 (D-4).
///
/// `Doc/상세정보명세.html`의 도면 블록 자리다. 도면 자체는 국토부 실거래가에
/// 없어서 건축HUB가 필요하고(D-1~D-3), 그것은 별도 활용신청이 선행이다.
/// **그 자리를 비워 두는 대신 "여기가 어디인가"를 보여준다** — 명세의 D-4가
/// 물어본 것이 그것이고, 지금 가진 데이터로 답할 수 있다.
///
/// **MapLibre를 하나 더 띄우지 않는다.** 지도 화면 하나가 그래픽 메모리
/// 139 MB를 쓴다(실측). 상세창을 열 때마다 두 번째 렌더러를 만들면 저사양
/// 기기에서 그대로 죽는다. 대신 타일 이미지를 직접 붙인다 — 정지 화면이라
/// 조작이 없고, 조작이 없으니 렌더러도 필요 없다.
library;

import 'dart:math' as math;

/// 타일 한 장의 픽셀 크기. 두 출처 모두 256이다.
const double kTilePx = 256;

/// 미니뷰의 확대 수준.
///
/// 16이면 한 블록이 화면을 채운다. 더 당기면 어느 건물인지는 알겠으나 주변을
/// 못 읽고, 더 빼면 "동네 어디쯤"이 되어 굳이 볼 이유가 없어진다.
const int kMiniMapZoom = 16;

/// 타일을 어디서 받는가.
///
/// 배경지도와 **같은 출처를 써야 한다.** 다른 곳에서 받으면 지도 화면과
/// 상세창의 그림이 달라지고, 사용자는 둘 중 어느 쪽이 맞는지 알 수 없다.
sealed class TileSource {
  const TileSource();

  const factory TileSource.osm() = OsmTiles;
}

final class OsmTiles extends TileSource {
  const OsmTiles();
}

/// 타일 하나를 가리키는 정수 좌표.
class TileXY {
  const TileXY({required this.z, required this.x, required this.y});
  final int z;
  final int x;
  final int y;
}

/// 타일 주소.
///
/// 출처마다 좌표 순서가 다르다. OSM은 `{z}/{x}/{y}`다. 순서를 바꾸면 지도가
/// 나오긴 하는데 엉뚱한 자리가 나오고, 축척이 작으면 사람이 못 알아본다.
/// 그래서 출처를 늘릴 때마다 테스트로 묶는다.
String tileUrl(TileSource source, TileXY t) => switch (source) {
  OsmTiles() => 'https://tile.openstreetmap.org/${t.z}/${t.x}/${t.y}.png',
};

/// 타일 단위의 실수 좌표. 정수부가 타일 번호, 소수부가 타일 안의 위치다.
class TilePoint {
  const TilePoint(this.x, this.y);
  final double x;
  final double y;
}

/// 위경도를 웹 메르카토르 타일 좌표로.
///
/// 화면 좌표는 위가 0이라 **위도가 커질수록 y가 작아진다.** 부호를 뒤집으면
/// 남북이 뒤집힌 지도가 나오는데, 축척이 작으면 사람이 못 알아본다.
TilePoint projectToTile({
  required double lat,
  required double lng,
  required int zoom,
}) {
  final n = math.pow(2, zoom).toDouble();
  // 극지방은 메르카토르에서 무한대로 발산한다. 실제 한계각으로 자른다.
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180;
  final x = (lng + 180) / 360 * n;
  final y = (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n;
  return TilePoint(x, y);
}

/// 상자 안에 놓일 타일 한 장.
class PlacedTile {
  const PlacedTile({required this.xy, required this.left, required this.top});
  final TileXY xy;
  final double left;
  final double top;
}

/// 미니뷰 한 판의 배치.
class MiniMapLayout {
  const MiniMapLayout({
    required this.tiles,
    required this.markerLeft,
    required this.markerTop,
  });

  final List<PlacedTile> tiles;

  /// 핀이 놓일 자리. 늘 상자 한가운데다 — 그 점을 중심으로 잘랐기 때문이다.
  final double markerLeft;
  final double markerTop;
}

/// [lat]·[lng]을 한가운데 두고 [size]×[size] 상자를 덮는 타일들을 고른다.
MiniMapLayout miniMapLayout({
  required double lat,
  required double lng,
  required double size,
  int zoom = kMiniMapZoom,
}) {
  final centre = projectToTile(lat: lat, lng: lng, zoom: zoom);
  final half = size / 2;

  // 상자 왼쪽 위 모서리가 타일 좌표로 어디인가.
  final originX = centre.x - half / kTilePx;
  final originY = centre.y - half / kTilePx;

  final firstX = originX.floor();
  final firstY = originY.floor();
  // 상자 오른쪽 아래까지 덮으려면 몇 장이 더 필요한가. ceil로 잡아야 마지막
  // 줄이 잘려 회색으로 남지 않는다.
  final lastX = (originX + size / kTilePx).ceil();
  final lastY = (originY + size / kTilePx).ceil();

  final max = 1 << zoom;
  final tiles = <PlacedTile>[];
  for (var ty = firstY; ty < lastY; ty += 1) {
    // 위아래 밖은 타일이 없다. 요청하면 404이므로 아예 안 만든다.
    if (ty < 0 || ty >= max) continue;
    for (var tx = firstX; tx < lastX; tx += 1) {
      // 좌우는 날짜변경선에서 감긴다. 지구가 둥근 쪽은 감아 주는 것이 맞다.
      final wrapped = ((tx % max) + max) % max;
      tiles.add(
        PlacedTile(
          xy: TileXY(z: zoom, x: wrapped, y: ty),
          left: (tx - originX) * kTilePx,
          top: (ty - originY) * kTilePx,
        ),
      );
    }
  }

  return MiniMapLayout(tiles: tiles, markerLeft: half, markerTop: half);
}
