/// 광고 표출 (T6.2 · FR-6).
///
/// **SDK를 인터페이스 뒤에 둔다.** 광고 계정은 아직 없고, 있더라도 실제 표출은
/// 테스트에서 만들어낼 수 없다. 시점 규칙([AdPolicy])만은 지금 완성해 두고
/// 시험할 수 있어야 한다 — 나중에 SDK를 붙일 때 고칠 곳이 여기 하나여야 한다.
library;

/// 전면광고 한 편.
abstract interface class InterstitialAds {
  /// 실제로 **보여줬을 때만** 참을 돌려준다.
  ///
  /// 이 구별이 중요하다. 못 보여줬는데 보여준 것으로 치면 다음 한 시간을
  /// 그냥 쉬게 된다 — 광고는 안 나오고 주기만 소모된다.
  Future<bool> show();
}

/// 광고 단위가 없을 때 (지금).
///
/// 조용히 아무것도 하지 않고 **거짓을 돌려준다**. 참을 돌려주면 노출 시각이
/// 갱신되어, 광고를 붙인 뒤에도 첫 한 시간이 통째로 사라진다.
class NoInterstitialAds implements InterstitialAds {
  const NoInterstitialAds();

  @override
  Future<bool> show() async => false;
}
