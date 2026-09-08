import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/location.dart';
import 'data/sync/refresh_trigger.dart';
import 'data/sync/region_index.dart';
import 'data/sync/sync_engine.dart';
import 'format.dart';
import 'features/about/about_sheet.dart';
import 'features/ads/ad_policy.dart';
import 'features/filter/filter_sheet.dart';
import 'features/list/list_page.dart';
import 'features/map/map_page.dart';
import 'features/region/region_picker.dart';
import 'state/ads.dart';
import 'state/app_state.dart';
import 'theme.dart';

class RealDealMapApp extends StatelessWidget {
  const RealDealMapApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '실거래가 지도',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          textScaler: TextScaler.linear(media.textScaler.scale(1) * kTextScale),
        ),
        child: child!,
      );
    },
    home: const HomeShell(),
  );
}

/// 지도와 목록은 **같은 데이터를 다르게 보는 것**이라 탭으로 나란히 둔다.
/// 화면을 갈아 끼우지 않고 상태를 유지해야 지도를 보다 목록을 확인하고
/// 돌아왔을 때 지도가 처음부터 다시 그려지지 않는다.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  /// 포그라운드 복귀는 광고를 물어봐도 되는 자리 중 하나다 (FR-6).
  AppLifecycleListener? _lifecycle;

  /// 위치로 지역을 여는 것은 **한 번만** 시도한다. 색인이 늦게 와서 다시 부를
  /// 때도 마찬가지다 — 실패할 때마다 권한 창을 다시 띄우면 앱이 아니라 성가심이다.
  bool _triedLocation = false;

  @override
  void initState() {
    super.initState();
    // 첫 프레임 뒤에 시작한다. build 중에 상태를 건드리면 Riverpod이 막는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    // 여기서 미리 만든다. 첫 안전 지점에서야 만들면 "앱을 켠 시각"이 그
    // 순간으로 잡히고, 켠 직후 제한이 앱 실행이 아니라 첫 조작을 기준으로
    // 걸린다 — 10분 뒤 탭을 처음 눌러도 거기서 90초를 더 기다리게 된다.
    ref.read(adsControllerProvider);
    // 켠 직후에도 한 번 불리지만 [kAdLaunchGrace]가 막는다.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.adMoment(AdMoment.resumed),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// 마지막으로 보던 지역을 되살리고, 없으면 **지금 있는 곳**을 연다 (FR-1 · T5.9).
  ///
  /// 위치를 못 얻으면 아무 지역도 고르지 않는다. **임의로 서울을 열어 주지 않는다** —
  /// 사용자가 자기 동네라고 오해할 수 있고, 실거래가는 그 오해가 값비싼 데이터다.
  Future<void> _bootstrap() async {
    final saved = ref.read(selectedRegionProvider);
    if (saved != null) {
      await ref.read(syncProvider.notifier).syncRegion(saved);
      await ref.read(regionIndexProvider.notifier).reload();
      // 색인이 왔으니 이제 이 지역의 이름을 안다. 남겨 두면 **다음에 앱을 켤 때
      // 색인을 기다리지 않고** 머리말이 제 이름으로 뜬다.
      //
      // 여기서 하지 않으면 이름이 영영 안 남는다 — 이 갈래는 지역이 이미
      // 정해져 있어 select()를 부르지 않기 때문이다. 실기기에서 머리말이
      // 계속 "지역 확인 중"에 머무는 것으로 드러났다.
      if (!mounted) return;
      final name = ref
          .read(regionIndexProvider)
          .value
          ?.byCode(saved)
          ?.displayName;
      if (name != null) ref.read(lastRegionNameProvider.notifier).set(name);
      return;
    }

    // 색인이 먼저다. 좌표를 시군구로 푸는 근거가 색인이라, 없으면 위치를 받아도
    // 쓸 데가 없다.
    await ref.read(regionIndexProvider.notifier).reload();
    if (!mounted) return;
    await _openHere();
  }

  /// 지금 있는 곳의 시군구를 연다.
  ///
  /// 담는 지역이 없으면 가장 가까운 곳으로 간다. 배포되지 않은 지역에 있는
  /// 사용자에게 빈 화면을 주는 것보다, 가까운 데이터를 보여주고 지역 이름을
  /// 밝히는 편이 낫다.
  Future<void> _openHere() async {
    if (_triedLocation) return;
    // 색인이 없으면 좌표를 시군구로 풀 수 없다. 아직 시도한 것으로 치지 않고
    // 색인이 도착할 때 다시 부른다 — 첫 실행에 네트워크가 늦으면 색인이 비어서
    // 오는데, 그대로 포기하면 사용자는 영영 직접 골라야 한다.
    if (ref.read(regionIndexProvider).value?.isEmpty ?? true) return;
    _triedLocation = true;

    final (outcome, fix) = await ref.read(locationProvider).current();
    if (!mounted || fix == null) {
      if (mounted && outcome != LocationOutcome.ok) _sayWhyNoLocation(outcome);
      return;
    }

    final index = ref.read(regionIndexProvider).value;
    final point = LatLng(fix.lat, fix.lng);
    final region = index?.at(point) ?? index?.nearest(point);
    if (region == null || !mounted) return;

    ref
        .read(selectedRegionProvider.notifier)
        .select(region.sggCd, name: region.displayName);
    // 사용자가 고른 것과 같은 자격이다. 지도가 이 신호를 보고 그쪽으로 옮긴다.
    ref.read(regionFocusProvider.notifier).request();
    unawaited(ref.read(syncProvider.notifier).syncRegion(region.sggCd));
  }

  /// 왜 위치로 열지 못했는지 한 줄로 말한다.
  ///
  /// 조용히 넘어가면 사용자는 앱이 자기 동네를 못 찾은 이유를 알 수 없고,
  /// 무엇을 하면 되는지도 모른다.
  void _sayWhyNoLocation(LocationOutcome outcome) {
    final message = switch (outcome) {
      LocationOutcome.denied => '위치 권한이 없어 지역을 직접 고르셔야 합니다.',
      LocationOutcome.deniedForever => '위치 권한이 꺼져 있습니다. 설정에서 켜거나 지역을 직접 고르세요.',
      LocationOutcome.disabled => '기기의 위치 기능이 꺼져 있습니다. 지역을 직접 고르세요.',
      LocationOutcome.failed => '현재 위치를 확인하지 못했습니다. 지역을 직접 고르세요.',
      LocationOutcome.ok => '',
    };
    if (message.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickRegion() async {
    final picked = await RegionPicker.show(context);
    if (picked == null || !mounted) return;

    // 고른 지역의 이름을 여기서 알고 있다. 같이 남겨 두면 다음에 앱을 켤 때
    // 색인이 오기 전에도 머리말이 제 이름으로 뜬다.
    final name = ref
        .read(regionIndexProvider)
        .value
        ?.byCode(picked)
        ?.displayName;
    ref.read(selectedRegionProvider.notifier).select(picked, name: name);
    ref.read(regionFocusProvider.notifier).request();
    unawaited(ref.read(syncProvider.notifier).syncRegion(picked));
  }

  void _showTab(int index) {
    setState(() => _tab = index);
    ref.adMoment(AdMoment.tabSwitched);
  }

  @override
  Widget build(BuildContext context) {
    // 색인이 늦게 도착하면 그때 위치로 열어 본다.
    ref.listen(regionIndexProvider, (_, next) {
      if (next.value == null || next.value!.isEmpty) return;
      if (ref.read(selectedRegionProvider) != null) return;
      unawaited(_openHere());
    });

    final index = ref.watch(regionIndexProvider).value;
    final sggCd = ref.watch(selectedRegionProvider);
    final region = sggCd == null ? null : index?.byCode(sggCd);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: InkWell(
          onTap: _pickRegion,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  // 색인이 오기 전에는 마지막으로 알던 이름을 쓴다.
                  // **시군구 코드는 보여주지 않는다** — 사용자에게 아무 뜻이 없다.
                  region?.displayName ??
                      ref.watch(lastRegionNameProvider) ??
                      (sggCd == null ? '지역 선택' : '지역 확인 중'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: '필터',
            onPressed: () async {
              await FilterSheet.show(context);
              if (mounted) ref.adMoment(AdMoment.filterApplied);
            },
            icon: const Icon(Icons.tune, size: 20),
          ),
        ],
        bottom: PreferredSize(
          // 글자 배율을 태운다. 30으로 고정하면 배율이 커졌을 때 기준 시각이
          // 잘려 "오프라인 (저장된 데이…"가 된다 — 잘린 경고는 경고가 아니다.
          //
          // 기준 시각 두 줄(30)에 참고용 고지 한 줄을 더한다 (T6.6 · G6).
          // 설정이 빠진 빌드에서는 경고 줄이 하나 더 붙는다 — 자리를 안 주면
          // 넘쳐서 잘리고, 잘린 경고는 다시 경고가 아니게 된다.
          preferredSize: Size.fromHeight(
            MediaQuery.textScalerOf(context).scale(
              30 +
                  kAboutBannerHeight +
                  ref.watch(configProvider).issues.length *
                      (kConfigWarningHeight + 2),
            ),
          ),
          child: const _StatusBar(),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          MapPage(onShowList: () => _showTab(1)),
          const ListPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 58,
        selectedIndex: _tab,
        onDestinationSelected: _showTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: '지도'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: '목록'),
        ],
      ),
    );
  }
}

