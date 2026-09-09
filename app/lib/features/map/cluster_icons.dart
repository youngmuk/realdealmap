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
String clusterLabel(int count) {
  if (count < 100) return '$count';
  if (count >= 1000) return '999+';
  return '${count ~/ 10 * 10}+';
}

/// 이 묶음을 그릴 아이콘 이름. 같은 이름이면 이미 올린 이미지를 그대로 쓴다
String clusterIconName(int count, bool approximate, bool sameSpot) =>
    'rdm-c-${clusterLabel(count)}-${approximate ? 'a' : 'e'}'
    '${sameSpot ? '-s' : ''}';

/// 필요한 아이콘을 스타일에 올린다. 이미 올린 것은 건너뛴다.
///
/// [added]는 호출자가 들고 있는 캐시다. 화면을 옮길 때마다 같은 숫자가 다시
/// 나오므로, 이걸 안 들고 있으면 매번 수십 장을 다시 그린다.
Future<void> ensureClusterIcons(
  ml.MapLibreMapController controller,
  Iterable<({int count, bool approximate, bool sameSpot})> needed,
  Set<String> added,
) async {
  // 한 줄씩 기다리지 않는다. 줌을 크게 바꾸면 새 숫자가 수십 개씩 한꺼번에
  // 나오는데, 순차로 기다리면 그만큼 지도 갱신이 늦어진다.
  final work = <Future<void>>[];
  for (final item in needed) {
    final name = clusterIconName(item.count, item.approximate, item.sameSpot);
    if (!added.add(name)) continue;
    work.add(
      _drawBadge(
        item.count,
        item.approximate,
        item.sameSpot,
      ).then((bytes) => controller.addImage(name, bytes)),
    );
  }
  await Future.wait(work);
}

Future<Uint8List> _drawBadge(int count, bool approximate, bool sameSpot) async {
  final radius = clusterRadius(count);
  const stroke = 1.5;
  // 겹친 카드가 뒤로 삐져나오는 만큼을 여유로 둔다. 안 두면 잘린다.
  final pad = (radius + stroke) * _scale * (sameSpot ? 1.32 : 1.0);
  final size = pad * 2;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final center = ui.Offset(size / 2, size / 2);

  final fill = ui.Paint()
    // 근사 좌표 묶음은 옅게. 위치를 믿으면 안 된다는 뜻을 색으로 말한다
    ..color = approximate
        ? _approxFill.withValues(alpha: 0.28)
        : _clusterFill.withValues(alpha: 0.82);
  final edge = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = stroke * _scale
    ..color = approximate
        ? _approxFill.withValues(alpha: 0.9)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.85);

  if (sameSpot) {
    // **모양으로 갈라 놓는다.**
    //
    // 원과 이 모양은 눌렀을 때 하는 일이 다르다 — 원은 확대해서 갈라지고,
    // 이것은 갈라지지 않아 목록이 열린다. 둘이 똑같이 생겼을 때 사용자는
    // 숫자만큼의 점이 나오기를 기대하고 확대했다가 점 하나를 보게 된다.
    // 실제로 그 혼동이 신고로 들어왔다.
    //
    // 겹친 카드로 그린다. "여러 장이 포개져 있다"는 뜻이 설명 없이 읽힌다.
    final r = radius * _scale;
    final radius0 = ui.Radius.circular(r * 0.42);
    for (final offset in [r * 0.30, 0.0]) {
      final rect = ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: center + ui.Offset(offset, -offset),
          width: r * 1.9,
          height: r * 1.9,
        ),
        radius0,
      );
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, edge);
    }
  } else {
    canvas.drawCircle(center, radius * _scale, fill);
    canvas.drawCircle(center, radius * _scale, edge);
  }

  final label = clusterLabel(count);
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
