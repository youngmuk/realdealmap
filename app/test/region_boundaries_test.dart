import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/sync/region_boundaries.dart';
import 'package:realdealmap/data/sync/region_index.dart';

/// 좌표를 시군구로 푸는 규칙 — 경계 폴리곤 판.
///
/// 여기가 틀리면 사용자는 **남의 동네 시세를 자기 동네로 읽는다.** 경계상자로
/// 풀던 시절 실기기에서 광진구에 서서 동대문구가 나왔고, 전국 표본으로 재 보니
/// 9.84%가 그랬다. 그래서 두 가지를 나눠 본다 — 해석이 맞는가, 그리고
/// **앱에 실제로 들어간 파일**이 진짜 자리를 맞히는가.

/// 남서쪽 모서리에서 [size]만큼 뻗은 정사각형 시군구 하나.
Map<String, dynamic> _square(
  String sggCd, {
  required double south,
  required double west,
  required double size,
  List<List<double>> holes = const [],
}) {
  final north = south + size;
  final east = west + size;
  return {
    'sggCd': sggCd,
    'bbox': {'south': south, 'north': north, 'west': west, 'east': east},
    'polygons': [
      [
        [west, south, east, south, east, north, west, north, west, south],
        ...holes,
      ],
    ],
  };
}

Uint8List _payload(
  List<Map<String, dynamic>> regions, {
  int schemaVersion = 1,
  double snapDegrees = 0.003,
  bool compress = false,
}) {
  final json = jsonEncode({
    'schemaVersion': schemaVersion,
    'attribution': '통계청 SGIS · vuski/admdongkor · CC BY 4.0',
    'toleranceDegrees': snapDegrees / 1.5,
    'snapDegrees': snapDegrees,
    'regions': regions,
  });
  final bytes = Uint8List.fromList(utf8.encode(json));
  return compress ? Uint8List.fromList(gzip.encode(bytes)) : bytes;
}

RegionSummary _region(
  String sggCd, {
  required BoundingBox bbox,
  required LatLng center,
}) => RegionSummary(
  sggCd: sggCd,
  name: sggCd,
  sidoName: '시도',
  sggName: sggCd,
  records: 1,
  located: 1,
  refreshedAt: '2026-09-10T00:00:00Z',
  bbox: bbox,
  center: center,
);