/// 데이터 기준 시각과 참고용 고지를 **상시 노출한다** (T5.8 · T6.6).
///
/// 실거래가는 값이 시각에 매인 데이터다. "언제 것인지"를 감추면 사용자는
/// 지금 시세로 읽는다. 갱신 중·오프라인도 여기서 같이 말한다 —
/// 조용히 실패해서 옛 데이터를 새것처럼 보여주는 것이 가장 나쁘다.
///
/// 여기에 둔 이유는 **지도와 목록 두 탭 모두에서 항상 보이는 유일한 자리**라서다.
/// 지도 범례에 두면 목록 탭에서 사라지고, 그때 고지는 상시가 아니게 된다.
/// 빠진 설정을 화면에 대고 말한다.
///
/// 이 자리는 개발자에게 하는 말이지 사용자에게 하는 말이 아니다. 그래도 앱 안에
/// 두는 이유는, 빌드 스크립트는 우회할 수 있어도 첫 화면은 우회할 수 없기 때문이다.
/// 값을 빠뜨린 빌드를 스토어에 올리려면 이것을 보고도 올려야 한다.
/// 경고 한 줄이 차지하는 높이. 상태바가 내주는 예산이 이 값을 사유 수만큼 잡는다.
const double kConfigWarningHeight = 20;

