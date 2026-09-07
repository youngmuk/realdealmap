import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/location.dart';
import 'data/sync/refresh_trigger.dart';
import 'data/sync/region_index.dart';
import 'data/sync/sync_engine.dart';
import 'format.dart';
import 'features/filter/filter_sheet.dart';
import 'features/list/list_page.dart';
import 'features/map/map_page.dart';
import 'features/region/region_picker.dart';
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

  @override
  void initState() {
    super.initState();
    // 첫 프레임 뒤에 시작한다. build 중에 상태를 건드리면 Riverpod이 막는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
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
    final (outcome, fix) = await ref.read(locationProvider).current();
    if (!mounted || fix == null) {
      if (mounted && outcome != LocationOutcome.ok) _sayWhyNoLocation(outcome);
      return;
    }

    final index = ref.read(regionIndexProvider).value;
    final point = LatLng(fix.lat, fix.lng);
    final region = index?.at(point) ?? index?.nearest(point);
    if (region == null || !mounted) return;

    ref.read(selectedRegionProvider.notifier).select(region.sggCd);
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

    ref.read(selectedRegionProvider.notifier).select(picked);
    unawaited(ref.read(syncProvider.notifier).syncRegion(picked));
  }

  @override
  Widget build(BuildContext context) {
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
                  region?.sggName ?? (sggCd ?? '지역 선택'),
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
            onPressed: () => FilterSheet.show(context),
            icon: const Icon(Icons.tune, size: 20),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(30),
          child: _StatusBar(),
        ),
      ),
      body: IndexedStack(index: _tab, children: const [MapPage(), ListPage()]),
      bottomNavigationBar: NavigationBar(
        height: 58,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: '지도'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: '목록'),
        ],
      ),
    );
  }
}

/// 데이터 기준 시각을 **상시 노출한다** (T5.8).
///
/// 실거래가는 값이 시각에 매인 데이터다. "언제 것인지"를 감추면 사용자는
/// 지금 시세로 읽는다. 갱신 중·오프라인도 여기서 같이 말한다 —
/// 조용히 실패해서 옛 데이터를 새것처럼 보여주는 것이 가장 나쁘다.
class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final (text, color) = _message(sync);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
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
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
