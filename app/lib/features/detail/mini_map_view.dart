/// 지도 미니뷰 위젯 (D-4).
///
/// 타일 계산은 [mini_map.dart]에 있고 여기는 그리기만 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import 'mini_map.dart';

/// 미니뷰 높이. 상세창 위쪽을 다 먹지 않으면서 "어디쯤"이 읽히는 크기다.
const double kMiniMapHeight = 168;

class MiniMapView extends ConsumerWidget {
  const MiniMapView({
    required this.lat,
    required this.lng,
    required this.approximate,
    super.key,
  });

  final double lat;
  final double lng;

  /// 지번을 몰라 법정동 중심으로 찍은 좌표인가.
  ///
  /// 이때 뾰족한 핀을 찍으면 **그 건물이라고 말하는 것이 된다.** 실제로는
  /// 수백 미터가 빗나갈 수 있다(실측 226~582 m). 원으로 그려서 "이 근처"임을
  /// 모양으로 말하고, 글로도 한 번 더 말한다.
  final bool approximate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 배경지도와 같은 출처를 써야 한다. 지금은 OSM 폴백 하나뿐이다 —
    // 출시용 배경지도(PMTiles)를 얹으면 여기도 그쪽을 가리킨다.
    const source = TileSource.osm();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: kMiniMapHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 상자가 정사각형이 아니므로 긴 변을 기준으로 덮는다. 짧은 변은
              // ClipRRect가 잘라 낸다 — 모자라서 회색이 남는 것보다 낫다.
              final side = constraints.maxWidth > constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              final layout = miniMapLayout(lat: lat, lng: lng, size: side);
              final dx = (constraints.maxWidth - side) / 2;
              final dy = (constraints.maxHeight - side) / 2;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // 타일이 아직 안 왔을 때 검은 상자가 보이지 않게 깔아 둔다.
                  const ColoredBox(color: Palette.rule),
                  for (final tile in layout.tiles)
                    Positioned(
                      left: tile.left + dx,
                      top: tile.top + dy,
                      width: kTilePx,
                      height: kTilePx,
                      child: Image.network(
                        tileUrl(source, tile.xy),
                        fit: BoxFit.fill,
                        // 한 장이 실패해도 미니뷰 전체를 버리지 않는다.
                        // 나머지 타일만으로도 "어디쯤"은 읽힌다.
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  Positioned(
                    left: layout.markerLeft + dx - _markerSize / 2,
                    top:
                        layout.markerTop +
                        dy -
                        (approximate ? _markerSize / 2 : _markerSize),
                    width: _markerSize,
                    height: _markerSize,
                    child: _Marker(approximate: approximate),
                  ),
                  if (approximate)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ApproximateNote(),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

const double _markerSize = 28;

class _Marker extends StatelessWidget {
  const _Marker({required this.approximate});
  final bool approximate;

  @override
  Widget build(BuildContext context) => approximate
      // 원은 "이 안 어딘가"를 뜻한다. 가운데를 가리키지 않는다.
      ? Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Palette.accent.withValues(alpha: 0.22),
            border: Border.all(color: Palette.accent, width: 2),
          ),
        )
      : const Icon(
          Icons.location_on,
          size: _markerSize,
          color: Palette.accent,
          shadows: [Shadow(color: Colors.white, blurRadius: 4)],
        );
}

class _ApproximateNote extends StatelessWidget {
  const _ApproximateNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    color: Colors.black.withValues(alpha: 0.55),
    child: const Text(
      '지번이 공개되지 않아 법정동 근사 위치입니다',
      style: TextStyle(color: Colors.white, fontSize: 11.5),
    ),
  );
}
