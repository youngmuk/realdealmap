/// 광고 시점 규칙 (T6.2 · FR-6).
///
/// **주기는 지키되 시점만 안전하게 옮긴다.** "무조건 1시간마다"를 지도 조작 중
/// 강제 노출로 구현하면 우발적 클릭을 유도하게 되고, 그것은 AdMob 정책 위반이며
/// 무엇보다 사용자를 속이는 일이다. 최대 지연은 다음 전환 지점까지다.
///
/// 이 파일에 화면도 SDK도 없다. 순수하기 때문에 규칙 자체를 시험할 수 있다 —
/// 광고는 실기기에서 눈으로 확인하기 가장 어려운 기능이라 더욱 그렇다.
library;

/// 광고를 물어봐도 되는 **자리**.
///
/// 여기 없는 순간에는 정책에 물어볼 수조차 없다. 지도 팬·줌 제스처가 이 목록에
/// 없는 것이 "지도 제스처 중 노출 0회"를 지키는 방식이다 — 호출부에서 조심하는
/// 것이 아니라, 부를 방법 자체를 두지 않는다.
enum AdMoment {
  /// 상세창을 닫은 직후
  detailClosed,

  /// 지도 ↔ 목록 탭 전환
  tabSwitched,

  /// 필터를 적용하고 결과를 보기 직전
  filterApplied,

  /// 앱이 백그라운드에서 돌아왔을 때
  resumed,
}

/// 마지막 노출로부터 이만큼 지나야 다시 보여준다 (FR-6).
const Duration kAdInterval = Duration(minutes: 60);

/// 앱을 켠 직후 이만큼은 광고를 띄우지 않는다.
///
/// 사용자는 무언가를 보러 앱을 열었다. 그 앞을 막고 광고부터 띄우면 앱을 여는
/// 일 자체가 손해가 된다. 켜자마자 탭을 눌러도 여기에 걸린다.
const Duration kAdLaunchGrace = Duration(seconds: 90);

/// 시각과 상태만 보고 판단한다. **어디서 물었는지**는 [AdMoment]가 이미 보증한다.
class AdPolicy {
  const AdPolicy({
    this.interval = kAdInterval,
    this.launchGrace = kAdLaunchGrace,
  });

  final Duration interval;
  final Duration launchGrace;

  /// [since]는 마지막 노출 시각이고, 한 번도 없었으면 **최초 실행 시각**이다.
  ///
  /// 설치 직후를 0으로 두면 첫 안전 지점에서 곧바로 광고가 뜬다. 처음 쓰는
  /// 사람에게 그것은 앱의 첫인상이 된다. 그래서 처음에도 한 주기를 기다린다.
  bool isDue({
    required DateTime now,
    required DateTime since,
    required DateTime launchedAt,
    required bool busy,
  }) {
    // 로딩 스피너 위에 광고를 얹으면 사용자는 광고를 로딩 실패로 읽는다.
    if (busy) return false;
    if (now.difference(launchedAt) < launchGrace) return false;
    return now.difference(since) >= interval;
  }
}
