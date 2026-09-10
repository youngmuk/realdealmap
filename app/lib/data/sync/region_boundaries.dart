/// 시군구 경계 폴리곤 — "이 좌표가 어느 시군구인가"의 근거.
///
/// **전에는 경계상자로 풀었다.** 그 시군구에서 거래가 일어난 범위를 사각형으로
/// 감싸고, 좌표가 그 사각형에 들면 그 지역으로 쳤다. 이웃끼리 사각형이 겹쳐서
/// 여럿이 걸리면 중심이 가까운 쪽을 골랐다. 전국 표본 24,836개(정확좌표)로
/// 재 보니 **9.84%가 틀렸다** — 강남구가 송파구로, 부산진구가 연제구로,
/// 경주시가 울주군으로 갔다. 실기기에서 광진구에 서서 동대문구를 받은 것도
/// 이것과 같은 뿌리다.
///
/// 여기서는 진짜 경계선 안쪽인지 따진다. 같은 표본에서 **99.91%**가 맞는다.
///
/// **왜 받아 오지 않고 앱에 넣나.** 첫 실행에서 "지금 있는 곳"을 여는 일이
/// 네트워크보다 먼저 일어나야 하고, 행정 경계는 개편이 있을 때나 바뀐다.
/// 400KB를 얹는 대신 받기·캐시·무효화가 통째로 없어진다.
///
/// 원자료는 통계청 SGIS 행정동 경계(공공누리 제1유형)를 vuski/admdongkor이
/// 가공해 CC BY 4.0으로 배포하는 것이다. **출처 표기가 조건이라** 파일 안에
/// 문구를 싣고([attribution]) 설정 화면이 그것을 보여준다.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'geo.dart';

/// 앱에 넣은 경계 파일. `packages/ingest/scripts/build-region-boundaries.mjs`가 굽는다.
const String kBoundariesAsset = 'assets/regions/boundaries.json.gz';

/// 읽을 수 있는 판. 앞으로 나온 판은 무엇이 옛 규칙으로 들어왔는지 알 수 없어 버린다.
const int kSupportedBoundaryVersion = 1;

/// 시군구 하나의 생김새.
///
/// 링은 `[경도, 위도, 경도, 위도, ...]`로 평평하다. `List<LatLng>`으로 담으면
/// 점 75,123개마다 객체가 하나씩 생긴다 — [Float64List]는 그 자리에 숫자만 둔다.
final class RegionShape {
  const RegionShape(this.sggCd, this.bbox, this.polygons);

  final String sggCd;

  /// 링을 훑기 전에 먼저 거르는 상자. 없으면 256개 시군구를 전부 훑는다.
  final BoundingBox bbox;

  /// 조각들. 각 조각의 첫 링이 바깥이고 나머지는 구멍이다.
  final List<List<Float64List>> polygons;
}

class RegionBoundaries {
  const RegionBoundaries(this.shapes, this.attribution, this.snapDegrees);

  final List<RegionShape> shapes;

  /// 출처 표기. CC BY 4.0의 조건이라 화면 어딘가에 반드시 남아야 한다.
  final String attribution;

  /// 폴리곤 밖으로 밀려난 점을 몇 도까지 주울 것인가. 굽는 쪽이 정해서 싣는다.
  final double snapDegrees;

  bool get isEmpty => shapes.isEmpty;

  /// 이 자리를 담는 시군구 코드. 어디에도 안 들면 `null`.
  ///
  /// **가장 가까운 것을 억지로 고르지 않는다.** 바다 위나 아직 배포되지 않은
  /// 곳일 수 있는데, 엉뚱한 지역을 붙이면 사용자는 그 자리의 실거래라고 믿는다.
  String? at(LatLng point) {
    for (final shape in shapes) {
      if (!shape.bbox.contains(point)) continue;
      if (_inShape(shape, point)) return shape.sggCd;
    }
    return null;
  }

  /// 담는 시군구, 없으면 **우리가 만든 오차만큼만** 물러나 가장 가까운 시군구.
  ///
  /// 경계선을 성기게 만들었기 때문에 선이 최대 [snapDegrees]/1.5만큼 안쪽으로
  /// 들어와 있을 수 있고, 그 띠에 서 있던 사람은 자기 시군구 밖으로 떨어진다.
  /// 표본에서 511개가 그렇게 밀렸고 **511개 전부** 이 방법으로 제자리에 돌아왔다.
  ///
  /// 무르는 거리를 [snapDegrees]로 묶어 둔 것이 요점이다. 넓게 잡으면 진짜로
  /// 바깥에 있는 사람에게까지 지역을 붙이게 되어 [at]의 약속이 깨진다.
  String? resolve(LatLng point) => at(point) ?? _nearestEdge(point);

