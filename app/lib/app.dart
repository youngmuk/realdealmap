import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/sync/refresh_trigger.dart';
import 'data/sync/sync_engine.dart';
import 'format.dart';
import 'features/list/list_page.dart';
import 'features/map/map_page.dart';
import 'features/region/region_picker.dart';
import 'state/app_state.dart';
import 'state/filters.dart';
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

  /// 마지막으로 보던 지역을 되살린다 (FR-1).
  ///
  /// 없으면 아무 지역도 고르지 않는다. **임의로 서울을 열어 주지 않는다** —
  /// 사용자가 자기 동네라고 오해할 수 있고, 실거래가는 그 오해가 값비싼 데이터다.
  Future<void> _bootstrap() async {
    final saved = ref.read(selectedRegionProvider);
    if (saved != null) {
      await ref.read(syncProvider.notifier).syncRegion(saved);
    }
    await ref.read(regionIndexProvider.notifier).reload();
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
            onPressed: () => _FilterSheet.show(context),
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

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    backgroundColor: Palette.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _FilterSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);

    // 글자 배율이 커지면 내용이 화면을 넘는다. 넘치면 스크롤한다 —
    // 잘려서 안 보이는 설정은 없는 설정과 같다.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('필터', style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              if (!filter.isEmpty)
                TextButton(onPressed: notifier.clear, child: const Text('초기화')),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in kDatasetKeys)
                FilterChip(
                  label: Text(datasetLabel(key)),
                  // 비어 있으면 전부다. 하나도 안 고른 상태를 "전부"로 보여준다.
                  selected:
                      filter.datasetKeys.isEmpty ||
                      filter.datasetKeys.contains(key),
                  onSelected: (_) => notifier.toggleDataset(key),
                  selectedColor: Palette.accentSoft,
                  checkmarkColor: Palette.accent,
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: filter.includeCancelled,
            onChanged: notifier.setCancelled,
            title: const Text('해제된 거래 포함', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '해제도 사실입니다. 감추면 "왜 그 거래가 안 보이지"가 됩니다.',
              style: TextStyle(fontSize: 11.5, color: Palette.ink3),
            ),
          ),
        ],
      ),
    );
  }
}
