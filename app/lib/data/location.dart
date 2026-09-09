/// 기기 위치 (T5.9 · FR-1).
///
/// **위치는 기기 밖으로 나가지 않는다.** 좌표를 서버에 보내 지역을 물어보지 않고,
/// 이미 내려받은 지역 색인에서 담는 시군구를 고르는 데만 쓴다. 그래서 정밀 위치도
/// 필요 없다 — 시군구를 고르는 데 미터 단위 정확도는 아무 값어치가 없고,
/// 필요 없는 권한을 받는 것은 그 자체로 비용이다.
library;

import 'package:flutter/services.dart';
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

/// 왜 위치를 못 얻었는지 한 줄로 말한다. 얻었으면 null이다.
///
/// **문구를 여기 두는 이유**는 부르는 자리가 둘이기 때문이다 — 첫 실행의 자동
/// 열기(app.dart)와 지도의 현재 위치 버튼. 각자 적어 두면 한쪽만 고쳐져
/// 같은 상황에 다른 안내가 나간다.
///
/// 조용히 넘어가지 않는다. 아무 말이 없으면 사용자는 앱이 자기 동네를 못 찾은
/// 이유도, 무엇을 하면 되는지도 알 수 없다.
String? locationProblem(LocationOutcome outcome) => switch (outcome) {
  LocationOutcome.denied => '위치 권한이 없어 지역을 직접 고르셔야 합니다.',
  LocationOutcome.deniedForever => '위치 권한이 꺼져 있습니다. 설정에서 켜거나 지역을 직접 고르세요.',
  LocationOutcome.disabled => '기기의 위치 기능이 꺼져 있습니다. 지역을 직접 고르세요.',
  LocationOutcome.failed => '현재 위치를 확인하지 못했습니다. 지역을 직접 고르세요.',
  LocationOutcome.ok => null,
};

class DeviceFix {
  const DeviceFix(this.lat, this.lng, {this.precise = true});

  final double lat;
  final double lng;

  /// 정밀 위치로 잡은 좌표인가.
  ///
  /// **거짓이면 좌표를 그대로 믿으면 안 된다.** 안드로이드의 대략 위치는
  /// 일부러 1~2km 격자로 뭉갠 값이라, 그것을 줌 16으로 열면 사용자는
  /// 자기가 서 있지도 않은 골목을 "현재 위치"로 본다. 실기기에서 군자동이
  /// 동대문구 장안동으로 나왔다.
  final bool precise;
}

/// 테스트에서 갈아 끼우려고 인터페이스로 둔다. 위치는 시험 환경에서 만들어낼 수
/// 없는 값이라, 실물에 묶어 두면 첫 진입 로직 전체가 검증 불가능해진다.
abstract interface class LocationSource {
  /// [precise]는 **정밀 위치를 물어봐도 되는 자리인가**를 뜻한다.
  ///
  /// 첫 진입의 자동 열기는 거짓이다 — 아직 아무것도 부탁하지 않은 사용자에게
  /// 정확한 위치부터 요구하지 않는다. 지도의 "현재 위치" 버튼만 참이다.
  ///
  /// 참으로 불러도 사용자가 대략 위치만 주면 그대로 진행한다. 그때는
  /// [DeviceFix.precise]가 거짓이라, 화면이 그 사실을 말할 수 있다.
  Future<(LocationOutcome, DeviceFix?)> current({bool precise = false});
}

class GeolocatorLocation implements LocationSource {
  const GeolocatorLocation();

  /// 권한 요청만 네이티브로 넘긴다 — 이유는 `MainActivity.kt`에 적어 두었다.
  /// 요약하면 geolocator는 매니페스트에 있는 위치 권한을 전부 한꺼번에 요청해,
  /// 정밀 위치를 선언하는 순간 첫 실행에도 "정확한 위치" 창이 뜬다.
  static const _permissions = MethodChannel('realdealmap/location_permission');

  @override
  Future<(LocationOutcome, DeviceFix?)> current({bool precise = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (LocationOutcome.disabled, null);
    }

    final granted = await _grant(precise: precise);
    if (granted == _Grant.deniedForever) {
      return (LocationOutcome.deniedForever, null);
    }
    if (granted == _Grant.none) return (LocationOutcome.denied, null);

    final fine = granted == _Grant.fine;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          // 정밀 위치를 받았을 때만 높은 정확도를 요구한다. 대략 위치만
          // 있는데 높게 부르면 뭉갠 값을 얻으려고 오래 기다리기만 한다.
          accuracy: fine ? LocationAccuracy.high : LocationAccuracy.low,
          // 정확도를 높이면 그만큼 오래 걸린다. 그래도 상한은 둔다 —
          // 실내에서 영영 안 돌아오면 버튼이 멈춘 것으로 보인다.
          timeLimit: Duration(seconds: fine ? 12 : 8),
        ),
      );
      return (
        LocationOutcome.ok,
        DeviceFix(position.latitude, position.longitude, precise: fine),
      );
    } on Exception {
      // 위치를 못 받은 것은 앱의 실패가 아니다. 지역을 직접 고르는 길이 늘 열려 있다.
      return (LocationOutcome.failed, null);
    }
  }

  /// 필요한 만큼만 받아 온다. 이미 있으면 창을 띄우지 않는다.
  Future<_Grant> _grant({required bool precise}) async {
    try {
      final current = _parse(await _permissions.invokeMethod<String>('status'));
      // 대략 위치만 필요한데 이미 있으면 그대로 쓴다. 정밀 위치가 이미
      // 있는 경우도 마찬가지다 — 있는 것을 다시 묻지 않는다.
      if (current == _Grant.fine) return current;
      if (!precise && current == _Grant.coarse) return current;

      return _parse(
        await _permissions.invokeMethod<String>(
          precise ? 'requestFine' : 'requestCoarse',
        ),
      );
    } on PlatformException {
      return _Grant.none;
    } on MissingPluginException {
      // 이 통로가 없는 플랫폼. geolocator의 기본 경로로 떨어진다 —
      // 단계는 못 나누지만 위치 자체는 동작한다.
      final permission = await Geolocator.checkPermission();
      final decided = permission == LocationPermission.denied
          ? await Geolocator.requestPermission()
          : permission;
      return switch (decided) {
        LocationPermission.always ||
        LocationPermission.whileInUse => _Grant.fine,
        LocationPermission.deniedForever => _Grant.deniedForever,
        _ => _Grant.none,
      };
    }
  }

  static _Grant _parse(String? value) => switch (value) {
    'fine' => _Grant.fine,
    'coarse' => _Grant.coarse,
    'denied_forever' => _Grant.deniedForever,
    _ => _Grant.none,
  };
}

/// 지금 받아 둔 위치 권한의 크기.
enum _Grant { none, coarse, fine, deniedForever }