  String? _nearestEdge(LatLng point) {
    // 경도 1도는 위도에 따라 짧아진다. 그대로 재면 동서 거리를 부풀려
    // 엉뚱한 쪽이 "가깝다"고 나온다.
    final kx = math.cos(point.lat * math.pi / 180);
    final px = point.lng * kx;
    final py = point.lat;

    String? best;
    var bestDistance = snapDegrees * snapDegrees;

    for (final shape in shapes) {
      final box = shape.bbox;
      // 상자에서 이미 먼 곳은 링을 훑지 않는다. 이것이 없으면 점 하나에
      // 75,123개 선분을 전부 재게 된다.
      final dx =
          math.max(math.max(box.west - point.lng, 0.0), point.lng - box.east) *
          kx;
      final dy = math.max(
        math.max(box.south - point.lat, 0.0),
        point.lat - box.north,
      );
      if (dx * dx + dy * dy >= bestDistance) continue;

      for (final rings in shape.polygons) {
        final ring = rings.first;
        for (var i = 2; i < ring.length; i += 2) {
          final d = _sqSegment(
            px,
            py,
            ring[i - 2] * kx,
            ring[i - 1],
            ring[i] * kx,
            ring[i + 1],
          );
          if (d < bestDistance) {
            bestDistance = d;
            best = shape.sggCd;
          }
        }
      }
    }
    return best;
  }

  /// 앱에 넣어 둔 파일을 읽는다. 못 읽으면 `null` — 부르는 쪽이 옛 방식으로 돈다.
  ///
  /// **푸는 일은 다른 아이소레이트에서 한다.** 1.4MB를 [jsonDecode] 하는 데
  /// 100ms 남짓 걸리는데, 이것을 본 아이소레이트에서 하면 그동안 지도가 멈춘다.
  /// 이 일이 일어나는 때가 하필 앱을 켠 직후라 사용자 눈에 그대로 보인다.
  ///
  /// 에셋을 읽는 것 자체는 플랫폼 채널이라 본 아이소레이트에서만 된다.
  /// 그래서 바이트만 여기서 얻고 넘긴다 — [Uint8List]는 그대로 건너간다.
  static Future<RegionBoundaries?> loadAsset({AssetBundle? bundle}) async {
    final ByteData data;
    try {
      data = await (bundle ?? rootBundle).load(kBoundariesAsset);
    } on FlutterError {
      // 에셋이 빠진 채로 빌드된 경우다. 위치 기능을 통째로 잃는 것보다
      // 경계상자로 도는 편이 낫다.
      return null;
    }
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return Isolate.run(() => decode(bytes));
  }

  /// gzip이면 풀고 해석한다. 형식이 어긋나면 `null`.
  static RegionBoundaries? decode(Uint8List bytes) {
    final Uint8List raw;
    try {
      raw = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
          ? Uint8List.fromList(gzip.decode(bytes))
          : bytes;
    } on FormatException {
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(raw));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final version = decoded['schemaVersion'];
    if (version is! int || version > kSupportedBoundaryVersion) return null;

    final snap = decoded['snapDegrees'];
    final rows = decoded['regions'];
    if (snap is! num || rows is! List) return null;

    final shapes = <RegionShape>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final sggCd = row['sggCd'];
      final bbox = BoundingBox.tryFrom(row['bbox'] as Map<String, dynamic>?);
      final polygons = row['polygons'];
      if (sggCd is! String ||
          sggCd.length != 5 ||
          bbox == null ||
          polygons is! List) {
        continue;
      }

      final parsed = <List<Float64List>>[];
      for (final rings in polygons.whereType<List>()) {
        final one = <Float64List>[];
        for (final ring in rings.whereType<List>()) {
          // 짝이 안 맞거나 삼각형도 못 되는 링은 면적이 없다.
          if (ring.length < 8 || ring.length.isOdd) continue;
          final flat = Float64List(ring.length);
          for (var i = 0; i < ring.length; i++) {
            final v = ring[i];
            if (v is! num) return null;
            flat[i] = v.toDouble();
          }
          one.add(flat);
        }
        if (one.isNotEmpty) parsed.add(one);
      }
      if (parsed.isNotEmpty) shapes.add(RegionShape(sggCd, bbox, parsed));
    }
    if (shapes.isEmpty) return null;

    return RegionBoundaries(
      shapes,
      decoded['attribution'] as String? ?? '',
      snap.toDouble(),
    );
  }
}

bool _inShape(RegionShape shape, LatLng point) {
  for (final rings in shape.polygons) {
    if (!_inRing(rings.first, point)) continue;
    var inHole = false;
    for (var k = 1; k < rings.length; k++) {
      if (_inRing(rings[k], point)) {
        inHole = true;
        break;
      }
    }
    if (!inHole) return true;
  }
  return false;
}

/// 광선 교차. 점에서 동쪽으로 반직선을 쏘아 링과 몇 번 만나는지 센다 —
/// 홀수면 안이다.
bool _inRing(Float64List ring, LatLng point) {
  final lat = point.lat;
  final lng = point.lng;
  var inside = false;
  final n = ring.length;
  for (var i = 0, j = n - 2; i < n; j = i, i += 2) {
    final yi = ring[i + 1];
    final yj = ring[j + 1];
    if ((yi > lat) != (yj > lat)) {
      final xi = ring[i];
      final xj = ring[j];
      if (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}

/// 점에서 선분까지 거리의 제곱.
double _sqSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  var x = ax;
  var y = ay;
  var dx = bx - ax;
  var dy = by - ay;
  if (dx != 0 || dy != 0) {
    final t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy);
    if (t > 1) {
      x = bx;
      y = by;
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }
  dx = px - x;
  dy = py - y;
  return dx * dx + dy * dy;
}
