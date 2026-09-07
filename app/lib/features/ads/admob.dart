/// AdMob 전면광고 (T6.2 · FR-6).
///
/// [InterstitialAds] 뒤에 SDK를 두는 이유는 [ads.dart]에 적어 뒀다. 여기가
/// 그 구현이고, 시점 규칙([AdPolicy])은 이 파일을 전혀 모른다.
///
/// **지금은 구글이 공개한 테스트 단위를 쓴다.** 계정이 아직 없기도 하지만,
/// 개발 중에 실제 단위를 쓰면 자기 광고를 자기가 눌러 보게 되고 그것은 정책
/// 위반이다(계정이 정지된다). 계정이 생기면 [kAdUnitId]만 바꾸면 된다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads.dart';

/// 구글이 공개한 안드로이드 전면광고 테스트 단위.
///
/// 실제 단위로 바꿀 때 AndroidManifest의 APPLICATION_ID도 함께 바꿔야 한다.
/// 둘 중 하나만 바꾸면 광고가 조용히 안 나온다.
const String kTestInterstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';

/// 미리 받아 두고, 부르면 보여주고, 닫히면 다음 것을 받는다.
///
/// 미리 받지 않으면 "지금 보여줘"와 "받아 와" 사이의 몇 초 동안 화면이 멈춘
/// 것처럼 보인다. 안전 전환 지점(상세 닫기·탭 전환)에서 부르는데, 그 순간에
/// 멈추면 사용자는 자기 조작이 씹혔다고 읽는다.
class AdMobInterstitial implements InterstitialAds {
  AdMobInterstitial({this.unitId = kTestInterstitialUnitId});

  final String unitId;

  InterstitialAd? _ready;
  bool _loading = false;

  /// 받아 두기를 시작한다. 실패해도 조용히 넘어간다 — 광고가 없다고 앱이
  /// 곤란해질 이유는 없다.
  void preload() {
    if (_ready != null || _loading) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ready = ad;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          _ready = null;
          debugPrint('[RDM-ad] 못 받음: ${error.code} ${error.message}');
        },
      ),
    );
  }

  @override
  Future<bool> show() async {
    final ad = _ready;
    if (ad == null) {
      // 없으면 다음을 위해 받아 두고, **거짓을 돌려준다.**
      // 참을 돌려주면 안 보여주고도 한 주기를 소모한다.
      preload();
      return false;
    }
    _ready = null;

    // 닫힐 때까지 기다린다. 기다리지 않으면 광고가 뜬 채로 "보여줬다"가 되어
    // 그 뒤 화면 전환이 광고 위에서 벌어진다.
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!closed.isCompleted) closed.completeError(error);
        preload();
      },
    );

    try {
      await ad.show();
      await closed.future;
      return true;
    } on Object catch (error) {
      debugPrint('[RDM-ad] 못 보여줌: $error');
      return false;
    }
  }
}
