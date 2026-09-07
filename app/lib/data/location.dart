/// 기기 위치 (T5.9 · FR-1).
///
/// **위치는 기기 밖으로 나가지 않는다.** 좌표를 서버에 보내 지역을 물어보지 않고,
/// 이미 내려받은 지역 색인에서 담는 시군구를 고르는 데만 쓴다. 그래서 정밀 위치도
/// 필요 없다 — 시군구를 고르는 데 미터 단위 정확도는 아무 값어치가 없고,
/// 필요 없는 권한을 받는 것은 그 자체로 비용이다.
library;

import 'package:geolocator/geolocator.dart';

/// 위치를 못 얻었을 때 **왜 못 얻었는지**를 남긴다.
///
/// 하나의 실패로 뭉뚱그리면 "권한을 거부했다"와 "GPS가 꺼져 있다"에 같은 안내를
/// 하게 되는데, 사용자가 해야 할 일이 서로 다르다.
enum LocationOutcome {
  ok,

  /// 이번에 거부했다. 다음에 다시 물어볼 수 있다
  denied,

  /// 다시 묻지 않기로 했다. 앱에서 물어봐야 소용없고 설정으로 가야 한다
  deniedForever,

  /// 기기의 위치 기능이 꺼져 있다
  disabled,

  /// 권한은 있는데 좌표를 못 받았다 (실내·기기 문제 등)
  failed,
}

class DeviceFix {
  const DeviceFix(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// 테스트에서 갈아 끼우려고 인터페이스로 둔다. 위치는 시험 환경에서 만들어낼 수
/// 없는 값이라, 실물에 묶어 두면 첫 진입 로직 전체가 검증 불가능해진다.
abstract interface class LocationSource {
  Future<(LocationOutcome, DeviceFix?)> current();
}

class GeolocatorLocation implements LocationSource {
  const GeolocatorLocation();

  @override
  Future<(LocationOutcome, DeviceFix?)> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (LocationOutcome.disabled, null);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return (LocationOutcome.deniedForever, null);
    }
    if (permission == LocationPermission.denied) {
      return (LocationOutcome.denied, null);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // 시군구만 고르면 되므로 낮은 정확도로 충분하다. 높은 정확도를 요구하면
          // 실내에서 오래 기다리다 실패하는데, 그 기다림이 곧 빈 첫 화면이다.
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (
        LocationOutcome.ok,
        DeviceFix(position.latitude, position.longitude),
      );
    } on Exception {
      // 위치를 못 받은 것은 앱의 실패가 아니다. 지역을 직접 고르는 길이 늘 열려 있다.
      return (LocationOutcome.failed, null);
    }
  }
}
