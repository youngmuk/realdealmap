import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/sync/building_shapes.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// 상세창의 건물 그림 — "이 거래가 어느 건물인가".
///
/// **도면이 아니라 외곽선이다.** 평면도는 국토부 실거래가에도 도로명주소 자료에도
/// 없다(건축HUB가 따로 필요하고 별도 활용신청이 선행이다). 여기서 그리는 것은
/// 건물이 땅 위에 차지한 자리다. 그것만으로도 맞닿은 집들 사이에서
/// **어느 건물의 거래인지**는 가려진다 — 지도의 핀 하나로는 못 하던 일이다.
///
/// **지도를 띄우지 않는다.** 렌더러를 하나 더 올리면 그래픽 메모리가 두 배가 된다
/// (지도 하나가 139MB · 실측). 폴리곤 몇 개를 캔버스에 직접 그리면 타일도
/// 렌더러도 필요 없다. 상세창에 지도를 넣지 않기로 한 결정은 그대로 지켜진다.
///
/// **없으면 자리 자체가 없다.** 지번이 가려진 거래, 아직 안 올린 지역, 끊긴 회선이
/// 모두 같은 결과다 — 빈 상자를 남기면 "불러오지 못했다"로 읽히고, 사용자는
/// 자기 탓이거나 앱이 고장 난 것으로 받아들인다.
class BuildingOutlineBlock extends ConsumerStatefulWidget {
  const BuildingOutlineBlock({required this.tx, super.key});

  final TxRow tx;

  @override
  ConsumerState<BuildingOutlineBlock> createState() =>
      _BuildingOutlineBlockState();
}

class _BuildingOutlineBlockState extends ConsumerState<BuildingOutlineBlock> {
  /// `null`이면 물어볼 것도 없는 거래다(지번이 가려졌다).
  Future<BuildingOutlines?>? _outlines;

  @override
  void initState() {
    super.initState();
    final tx = widget.tx;
    if (!BuildingShapeStore.canLocate(tx.jibun)) return;
    // build에서 시작하면 다시 그릴 때마다 요청이 나간다.
    _outlines = ref
        .read(buildingShapeStoreProvider)
        .outlines(sggCd: tx.sggCd, umdNm: tx.umdNm, jibun: tx.jibun);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _outlines;
    if (pending == null) return const SizedBox.shrink();

    return FutureBuilder<BuildingOutlines?>(
      future: pending,
      builder: (context, snapshot) {
        final outlines = snapshot.data;
        // 기다리는 동안에도 빈자리를 만들지 않는다. 자리가 생겼다 없어지면
        // 읽던 줄이 밀린다.
        if (outlines == null || outlines.isEmpty) {
          return const SizedBox.shrink();
        }
        return _Figure(outlines: outlines);
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.outlines});

  final BuildingOutlines outlines;

  @override
  Widget build(BuildContext context) {
    final many = outlines.target.length > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: '건물 외곽선 그림',
            child: Container(
              height: 168,
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Palette.rule),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                size: Size.infinite,
                painter: BuildingOutlinePainter(
                  outlines: outlines,
                  window: outlineWindow(outlines.target),
                ),
              ),
            ),
          ),
          // 단지는 동이 여럿인데 거래 자료에는 동 번호가 없다. 하나만 칠하면
          // 사용자는 **그 동의 거래**라고 읽는다 — 우리가 모르는 것을 아는 척하게 된다.
          if (many)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '이 지번의 건물 ${outlines.target.length}동입니다. '
                '거래 자료에 동 번호가 없어 어느 동인지는 알 수 없습니다.',
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Palette.ink3,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _caption(outlines),
              style: const TextStyle(fontSize: 11, color: Palette.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 출처와 자료 시점. 공공누리 제1유형의 조건이라 빠지면 재배포가 위반이 된다.
String _caption(BuildingOutlines outlines) {
  final attribution = outlines.attribution.isNotEmpty
      ? outlines.attribution
      : '행정안전부 도로명주소 건물 도형 · 공공누리 제1유형';
  final when = _sourceLabel(outlines.source);
  return when.isEmpty ? attribution : '$attribution · $when 기준';
}

/// `20260901` → `2026년 9월`. 모양이 다르면 그대로 둔다.
String _sourceLabel(String source) {
  if (source.length < 6 || int.tryParse(source.substring(0, 6)) == null) {
    return '';
  }
  final year = source.substring(0, 4);
  final month = int.parse(source.substring(4, 6));
  if (month < 1 || month > 12) return '';
  return '$year년 $month월';
}

/// 외곽선을 그린다.
///
/// 위경도를 그대로 쓰면 위도 37도에서 가로가 실제보다 **25% 넓게** 보인다.
/// 경도 1도가 위도 1도보다 짧기 때문이다 — 건물이 옆으로 퍼진 모양이 되므로
/// 가로에 `cos(위도)`를 곱해 편다.
class BuildingOutlinePainter extends CustomPainter {
  BuildingOutlinePainter({required this.outlines, required this.window});

  final BuildingOutlines outlines;
  final BoundingBox window;

  @override
  void paint(Canvas canvas, Size size) {
    final midLat = (window.south + window.north) / 2;
    final kx = math.cos(midLat * math.pi / 180);
    final spanX = (window.east - window.west) * kx;
    final spanY = window.north - window.south;
    if (spanX <= 0 || spanY <= 0 || size.isEmpty) return;

    final scale = math.min(size.width / spanX, size.height / spanY);
    final left = (size.width - spanX * scale) / 2;
    final top = (size.height - spanY * scale) / 2;

    Path pathOf(Outline ring) {
      final path = Path();
      for (var i = 0; i < ring.length; i += 2) {
        final x = left + (ring[i] - window.west) * kx * scale;
        final y = top + (window.north - ring[i + 1]) * scale;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      return path;
    }

    // 이웃부터 그린다. 옅게 깔려 있어야 이 건물이 어디쯤인지 읽힌다.
    final neighbourFill = Paint()..color = const Color(0xFFEFEAE1);
    final neighbourLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Palette.rule;
    for (final ring in outlines.neighbours) {
      final path = pathOf(ring);
      canvas
        ..drawPath(path, neighbourFill)
        ..drawPath(path, neighbourLine);
    }

    final targetFill = Paint()..color = Palette.accentSoft;
    final targetLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.accent;
    for (final ring in outlines.target) {
      final path = pathOf(ring);
      canvas
        ..drawPath(path, targetFill)
        ..drawPath(path, targetLine);
    }
  }

  @override
  bool shouldRepaint(BuildingOutlinePainter old) =>
      !identical(old.outlines, outlines) ||
      old.window.south != window.south ||
      old.window.north != window.north ||
      old.window.west != window.west ||
      old.window.east != window.east;
}