void main() {
  group('해석', () {
    test('gzip이든 아니든 같게 읽는다', () {
      final regions = [_square('11110', south: 37.0, west: 127.0, size: 0.1)];
      final plain = RegionBoundaries.decode(_payload(regions));
      final zipped = RegionBoundaries.decode(_payload(regions, compress: true));

      expect(plain?.shapes.length, 1);
      expect(zipped?.shapes.length, 1);
      expect(zipped?.snapDegrees, 0.003);
      expect(zipped?.attribution, contains('CC BY 4.0'));
    });

    // 앞으로 나온 판을 반쯤 읽으면 무엇이 옛 규칙으로 들어왔는지 알 수 없다.
    test('모르는 판은 통째로 버린다', () {
      final future = _payload([
        _square('11110', south: 37.0, west: 127.0, size: 0.1),
      ], schemaVersion: kSupportedBoundaryVersion + 1);
      expect(RegionBoundaries.decode(future), isNull);
    });

    test('내용이 아니면 null이다', () {
      expect(
        RegionBoundaries.decode(Uint8List.fromList(utf8.encode('{'))),
        isNull,
      );
      expect(
        RegionBoundaries.decode(Uint8List.fromList(utf8.encode('[]'))),
        isNull,
      );
      expect(RegionBoundaries.decode(_payload(const [])), isNull);
    });
  });

  group('담기는가', () {
    final bounds = RegionBoundaries.decode(
      _payload([
        _square('11110', south: 37.0, west: 127.0, size: 0.1),
        _square('11140', south: 37.0, west: 127.1, size: 0.1),
      ]),
    )!;

    test('안에 있으면 그 지역이다', () {
      expect(bounds.at(const LatLng(37.05, 127.05)), '11110');
      expect(bounds.at(const LatLng(37.05, 127.15)), '11140');
    });

    // 억지로 가까운 곳을 고르지 않는다. 바다 위나 아직 배포되지 않은 곳일 수
    // 있고, 엉뚱한 지역을 붙이면 사용자는 그 자리의 실거래라고 믿는다.
    test('멀리 밖이면 아무 데도 아니다', () {
      expect(bounds.at(const LatLng(35.0, 129.0)), isNull);
      expect(bounds.resolve(const LatLng(35.0, 129.0)), isNull);
    });

    // 성기게 만든 탓에 밖으로 밀린 점만 줍는다. 실측에서 511개가 밀렸고
    // 511개 전부 이 방법으로 제자리로 돌아왔다.
    test('경계 바로 밖은 줍고, 그보다 멀면 안 줍는다', () {
      // snapDegrees 0.003 — 0.002도(약 220m)는 줍고 0.01도(약 1.1km)는 못 줍는다.
      expect(bounds.at(const LatLng(37.05, 126.998)), isNull);
      expect(bounds.resolve(const LatLng(37.05, 126.998)), '11110');
      expect(bounds.resolve(const LatLng(37.05, 126.99)), isNull);
    });

    test('구멍 안은 그 지역이 아니다', () {
      final holed = RegionBoundaries.decode(
        _payload([
          _square(
            '11110',
            south: 37.0,
            west: 127.0,
            size: 0.1,
            holes: const [
              [
                127.04, 37.04, //
                127.06, 37.04,
                127.06, 37.06,
                127.04, 37.06,
                127.04, 37.04,
              ],
            ],
          ),
        ]),
      )!;

      expect(holed.at(const LatLng(37.02, 127.02)), '11110');
      expect(holed.at(const LatLng(37.05, 127.05)), isNull);
    });
  });

  group('색인과 함께', () {
    // 경계상자가 겹치는 두 지역. 상자만 보면 중심이 가까운 쪽이 이긴다.
    final index = RegionIndex([
      _region(
        '11215',
        bbox: const BoundingBox(
          south: 37.0,
          north: 37.2,
          west: 127.0,
          east: 127.2,
        ),
        center: const LatLng(37.10, 127.10),
      ),
      _region(
        '11230',
        bbox: const BoundingBox(
          south: 37.0,
          north: 37.2,
          west: 127.0,
          east: 127.2,
        ),
        center: const LatLng(37.06, 127.06),
      ),
    ]);
    // 진짜 경계는 서로 겹치지 않는다.
    final bounds = RegionBoundaries.decode(
      _payload([
        _square('11215', south: 37.0, west: 127.0, size: 0.1),
        _square('11230', south: 37.1, west: 127.1, size: 0.1),
      ]),
    )!;

    // 실기기에서 광진구에 서서 동대문구가 나온 것이 이 모양이었다.
    test('상자로는 틀리고 경계로는 맞는다', () {
      const point = LatLng(37.05, 127.05);
      expect(index.at(point, null)?.sggCd, '11230');
      expect(index.at(point, bounds)?.sggCd, '11215');
    });

    // 경계는 전국 256개를 다 알지만 색인은 배포된 지역만 안다.
    test('경계가 짚어도 색인에 없으면 담긴 지역이 없다', () {
      final onlyOne = RegionIndex([index.regions.first]);
      expect(onlyOne.at(const LatLng(37.15, 127.15), bounds), isNull);
    });

    // 담는 지역이 없을 때 가장 가까운 곳으로 가는 길은 그대로 남는다.
    test('담는 곳이 없으면 가장 가까운 곳으로 떨어진다', () {
      expect(
        index.nearest(const LatLng(37.30, 127.30), bounds)?.sggCd,
        '11215',
      );
    });
  });

  // 해석이 맞아도 **구워 넣은 파일**이 틀리면 소용이 없다. 실제 에셋을 읽는다.
  group('앱에 들어간 파일', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    Future<RegionBoundaries> load() async {
      final data = await rootBundle.load(kBoundariesAsset);
      return RegionBoundaries.decode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      )!;
    }

    test('전국 시군구를 담고 있다', () async {
      final bounds = await load();

      expect(bounds.shapes.length, 256);
      // CC BY 4.0의 조건이다. 빠지면 재배포가 라이선스 위반이 된다.
      expect(bounds.attribution, contains('CC BY 4.0'));
      expect(bounds.attribution, contains('SGIS'));
    });

    test('아는 자리를 맞힌다', () async {
      final bounds = await load();

      // 실기기에서 틀렸던 바로 그 자리부터 본다.
      expect(bounds.at(const LatLng(37.5540, 127.0790)), '11215'); // 광진구 군자동
      expect(bounds.at(const LatLng(37.5006, 127.0364)), '11680'); // 강남구 역삼동
      expect(bounds.at(const LatLng(35.1631, 129.1636)), '26350'); // 해운대구
      expect(bounds.at(const LatLng(33.4996, 126.5312)), '50110'); // 제주시
      // 동해 한가운데. 여기서 지역이 나오면 판정이 아니라 어림짐작이다.
      expect(bounds.resolve(const LatLng(36.0, 131.0)), isNull);
    });
  });
}
