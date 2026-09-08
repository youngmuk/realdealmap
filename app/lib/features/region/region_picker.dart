import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/region_index.dart';
import '../../format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// 지역 선택 (FR-1 · T5.9).
///
/// **배포된 지역만 보여준다.** 카탈로그의 269개를 다 늘어놓으면 대부분이
/// 눌러도 빈 화면인데, 사용자는 앱이 고장 났다고 읽는다. 색인에 있는 것이
/// 곧 데이터가 있는 것이다.
class RegionPicker extends ConsumerStatefulWidget {
  const RegionPicker({super.key});

  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Palette.paper,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => const RegionPicker(),
      );

  @override
  ConsumerState<RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends ConsumerState<RegionPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(regionIndexProvider);
    final selected = ref.watch(selectedRegionProvider);

    return DraggableScrollableSheet(
      // 검색을 붙이면 키보드가 아래 절반을 덮는다. 0.6으로는 결과가 한 줄만
      // 보여서, 찾아 놓고도 고르지 못한다.
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => switch (index) {
        AsyncData(:final value) when value.isEmpty => const _Notice(
          '아직 배포된 지역이 없습니다.\n서버가 첫 지역을 만들면 여기에 나타납니다.',
        ),
        AsyncData(:final value) => _Body(
          controller: controller,
          groups: value.bySidoMatching(_search.text),
          selected: selected,
          search: _search,
          onQuery: () => setState(() {}),
        ),
        AsyncError() => const _Notice('지역 목록을 불러오지 못했습니다.'),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.groups,
    required this.selected,
    required this.search,
    required this.onQuery,
  });

  final ScrollController controller;
  final Map<String, List<RegionSummary>> groups;
  final String? selected;
  final TextEditingController search;
  final VoidCallback onQuery;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: search,
          onChanged: (_) => onQuery(),
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 14, color: Palette.ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: '지역 이름 (예: 중구, 울산)',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      search.clear();
                      onQuery();
                    },
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      // 키보드가 올라오면 시트 아래쪽이 그 뒤로 들어간다. 그대로 두면 검색
      // 결과의 아래쪽과 "없습니다" 안내가 키보드에 가려, 친 글자가 먹었는지
      // 아닌지를 화면으로 알 수 없다.
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: groups.isEmpty
              ? const _Notice('그 이름의 지역이 없습니다.')
              : ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    for (final entry in groups.entries) ...[
                      const SizedBox(height: 12),
                      Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Palette.ink2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final region in entry.value)
                            _RegionChip(
                              region: region,
                              selected: region.sggCd == selected,
                              onTap: () =>
                                  Navigator.of(context).pop(region.sggCd),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    ],
  );
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.region,
    required this.selected,
    required this.onTap,
  });

  final RegionSummary region;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? Palette.accentSoft : Palette.surface,
        border: Border.all(color: selected ? Palette.accent : Palette.rule),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            region.displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Palette.accent : Palette.ink,
            ),
          ),
          Text(
            '${formatCount(region.records)}건',
            style: const TextStyle(fontSize: 11, color: Palette.ink3),
          ),
        ],
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Palette.ink3, fontSize: 14, height: 1.6),
      ),
    ),
  );
}
