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
class RegionPicker extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(regionIndexProvider);
    final selected = ref.watch(selectedRegionProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, controller) => switch (index) {
        AsyncData(:final value) when value.isEmpty => const _Notice(
          '아직 배포된 지역이 없습니다.\n서버가 첫 지역을 만들면 여기에 나타납니다.',
        ),
        AsyncData(:final value) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('지역', style: Theme.of(context).textTheme.labelSmall),
            for (final entry in value.bySido.entries) ...[
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
                      onTap: () => Navigator.of(context).pop(region.sggCd),
                    ),
                ],
              ),
            ],
          ],
        ),
        AsyncError() => const _Notice('지역 목록을 불러오지 못했습니다.'),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
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
