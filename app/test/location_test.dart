import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/location.dart';
import 'package:realdealmap/data/sync/region_index.dart';
import 'package:realdealmap/features/map/locate.dart';

/// 첫 진입에서 좌표를 시군구로 푸는 규칙 (T5.9 · FR-1).
///
/// 위치 자체는 실기기에서만 나오지만, **좌표를 지역으로 바꾸는 판단**은 순수하다.
/// 거기가 틀리면 사용자는 남의 동네 시세를 자기 동네로 읽는다.
RegionSummary _region(
  String sggCd,
  String sidoName,
  String sggName, {
  required double lat,
  required double lng,
  double span = 0.05,
}) => RegionSummary(
  sggCd: sggCd,
  name: '$sidoName $sggName',
  sidoName: sidoName,
  sggName: sggName,
  records: 100,
  located: 100,
  refreshedAt: '2026-09-08T00:00:00Z',
  center: LatLng(lat, lng),
  bbox: BoundingBox(
    south: lat - span,
    north: lat + span,
    west: lng - span,
    east: lng + span,
  ),
);

/// 실기기 없이 위치 결과를 만들어 낸다.
class _FakeLocation implements LocationSource {
  const _FakeLocation(this.outcome, [this.fix]);
  final LocationOutcome outcome;
  final DeviceFix? fix;

  @override
  Future<(LocationOutcome, DeviceFix?)> current({bool precise = false}) async =>
      (outcome, fix);
}

/// 정밀 위치를 물어봤는지 기록한다.
class _PrecisionSpy implements LocationSource {
  bool? askedPrecise;

  @override
  Future<(LocationOutcome, DeviceFix?)> current({bool precise = false}) async {
    askedPrecise = precise;
    return (LocationOutcome.ok, const DeviceFix(37.50, 127.03));
  }
}

void main() {
  final gangnam = _region('11680', '서울특별시', '강남구', lat: 37.4979, lng: 127.0276);
  final busanjin = _region(
    '26230',
    '부산광역시',
    '부산진구',
    lat: 35.1628,
    lng: 129.0530,
  );
  final index = RegionIndex([gangnam, busanjin]);

  test('담는 지역이 있으면 그곳을 연다', () {
    final found = index.at(const LatLng(37.50, 127.03), null);

    expect(found?.sggCd, '11680');
  });

  // 배포되지 않은 지역에 있는 사용자에게 빈 화면을 주는 것보다, 가까운 데이터를
  // 보여주고 지역 이름을 밝히는 편이 낫다.
  test('담는 지역이 없으면 가장 가까운 곳으로 간다', () {
    final point = const LatLng(37.60, 127.10); // 강남구 밖, 그러나 가깝다

    expect(index.at(point, null), isNull);
    expect(index.nearest(point, null)?.sggCd, '11680');
  });

  // 서울에 있는 사용자에게 부산을 열어 주면 자기 동네로 오해한다.
  test('너무 멀면 아무 곳도 고르지 않는다', () {
    final pacific = const LatLng(20.0, 150.0);

    expect(index.at(pacific, null), isNull);
    expect(index.nearest(pacific, null), isNull);
  });

  test('경도는 위도에 따라 좁혀 잰다', () {
    // 위도 37도에서 경도 1도는 위도 1도보다 짧다. 보정하지 않으면 동서로
    // 떨어진 지역이 남북으로 같은 거리인 지역보다 가깝다고 나온다.
    final nearInLng = index.nearest(const LatLng(37.4979, 127.60), null);
    final nearInLat = index.nearest(const LatLng(38.10, 127.0276), null);

    expect(nearInLng?.sggCd, '11680');
    expect(nearInLat?.sggCd, '11680');
  });

  group('위치 실패', () {
    // 하나의 실패로 뭉뚱그리면 "권한을 거부했다"와 "GPS가 꺼져 있다"에 같은
    // 안내를 하게 되는데, 사용자가 해야 할 일이 서로 다르다.
    test('실패 사유가 서로 구별된다', () {
      expect(LocationOutcome.values, hasLength(5));
      expect({
        LocationOutcome.denied,
        LocationOutcome.deniedForever,
        LocationOutcome.disabled,
        LocationOutcome.failed,
      }, isNot(contains(LocationOutcome.ok)));
    });
  });

  /// 지도의 현재 위치 버튼이 무엇을 하는지.
  ///
  /// **좌표를 얻은 것과 그 자리에 거래가 있는 것은 다른 일이다.** 둘을 같은
  /// 실패로 뭉뚱그리면 사용자는 멀쩡한 위치 권한을 다시 뒤지게 된다.
  group('현재 위치로 가기', () {
    test('담는 지역이 있으면 좌표와 지역을 함께 준다', () async {
      final result = await locateHere(
        const _FakeLocation(LocationOutcome.ok, DeviceFix(37.50, 127.03)),
        index,
        null,
      );

      expect(result, isA<Located>());
      final located = result as Located;
      expect(located.lat, 37.50);
      expect(located.lng, 127.03);
      expect(located.region?.sggCd, '11680');
    });

    // 지역이 없어도 좌표는 유효하다. 지도는 옮겨 가야 한다.
    test('배포된 지역이 없어도 좌표는 준다', () async {
      final result = await locateHere(
        const _FakeLocation(LocationOutcome.ok, DeviceFix(20.0, 150.0)),
        index,
        null,
      );

      expect(result, isA<Located>());
      expect((result as Located).region, isNull);
    });

    test('좌표를 못 얻으면 사유를 그대로 넘긴다', () async {
      final result = await locateHere(
        const _FakeLocation(LocationOutcome.deniedForever),
        index,
        null,
      );

      expect((result as LocateFailed).outcome, LocationOutcome.deniedForever);
    });

    // 좌표를 시군구로 풀 근거가 없으면 권한 창부터 띄우지 않는다.
    test('색인이 없으면 위치를 묻지도 않는다', () async {
      var asked = false;
      final source = _SpyLocation(() => asked = true);

      final result = await locateHere(source, RegionIndex(const []), null);

      expect(result, isA<LocateNoIndex>());
      expect(asked, isFalse);
    });

    // 첫 진입의 자동 열기는 대략 위치만 받는다. 아직 아무것도 부탁하지 않은
    // 사용자에게 정확한 위치부터 요구하지 않는다.
    test('버튼은 정밀 위치를 물어본다', () async {
      final spy = _PrecisionSpy();

      await locateHere(spy, index, null);

      expect(spy.askedPrecise, isTrue);
    });

    // 사용자가 대략 위치만 줬는데 정확한 자리인 척하면 안 된다.
    test('대략 위치로 잡힌 것은 그렇다고 표시된다', () async {
      final result = await locateHere(
        const _FakeLocation(
          LocationOutcome.ok,
          DeviceFix(37.50, 127.03, precise: false),
        ),
        index,
        null,
      );

      expect((result as Located).precise, isFalse);
    });

    test('사유마다 다른 안내 문구가 나온다', () {
      final messages = {
        for (final o in LocationOutcome.values) o: locationProblem(o),
      };

      expect(messages[LocationOutcome.ok], isNull);
      final said = messages.values.nonNulls.toList();
      expect(said, hasLength(4));
      expect(said.toSet(), hasLength(4));
    });
  });
}

class _SpyLocation implements LocationSource {
  _SpyLocation(this.onAsk);
  final void Function() onAsk;

  @override
  Future<(LocationOutcome, DeviceFix?)> current({bool precise = false}) async {
    onAsk();
    return (LocationOutcome.failed, null);
  }
}
