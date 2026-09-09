import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/map/cluster.dart';
import 'package:realdealmap/features/map/cluster_icons.dart';

MapPin _pin(
  String id,
  double lat,
  double lng, {
  String precision = 'exact',
  String datasetKey = 'apartment/trade',
  String? name,
  String? jibun,
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
  name: name,
  jibun: jibun,
);

void main() {
  _labels();

  _stackKinds();

  _iconNames();

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

  // 좌표 사전은 `법정동|지번 → 한 점`이라 한 아파트 단지의 거래는 좌표가 하나다.
  // 실제 데이터로 재 보니 정확좌표 거래의 94%가 누군가와 자리를 나눠 쓰고,
  // 한 점에 132건이 겹친 곳도 있었다.
  //
  // 이것을 낱개로 그리면 화면에는 **한 개로 보이고** 탭하면 맨 위 하나만 열려
  // 나머지는 닿을 길이 없다. 실기기에서 39짜리 묶음을 확대했더니 점이 하나만
  // 보인다는 신고가 들어왔고, 원인이 이것이었다.
  test('정확 좌표라도 완전히 같은 자리면 최대 줌에서도 묶인다', () {
    final pins = [for (var i = 0; i < 39; i++) _pin('a$i', 37.5806, 127.0503)];

    final result = clusterPins(pins, 22);

    expect(result, hasLength(1));
    expect(result.single.count, 39);
    expect(result.single.isCluster, isTrue);
    // 확대해도 갈라지지 않는다는 표시. 이것이 false면 탭이 파고들기로 가서
    // 같은 묶음이 다시 나오고, 사용자에게는 반응이 없는 것으로 보인다.
    expect(result.single.sameSpot, isTrue);
    expect(result.single.approximate, isFalse);
  });

  test('같은 자리 묶음의 좌표는 원래 좌표 그대로다', () {
    // 이 좌표로 DB를 되물어 목록을 연다. 평균을 내다 미세하게 어긋나면
    // 조회가 빈 결과를 내고 목록이 안 열린다.
    final pins = [for (var i = 0; i < 3; i++) _pin('b$i', 37.5806, 127.0503)];

    final result = clusterPins(pins, 22).single;

    expect(result.lat, 37.5806);
    expect(result.lng, 127.0503);
  });

  test('같은 자리가 아닌 묶음은 sameSpot이 아니다', () {
    // 격자로 묶인 것은 확대하면 갈라진다. 파고들기가 맞다.
    final result = clusterPins([
      _pin('c0', 37.5806, 127.0503),
      _pin('c1', 37.5807, 127.0504),
    ], 12);

    expect(result.single.count, 2);
    expect(result.single.sameSpot, isFalse);
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

// 아이콘 이름이 갈리지 않으면 두 종류가 같은 그림으로 그려진다.
// 그러면 사용자는 확대하면 갈라지는 원과 갈라지지 않는 묶음을 구별할 수 없고,
// 숫자만큼의 점을 기대했다가 하나를 보게 된다 — 실제로 신고된 혼동이다.
void _iconNames() {
  group('묶음 아이콘 이름', () {
    test('같은 자리 묶음은 다른 이름을 받는다', () {
      expect(
        clusterIconName(39, false, true),
        isNot(clusterIconName(39, false, false)),
      );
    });

    test('근사 여부와 같은 자리 여부가 각각 갈린다', () {
      final names = {
        clusterIconName(39, false, false),
        clusterIconName(39, false, true),
        clusterIconName(39, true, false),
        clusterIconName(39, true, true),
      };
      expect(names, hasLength(4));
    });
  });
}

// 근사 묶음은 **같은 건물이 아니다.** 지번이 서로 다른데 좌표를 못 만들어
// 법정동 중심에 모아 둔 것이다. 두 경우를 같은 문장으로 설명하면 거짓이 된다.
void _stackKinds() {
  group('겹침의 이유', () {
    test('근사 묶음은 approximate로 표시된다', () {
      final pins = [
        for (var i = 0; i < 5; i++)
          _pin('u$i', 37.5806, 127.0503, precision: 'umd'),
      ];

      final result = clusterPins(pins, 22).single;

      expect(result.count, 5);
      expect(result.approximate, isTrue);
      expect(result.sameSpot, isTrue);
    });

    test('정확 좌표 묶음은 approximate가 아니다', () {
      final pins = [for (var i = 0; i < 5; i++) _pin('e$i', 37.5806, 127.0503)];

      final result = clusterPins(pins, 22).single;

      expect(result.approximate, isFalse);
      expect(result.sameSpot, isTrue);
    });
  });
}

/// 지도에 찍히는 이름.
///
/// **틀린 이름은 이름이 없는 것보다 나쁘다.** 격자로 끌어모은 묶음이나 법정동
/// 중심에 쌓은 묶음에 한 건물 이름이 붙으면, 사용자는 그 자리의 모든 거래를
/// 그 건물의 것으로 읽는다.
void _labels() {
  group('점 아래 이름', () {
    test('낱개는 건물 이름을 쓴다', () {
      final result = clusterPins([
        _pin('a', 37.5806, 127.0503, name: '워커힐아파트', jibun: '광장동 1'),
      ], 22).single;

      expect(result.label, '워커힐아파트');
    });

    test('이름이 없으면 지번으로 떨어진다', () {
      final result = clusterPins([
        _pin('a', 37.5806, 127.0503, jibun: '149-8'),
      ], 22).single;

      expect(result.label, '149-8');
    });

    test('이름 뒤에 붙은 지번 괄호는 뗀다', () {
      final result = clusterPins([
        _pin('a', 37.5806, 127.0503, name: '강변빌라(182-14)', jibun: '182-14'),
      ], 22).single;

      expect(result.label, '강변빌라');
    });

    test('이름이 통째로 지번 괄호면 지번을 쓴다', () {
      final result = clusterPins([
        _pin('a', 37.5806, 127.0503, name: '(175-65)', jibun: '175-65'),
      ], 22).single;

      expect(result.label, '175-65');
    });

    test('동 구분 괄호는 떼지 않는다', () {
      final result = clusterPins([
        _pin('a', 37.5806, 127.0503, name: '무지개빌라(B)', jibun: '1-1'),
      ], 22).single;

      expect(result.label, '무지개빌라(B)');
    });

    test('이름도 지번도 없으면 붙이지 않는다', () {
      final result = clusterPins([_pin('a', 37.5806, 127.0503)], 22).single;

      expect(result.label, isNull);
    });

    test('같은 자리 묶음은 하나라도 있는 이름을 쓴다', () {
      final result = clusterPins([
        _pin('a', 37.5806, 127.0503),
        _pin('b', 37.5806, 127.0503, name: '광장현대'),
      ], 22).single;

      expect(result.sameSpot, isTrue);
      expect(result.label, '광장현대');
    });

    test('격자로 끌어모은 묶음에는 이름이 없다', () {
      final result = clusterPins([
        _pin('a', 37.5806, 127.0503, name: '가나아파트'),
        _pin('b', 37.58061, 127.05031, name: '다라아파트'),
      ], 12).single;

      expect(result.isCluster, isTrue);
      expect(result.sameSpot, isFalse);
      expect(result.label, isNull);
    });

    test('근사 좌표 묶음에는 이름이 없다', () {
      final result = clusterPins([
        for (var i = 0; i < 3; i++)
          _pin('u$i', 37.5385, 127.0823, precision: 'umd', name: '어딘가'),
      ], 22).single;

      expect(result.approximate, isTrue);
      expect(result.label, isNull);
    });
  });
}
