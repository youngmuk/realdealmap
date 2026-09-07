/// 광고 노출 시각을 들고 있는다 (T6.2 · FR-6).
///
/// **마지막 노출 시각은 앱을 껐다 켜도 남아야 한다.** 안 남기면 앱을 다시 열
/// 때마다 주기가 처음부터 시작되고, 자주 여닫는 사용자는 광고를 훨씬 자주 본다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ads/ad_policy.dart';
import '../features/ads/ads.dart';
import 'app_state.dart';

const String _lastShownKey = 'ad.last_at';
const String _firstRunKey = 'ad.first_run_at';

/// 지금은 광고 단위가 없다. 계정이 생기면 여기만 갈아 끼운다.
final adsProvider = Provider<InterstitialAds>(
  (ref) => const NoInterstitialAds(),
);

final adPolicyProvider = Provider<AdPolicy>((ref) => const AdPolicy());

/// 시각을 주입해 둔다. 광고는 "한 시간 뒤"가 규칙이라, 시계를 갈아 끼우지
/// 못하면 규칙을 시험하려고 한 시간을 기다려야 한다.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AdsState {
  const AdsState({
    required this.firstRunAt,
    required this.launchedAt,
    this.lastShownAt,
  });

  /// 이 기기에서 앱을 처음 연 시각. 한 번도 노출한 적이 없을 때의 기준점이다.
  final DateTime firstRunAt;

  /// 이번 실행이 시작된 시각. 켠 직후를 막는 데 쓰고, 저장하지 않는다.
  final DateTime launchedAt;

  final DateTime? lastShownAt;

  /// 다음 노출을 재는 기준. 노출한 적이 없으면 최초 실행 시각이다.
  DateTime get since => lastShownAt ?? firstRunAt;

  AdsState copyWith({DateTime? lastShownAt}) => AdsState(
    firstRunAt: firstRunAt,
    launchedAt: launchedAt,
    lastShownAt: lastShownAt ?? this.lastShownAt,
  );
}

class AdsController extends Notifier<AdsState> {
  /// 두 자리에서 동시에 물어오는 일이 있다 (예: 탭 전환 직후 포그라운드 복귀).
  /// 막지 않으면 광고가 두 편 연달아 뜬다.
  bool _showing = false;

  @override
  AdsState build() {
    final prefs = ref.read(prefsProvider);
    final now = ref.read(clockProvider)();

    final storedFirstRun = DateTime.tryParse(
      prefs.getString(_firstRunKey) ?? '',
    );
    if (storedFirstRun == null) {
      // 첫 실행이다. 여기서 기준점을 박아 두지 않으면 첫 안전 지점에서
      // 곧바로 광고가 뜨고, 그것이 이 앱의 첫인상이 된다.
      // build 안이라 기다릴 수 없다. 잃어도 다음 실행에서 다시 박히고,
      // 그때는 첫 주기가 한 번 더 미뤄질 뿐이라 손해가 사용자 쪽이 아니다.
      unawaited(prefs.setString(_firstRunKey, now.toIso8601String()));
    }

    return AdsState(
      firstRunAt: storedFirstRun ?? now,
      launchedAt: now,
      lastShownAt: DateTime.tryParse(prefs.getString(_lastShownKey) ?? ''),
    );
  }

  /// 안전 전환 지점에 닿았다고 알린다. 보여줬으면 참.
  ///
  /// [moment]를 받는 것이 이 설계의 핵심이다. 지도 팬·줌은 [AdMoment]에 없으므로
  /// 여기까지 올 방법이 없다 — 조심해서 안 부르는 것이 아니라 부를 수가 없다.
  Future<bool> onMoment(AdMoment moment) async {
    if (_showing) return false;

    final now = ref.read(clockProvider)();
    final due = ref
        .read(adPolicyProvider)
        .isDue(
          now: now,
          since: state.since,
          launchedAt: state.launchedAt,
          busy: ref.read(syncProvider).running,
        );
    if (!due) return false;

    _showing = true;
    try {
      // 못 보여줬으면 시각을 건드리지 않는다. 건드리면 광고는 안 나오고
      // 주기만 소모된다.
      if (!await ref.read(adsProvider).show()) return false;

      state = state.copyWith(lastShownAt: now);
      await ref
          .read(prefsProvider)
          .setString(_lastShownKey, now.toIso8601String());
      return true;
    } finally {
      _showing = false;
    }
  }
}

final adsControllerProvider = NotifierProvider<AdsController, AdsState>(
  AdsController.new,
);

extension AdMomentRef on WidgetRef {
  /// 안전 전환 지점에 닿았다고 알린다.
  ///
  /// 화면은 광고를 기다리지 않는다. 기다리게 하면 탭 전환이 광고 로딩만큼
  /// 느려지고, 그 느림은 광고가 없을 때도 남는다.
  void adMoment(AdMoment moment) =>
      unawaited(read(adsControllerProvider.notifier).onMoment(moment));
}
