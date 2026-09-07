/// 묶음 마커를 이미지로 그린다.
///
/// **글자 레이어를 쓰지 않는다.** 심볼 레이어의 `textField`는 글리프(PBF 폰트)를
/// 요구하는데 래스터 스타일에는 `glyphs` 항목이 없다. 글리프 요청이 빈 URL로 나가
/// 실패하면 **그 소스에 붙은 레이어가 전부 사라진다** — 오류 하나 없이 지도만
/// 비어 보였고, 이 결함을 찾는 데 하루가 들었다.
///
/// 아이콘 이미지는 글리프를 타지 않는다. 원과 숫자를 여기서 직접 그려 넣으면
/// 네트워크도, 폰트 서버도, 오프라인 걱정도 없다.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// 기기 픽셀에 맞춰 크게 그린 뒤 줄여 쓴다. 1배로 그리면 숫자가 뭉갠 것처럼 보인다.
const double _scale = 3;

const _clusterFill = Color(0xFF16130F);
const _approxFill = Color(0xFFA16207);

/// 묶음 개수에 따른 반지름(논리 픽셀). 크기가 곧 밀도라 한눈에 읽힌다.
double clusterRadius(int count) {
  if (count >= 120) return 21;
  if (count >= 40) return 16;
  if (count >= 10) return 12;
  return 9;
}

/// 이 묶음을 그릴 아이콘 이름. 같은 이름이면 이미 올린 이미지를 그대로 쓴다.
String clusterIconName(int count, bool approximate) =>
    'rdm-c-$count-${approximate ? 'a' : 'e'}';

/// 필요한 아이콘을 스타일에 올린다. 이미 올린 것은 건너뛴다.
///
/// [added]는 호출자가 들고 있는 캐시다. 화면을 옮길 때마다 같은 숫자가 다시
/// 나오므로, 이걸 안 들고 있으면 매번 수십 장을 다시 그린다.
Future<void> ensureClusterIcons(
  ml.MapLibreMapController controller,
  Iterable<({int count, bool approximate})> needed,
  Set<String> added,
) async {
  for (final item in needed) {
    final name = clusterIconName(item.count, item.approximate);
    if (!added.add(name)) continue;
    await controller.addImage(
      name,
      await _drawBadge(item.count, item.approximate),
    );
  }
}

Future<Uint8List> _drawBadge(int count, bool approximate) async {
  final radius = clusterRadius(count);
  const stroke = 1.5;
  final size = (radius + stroke) * 2 * _scale;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final center = ui.Offset(size / 2, size / 2);

  canvas.drawCircle(
    center,
    radius * _scale,
    ui.Paint()
      // 근사 좌표 묶음은 옅게. 위치를 믿으면 안 된다는 뜻을 색으로 말한다
      ..color = approximate
          ? _approxFill.withValues(alpha: 0.28)
          : _clusterFill.withValues(alpha: 0.82),
  );
  canvas.drawCircle(
    center,
    radius * _scale,
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = stroke * _scale
      ..color = approximate
          ? _approxFill.withValues(alpha: 0.9)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.85),
  );

  // 네 자리가 넘으면 원 밖으로 삐져나간다. 정확한 숫자보다 읽히는 것이 낫다
  final label = count > 999 ? '999+' : '$count';
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        // 자릿수가 늘면 글자를 줄여 원 안에 담는다
        fontSize: (radius * _scale) * (label.length >= 3 ? 0.62 : 0.85),
        fontWeight: FontWeight.w700,
        color: approximate ? const Color(0xFF6B3D05) : const Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    center - ui.Offset(painter.width / 2, painter.height / 2),
  );

  final image = await recorder.endRecording().toImage(size.ceil(), size.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