/// 빠진 설정을 화면에 대고 말한다.
///
/// 이 자리는 개발자에게 하는 말이지 사용자에게 하는 말이 아니다. 그래도 앱 안에
/// 두는 이유는, 빌드 스크립트는 우회할 수 있어도 첫 화면은 우회할 수 없기 때문이다.
/// 값을 빠뜨린 빌드를 스토어에 올리려면 이것을 보고도 올려야 한다.
///
/// 사유마다 한 줄씩 준다. 이어 붙이면 좁은 화면에서 줄이 접히고, 접힌 만큼
/// 상태바 예산을 넘겨 잘린다 — 잘린 경고는 다시 경고가 아니다 (고지 배너와 같다).
class ConfigWarning extends ConsumerWidget {
  const ConfigWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(configProvider).issues;
    if (issues.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final issue in issues)
          Container(
            height: MediaQuery.textScalerOf(
              context,
            ).scale(kConfigWarningHeight),
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: Palette.danger,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '출시 불가 · ${issue.message}',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final (text, color) = _message(sync);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (sync.running)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              if (sync.running) const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 11.5, color: color),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const AboutBanner(),
          const ConfigWarning(),
        ],
      ),
    );
  }

  (String, Color) _message(SyncState sync) {
    if (sync.running) return ('갱신 확인 중', Palette.ink3);

    final base = sync.refreshedAt == null
        ? '기준 시각 없음'
        : '기준 ${formatAge(sync.refreshedAt!, DateTime.now().toUtc())} '
              '· ${sync.refreshedAt!.toLocal().toString().substring(0, 16)}';

    return switch (sync.last) {
      SyncStatus.offline => ('$base · 오프라인 (저장된 데이터)', Palette.warn),
      SyncStatus.rejected => ('$base · 새 데이터를 거부했습니다', Palette.danger),
      SyncStatus.absent => ('아직 배포되지 않은 지역입니다', Palette.warn),
      _ when sync.triggered == TriggerResult.accepted => (
        '$base · 새 데이터를 만드는 중',
        Palette.ink3,
      ),
      _ => (base, Palette.ink3),
    };
  }
}
