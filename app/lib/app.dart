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
import 'features/map/map_focus.dart';
import 'features/map/map_page.dart';
import 'features/region/region_picker.dart';
import 'features/settings/settings_sheet.dart';
import 'state/ads.dart';
import 'state/app_state.dart';
import 'theme.dart';

class RealDealMapApp extends StatelessWidget {
  const RealDealMapApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '실거래지도',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(textScaler: appTextScaler(media.textScaler)),
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
      onResume: () {
        ref.adMoment(AdMoment.resumed);
        _syncOnResume();
      },
    );
  }

  /// 앱으로 돌아왔을 때 다시 맞춘다.
  ///
  /// 동기화는 앱을 켤 때와 지역을 바꿀 때만 걸렸다. 그래서 앱을 켜 둔 채
  /// 하루를 두면 **화면의 기준 시각이 어제 것인 채로 남는다.** 실거래가는
  /// 값이 시각에 매인 데이터라 그것으로는 쓸모가 없다.
  ///
  /// 매번 원천을 부르는 것이 아니다. 매니페스트 하나(수십 KB)를 받아
  /// 바뀐 청크가 있을 때만 내려받고, 갱신 요청은 TTL을 넘겼을 때만 나간다.
  /// 판단은 [SyncController]가 하므로 여기서는 부르기만 한다.
  void _syncOnResume() {
    final region = ref.read(selectedRegionProvider);
    if (region == null) return;
    unawaited(ref.read(syncProvider.notifier).syncRegion(region));
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

  /// 왜 위치로 열지 못했는지 한 줄로 말한다. 문구는 [locationProblem]에 있다 —
  /// 지도의 현재 위치 버튼도 같은 것을 쓴다.
  void _sayWhyNoLocation(LocationOutcome outcome) {
    final message = locationProblem(outcome);
    if (message == null) return;
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
    // 상세창에서 "지도에서 보기"를 눌렀다. 카메라는 지도 화면이 스스로 옮기고,
    // 여기서는 탭만 바꾼다 — 목록 탭에서 눌렀다면 지도가 안 보이는 채로
    // 카메라만 움직여 아무 일도 안 일어난 것처럼 보인다.
    //
    // 광고 시점으로는 세지 않는다. 지도로 데려가 달라고 눌렀는데 전면광고가
    // 뜨면, 사용자가 부른 것은 지도지 광고가 아니다.
    ref.listen(mapFocusProvider, (_, next) {
      if (next != null && _tab != 0) setState(() => _tab = 0);
    });

    // 색인이 늦게 도착하면 그때 위치로 열어 본다.
    ref.listen(regionIndexProvider, (_, next) {
      if (next.value == null || next.value!.isEmpty) return;
      if (ref.read(selectedRegionProvider) != null) return;
      unawaited(_openHere());
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        // 머리말 맨 윗줄은 **기준 시각**이다. 지역 이름은 아래로 내려
        // 지도에 붙였다 — 지도를 보다 지역을 바꾸는 동선이라, 눈이 가는
        // 자리와 누르는 자리가 가까울수록 낫다.
        title: const _SyncLine(),
        actions: [
          IconButton(
            tooltip: '필터',
            onPressed: () async {
              await FilterSheet.show(context);
              if (mounted) ref.adMoment(AdMoment.filterApplied);
            },
            // 20에서 2배. 머리말에서 누를 것이 이것 하나뿐이라 크게 둔다.
            icon: const Icon(Icons.tune, size: 40),
          ),
        ],
        bottom: PreferredSize(
          // 글자 배율을 태운다. 30으로 고정하면 배율이 커졌을 때 기준 시각이
          // 잘려 "오프라인 (저장된 데이…"가 된다 — 잘린 경고는 경고가 아니다.
          //
          // 지도 바로 위에 지역 이름 한 줄(28)을 잡는다. 설정이 빠진
          // 빌드에서는 경고 줄이 하나 더 붙는다 — 자리를 안 주면 넘쳐서
          // 잘리고, 잘린 경고는 경고가 아니게 된다.
          preferredSize: Size.fromHeight(
            MediaQuery.textScalerOf(context).scale(
              28 +
                  ref.watch(configProvider).issues.length *
                      (kConfigWarningHeight + 2),
            ),
          ),
          child: _RegionBar(onTap: _pickRegion),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          MapPage(onShowList: () => _showTab(1)),
          const ListPage(),
        ],
      ),
      // 설정을 **탭 막대 옆**에 둔다. 지도 위에 띄워 두면 그 아래 마커를
      // 가리고, 지도를 움직이다 잘못 누르기도 한다. 여기 두면 어느 탭에서든
      // 같은 자리에 있으면서 지도를 한 픽셀도 덮지 않는다 —
      // 참고용 고지가 그 안에 있으므로 이 자리가 곧 G6를 지키는 방식이다.
      //
      // **NavigationDestination으로 넣지 않는다.** 그러면 세 번째 탭처럼
      // 보이는데 실제로는 시트를 열 뿐 화면을 바꾸지 않는다. 선택 표시가
      // 생겼다 사라지는 것을 사용자는 고장으로 읽는다.
      bottomNavigationBar: Row(
        children: [
          Expanded(
            child: NavigationBar(
              height: 58,
              selectedIndex: _tab,
              onDestinationSelected: _showTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  label: '지도',
                ),
                NavigationDestination(icon: Icon(Icons.list_alt), label: '목록'),
              ],
            ),
          ),
          const _SettingsButton(),
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

/// 머리말 맨 윗줄 — 데이터 기준 시각 (T5.8).
///
/// 실거래가는 값이 시각에 매인 데이터다. "언제 것인지"를 감추면 사용자는
/// 지금 시세로 읽는다. 갱신 중·오프라인도 여기서 같이 말한다 —
/// 조용히 실패해서 옛 데이터를 새것처럼 보여주는 것이 가장 나쁘다.
///
/// **누를 수 없다.** 전에는 이 줄 전체가 [AboutSheet]로 가는 자리였는데,
/// 고지가 설정으로 옮겨 가면서 그 뜻이 없어졌다. 눌러도 아무 일이 없는 것보다
/// 누를 곳처럼 보이지 않는 편이 낫다.
class _SyncLine extends ConsumerWidget {
  const _SyncLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final (text, color) = _message(sync);

    return Row(
      children: [
        if (sync.running) ...[
          const SizedBox(
            width: 9,
            height: 9,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            // 6.9에서 2배. 60%로 줄였더니 실기기에서 너무 작았다 —
            // 확인하려고 있는 줄이라도 읽히기는 해야 한다.
            // 앱 전체가 글자를 2배로 키우므로 화면에서는 27.6pt로 나온다.
            style: TextStyle(fontSize: 13.8, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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

/// 지도 바로 위 — 지역 이름과 설정 경고.
///
/// 지도에 붙여 둔다. 지도를 보다 지역을 바꾸는 동선이라, 눈이 가는 자리와
/// 누르는 자리가 가까울수록 낫다. 머리말 맨 위에 있을 때는 기준 시각과
/// 나란히 놓여 둘 다 상태 표시처럼 읽혔다.
class _RegionBar extends ConsumerWidget {
  const _RegionBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sggCd = ref.watch(selectedRegionProvider);
    final region = ref.watch(regionIndexProvider).value?.byCode(sggCd ?? '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
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
                    // 18의 90%.
                    style: const TextStyle(
                      fontSize: 16.2,
                      fontWeight: FontWeight.w800,
                      color: Palette.ink,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
          const ConfigWarning(),
        ],
      ),
    );
  }
}

/// 탭 막대 오른쪽 끝의 설정 버튼.
///
/// 지도와 목록 어느 탭에서든 같은 자리에 있다. 참고용 고지가 그 안에 있어,
/// **이 버튼에 닿는다는 것이 곧 고지가 표시된다는 뜻**이 된다 (G6).
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) => Material(
    // 탭 막대와 같은 바탕이라야 한 줄로 이어져 보인다.
    color: Theme.of(context).navigationBarTheme.backgroundColor,
    child: InkWell(
      onTap: () => SettingsSheet.show(context),
      // 탭 막대와 같은 높이(58). 옆에 서는 것이라 높이가 어긋나면 눈에 띈다.
      child: const SizedBox(
        width: 58,
        height: 58,
        child: Icon(Icons.settings_outlined, size: 22, color: Palette.slate),
      ),
    ),
  );
}
