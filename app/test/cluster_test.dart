import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/map/cluster.dart';

MapPin _pin(
  String id,
  double lat,
  double lng, {
  String precision = 'exact',
  String datasetKey = 'apartment/trade',
}) => MapPin(
  txId: id,
  lat: lat,
  lng: lng,
  precision: precision,
  datasetKey: datasetKey,
  amount: 100000,
  deposit: null,
  monthlyRent: null,
  cancelled: false,
);

void main() {
  test('빈 입력은 빈 결과', () {
    expect(clusterPins(const [], 13), isEmpty);
  });

  test('멀리 떨어진 점은 묶이지 않는다', () {
    final result = clusterPins([
      _pin('a', 37.50, 127.02),
      _pin('b', 37.60, 127.20),
    ], 13);

    expect(result, hasLength(2));
    expect(result.every((f) => f.count == 1), isTrue);
    expect(result.map((f) => f.txId), containsAll(['a', 'b']));
  });

  test('한 칸 안의 점은 하나로 묶인다', () {
    final result = clusterPins([
      _pin('a', 37.5000, 127.0200),
      _pin('b', 37.5001, 127.0201),
      _pin('c', 37.5002, 127.0202),
    ], 12);

    expect(result, hasLength(1));
    expect(result.single.count, 3);
    expect(result.single.isCluster, isTrue);
    // 묶음은 상세를 열 수 없다. txId가 남아 있으면 셋 중 하나만 열려 거짓말이 된다
    expect(result.single.txId, isNull);
  });

  test('줌이 올라가면 같은 점들이 풀린다', () {
    final pins = [_pin('a', 37.5000, 127.0200), _pin('b', 37.5010, 127.0210)];

    expect(clusterPins(pins, 11), hasLength(1));
    expect(clusterPins(pins, 17), hasLength(2));
  });

  test('최대 줌을 넘으면 정확 좌표는 전부 낱개다', () {
    final pins = [
      for (var i = 0; i < 5; i++) _pin('p$i', 37.5, 127.02 + i * 0.000001),
    ];

    final result = clusterPins(pins, kClusterMaxZoom);

    expect(result, hasLength(5));
    expect(result.every((f) => f.txId != null), isTrue);
  });

  test('근사 좌표는 최대 줌을 넘겨도 묶인다', () {
    // 법정동 중심점이라 좌표가 완전히 같다. 낱개로 그리면 한 점에 200개가 쌓여
    // 맨 위 하나만 눌린다 — 나머지 199건은 눌러도 열리지 않는다.
    final pins = [
      for (var i = 0; i < 200; i++)
        _pin('u$i', 37.4979, 127.0276, precision: 'umd'),
    ];

    final result = clusterPins(pins, 22);

    expect(result, hasLength(1));
    expect(result.single.count, 200);
    expect(result.single.approximate, isTrue);
  });

  test('근사와 정확은 같은 자리라도 섞이지 않는다', () {
    final result = clusterPins([
      _pin('exact', 37.4979, 127.0276),
      _pin('approx', 37.4979, 127.0276, precision: 'umd'),
    ], 12);

    expect(result, hasLength(2));
    expect(result.where((f) => f.approximate), hasLength(1));
    expect(result.where((f) => !f.approximate), hasLength(1));
  });

  test('묶음의 유형은 가장 많은 쪽을 따른다', () {
    final result = clusterPins([
      _pin('a', 37.5000, 127.0200, datasetKey: 'land/trade'),
      _pin('b', 37.5001, 127.0201, datasetKey: 'apartment/trade'),
      _pin('c', 37.5002, 127.0202, datasetKey: 'apartment/rent'),
    ], 12);

    expect(result.single.propertyType, 'apartment');
  });

  test('묶음 좌표는 구성원의 평균 안에 있다', () {
    final result = clusterPins([
      _pin('a', 37.5000, 127.0200),
      _pin('b', 37.5002, 127.0204),
    ], 12);

    expect(result.single.lat, closeTo(37.5001, 1e-9));
    expect(result.single.lng, closeTo(127.0202, 1e-9));
  });

  test('낱개는 좌표를 그대로 쓴다', () {
    final result = clusterPins([_pin('a', 37.5, 127.02)], 15);

    expect(result.single.lat, 37.5);
    expect(result.single.lng, 127.02);
    expect(result.single.txId, 'a');
    expect(result.single.isCluster, isFalse);
  });

  test('건수는 어떤 줌에서도 보존된다', () {
    final pins = [
      for (var i = 0; i < 300; i++)
        _pin(
          'p$i',
          37.45 + (i % 30) * 0.002,
          127.0 + (i ~/ 30) * 0.002,
          precision: i % 7 == 0 ? 'umd' : 'exact',
        ),
    ];

    for (final zoom in [8.0, 11.0, 13.5, 16.0, 18.0]) {
      final total = clusterPins(
        pins,
        zoom,
      ).fold<int>(0, (sum, f) => sum + f.count);
      expect(total, 300, reason: '줌 $zoom에서 건수가 새어 나갔다');
    }
  });

  test('격자는 위도에 따라 늘어나지 않는다', () {
    // 같은 화면 거리인데 위도만 다른 두 쌍. 메르카토르 픽셀 위에서 나누면
    // 둘 다 같은 판정을 받아야 한다 — 위경도 격자로 나누면 북쪽만 묶인다.
    double lngSpan(double lat) => 0.002 / math.cos(lat * math.pi / 180);

    final south = clusterPins([
      _pin('a', 33.0, 126.0),
      _pin('b', 33.0, 126.0 + lngSpan(33)),
    ], 12);
    final north = clusterPins([
      _pin('a', 38.5, 126.0),
      _pin('b', 38.5, 126.0 + lngSpan(38.5)),
    ], 12);

    expect(south.length, north.length);
  });
}
