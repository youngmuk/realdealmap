import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/features/detail/mini_map.dart';

/// 상세창 위쪽의 지도 미니뷰 (D-4).
///
/// 여기서 지키려는 것은 **핀이 맞는 자리에 찍히는가**다. 타일 좌표를 한 자리
/// 틀리면 지도는 멀쩡히 나오고 핀도 찍히는데 위치만 틀린다. 그런 오류는
/// "안 나온다"보다 알아채기 어렵고, 실거래가에서는 값비싼 거짓말이 된다.
void main() {
  group('타일 주소', () {
    // 출처마다 좌표 순서가 다르다. 순서를 바꾸면 엉뚱한 타일이 조용히 붙어
    // 지도가 나오긴 하는데 위치가 틀린다. 출처를 늘릴 때마다 여기에 묶는다.
    test('OSM은 z/x/y 순서다', () {
      final url = tileUrl(
        const TileSource.osm(),
        const TileXY(z: 16, x: 55899, y: 25377),
      );
      expect(url, endsWith('/16/55899/25377.png'));
    });
  });

  group('웹 메르카토르', () {
    // 손으로 계산한 기준값. 부호나 식이 틀어지면 여기서 걸린다.
    test('알려진 좌표가 알려진 타일로 간다', () {
      final p = projectToTile(lat: 37.5721, lng: 127.0642, zoom: 16);
      expect(p.x, closeTo(55899.331698, 0.001));
      expect(p.y, closeTo(25377.679650, 0.001));
    });

    test('경도가 커지면 x가 커진다', () {
      final a = projectToTile(lat: 37.5, lng: 126.0, zoom: 14);
      final b = projectToTile(lat: 37.5, lng: 128.0, zoom: 14);
      expect(b.x, greaterThan(a.x));
    });

    // 화면 좌표는 위가 0이다. 북쪽이 위라면 위도가 커질수록 y는 작아져야 한다.
    test('위도가 커지면 y가 작아진다', () {
      final a = projectToTile(lat: 36.0, lng: 127.0, zoom: 14);
      final b = projectToTile(lat: 38.0, lng: 127.0, zoom: 14);
      expect(b.y, lessThan(a.y));
    });
  });

  group('배치', () {
    const size = 240.0;

    MiniMapLayout layout({double lat = 37.5721, double lng = 127.0642}) =>
        miniMapLayout(lat: lat, lng: lng, zoom: 16, size: size);

    test('핀은 상자 한가운데다', () {
      final l = layout();
      expect(l.markerLeft, closeTo(size / 2, 0.01));
      expect(l.markerTop, closeTo(size / 2, 0.01));
    });

    // 한 장이라도 비면 그 자리가 회색으로 남는다. 상자를 남김없이 덮어야 한다.
    test('타일이 상자를 남김없이 덮는다', () {
      final l = layout();
      expect(l.tiles, isNotEmpty);

      final left = l.tiles.map((t) => t.left).reduce((a, b) => a < b ? a : b);
      final top = l.tiles.map((t) => t.top).reduce((a, b) => a < b ? a : b);
      final right = l.tiles
          .map((t) => t.left + kTilePx)
          .reduce((a, b) => a > b ? a : b);
      final bottom = l.tiles
          .map((t) => t.top + kTilePx)
          .reduce((a, b) => a > b ? a : b);

      expect(left, lessThanOrEqualTo(0));
      expect(top, lessThanOrEqualTo(0));
      expect(right, greaterThanOrEqualTo(size));
      expect(bottom, greaterThanOrEqualTo(size));
    });

    test('타일 좌표가 겹치지 않는다', () {
      final l = layout();
      final keys = l.tiles.map((t) => '${t.xy.x}/${t.xy.y}').toSet();
      expect(keys.length, l.tiles.length);
    });

    // 세계 경계에서 타일 번호가 음수나 범위 밖으로 나가면 404가 뜬다.
    test('경계에서도 타일 번호가 범위 안이다', () {
      for (final (lat, lng) in [
        (37.5, 179.99),
        (37.5, -179.99),
        (85.0, 0.0),
        (-85.0, 0.0),
      ]) {
        final l = miniMapLayout(lat: lat, lng: lng, zoom: 16, size: size);
        final max = 1 << 16;
        for (final t in l.tiles) {
          expect(t.xy.x, inInclusiveRange(0, max - 1));
          expect(t.xy.y, inInclusiveRange(0, max - 1));
        }
      }
    });
  });
}
