/// 지도가 살아 있는지 지켜본다.
///
/// 첫 실행에서 위치 권한 대화상자가 뜨면 그 순간 지도의 표면이 파괴됐다 다시
/// 만들어지는데, 스타일이 아직 올라오는 중이면 그대로 멈춘다. 콜백이 영영 오지
/// 않아 소스도 레이어도 없는 빈 화면이 남는다. 탭을 옮겨도 돌아오지 않고, 앱을
/// 완전히 껐다 켜야 살아난다. 첫 실행에서 사용자가 처음 보는 화면이 그것이었다.
///
/// 원인을 하나로 특정해 막는 대신 **결과를 본다.** 정해진 시간 안에 스타일이
/// 오지 않으면 그 지도는 죽은 것이므로, 이유가 무엇이든 다시 만든다.
///
/// 규칙만 따로 떼어 둔 이유는 이것이 타이머와 예산이 얽힌 상태 기계이고,
/// 플랫폼 뷰에 묶인 채로는 시험할 수 없기 때문이다. 되돌아오는 회귀 — 예를 들어
/// 성공했을 때 예산을 되돌리는 자리를 옮기는 것 — 은 실기기에서나 드러난다.
library;

import 'dart:async';

/// 아직 못 지키는 것: 스타일이 **한 번 올라온 뒤에** 표면만 조용히 사라지는 경우.
/// 그때는 지켜보는 사람이 없다. maplibre는 스타일이 다시 로드되면 콜백을 다시
/// 주므로(저메모리 복귀 등) 실제로 관측된 적은 없고, 관측되기 전에 감시를 상시로
/// 돌리면 멀쩡한 지도를 주기적으로 다시 만들 위험이 더 크다고 봤다.
class StyleWatchdog {
  StyleWatchdog({
    required this.onStuck,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 3,
  });

  /// 멈췄다고 판단했을 때 부른다. 지도를 새로 만드는 일은 바깥이 한다.
  final void Function() onStuck;

  /// 스타일은 URL이 아니라 문자열이라 네트워크를 타지 않는다. 이 시간을 넘겼다면
  /// 느린 것이 아니라 멈춘 것이다.
  final Duration timeout;

  /// 무한히 다시 만들지 않는다. 정말로 못 그리는 기기에서 깜빡임만 남는다.
  final int maxRetries;

  Timer? _timer;
  int _used = 0;

  /// 지금까지 다시 만든 횟수. 시험과 진단용이다.
  int get retries => _used;

  bool get isWatching => _timer != null;

  /// 지켜보기 시작한다. 이미 보고 있었으면 처음부터 다시 센다.
  ///
  /// 예산이 다 떨어졌으면 아예 걸지 않는다. 걸어 두고 만료 때 아무것도 안 하면
  /// 타이머만 계속 도는데, 그것은 배터리를 쓰면서 아무 일도 하지 않는 것이다.
  void watch() {
    _timer?.cancel();
    if (_used >= maxRetries) {
      _timer = null;
      return;
    }
    _timer = Timer(timeout, () {
      _timer = null;
      _used++;
      onStuck();
    });
  }

  /// 스타일이 올라왔다. 지켜보기를 멈추고 **예산을 되돌린다.**
  ///
  /// 되돌리지 않으면 오래 켜 둔 앱에서 세 번째 사고 이후로는 영영 복구하지
  /// 않는다. 예산은 "한 사고를 몇 번까지 다시 시도하는가"이지 앱 생애 전체의
  /// 한도가 아니다.
  void recovered() {
    _timer?.cancel();
    _timer = null;
    _used = 0;
  }

  /// 스타일을 세우기 시작했다. 아직 끝난 것은 아니라 예산은 그대로 둔다.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
