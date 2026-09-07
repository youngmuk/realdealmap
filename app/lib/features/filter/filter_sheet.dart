import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../format.dart';
import '../../state/app_state.dart';
import '../../state/filters.dart';
import '../../theme.dart';

/// 필터 (FR-4).
///
/// **지도와 목록에 같은 필터가 걸린다.** 둘이 따로 놀면 "목록에는 있는데 지도에
/// 없다"가 필터 때문인지 좌표가 없어서인지 사용자가 구별할 수 없다.
class FilterSheet extends ConsumerWidget {
  const FilterSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const FilterSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => ListView(
        controller: scroll,
        // 글자 배율이 커지면 내용이 화면을 넘는다. 넘치면 스크롤한다 —
        // 잘려서 안 보이는 설정은 없는 설정과 같다.
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Row(
            children: [
              Text('필터', style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              if (!filter.isEmpty)
                TextButton(onPressed: notifier.clear, child: const Text('초기화')),
            ],
          ),
          const SectionLabel('거래 종류'),
          _Chips(
            labels: kTradeLabels,
            // 비어 있으면 전부다. 하나도 안 고른 상태를 "전부"로 보여준다.
            selected: filter.selectedTrades,
            available: filter.availableTrades,
            onTap: notifier.toggleTrade,
          ),
          const SectionLabel('매물 유형'),
          _Chips(
            labels: kPropertyLabels,
            selected: filter.selectedProperties,
            available: filter.availableProperties,
            onTap: notifier.toggleProperty,
          ),
          if (!filter.availableProperties.contains('land'))
            const _Hint('토지는 매매만 있습니다'),
          const SectionLabel('계약 연월'),
          const _MonthPicker(),
          const SectionLabel('가격'),
          const _PriceRange(),
          const SizedBox(height: 4),
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

/// 데이터에 실제로 있는 달만 보여준다.
///
/// 달력을 띄우면 사용자가 데이터 없는 달을 고를 수 있고, 그때 빈 화면은
/// 앱이 고장 난 것으로 읽힌다. 고를 수 있는 것이 곧 있는 것이어야 한다.
class _MonthPicker extends ConsumerWidget {
  const _MonthPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sggCd = ref.watch(selectedRegionProvider);
    if (sggCd == null) return const _Hint('지역을 먼저 고르세요');

    final db = ref.watch(databaseProvider);
    // 데이터가 실제로 바뀌면 달 목록도 달라진다. 그때만 다시 읽는다.
    ref.watch(syncProvider.select((s) => s.revision));
    final selected = ref.watch(filterProvider).months;

    return FutureBuilder<List<String>>(
      future: db.availableMonths(sggCd),
      builder: (context, snapshot) {
        final months = snapshot.data;
        if (months == null) return const _Hint('불러오는 중');
        if (months.isEmpty) return const _Hint('아직 받은 거래가 없습니다');

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final month in months)
              FilterChip(
                label: Text(formatMonth(month)),
                selected: selected.isEmpty || selected.contains(month),
                onSelected: (_) => ref
                    .read(filterProvider.notifier)
                    .toggleMonth(month, months),
                selectedColor: Palette.accentSoft,
                checkmarkColor: Palette.accent,
              ),
          ],
        );
      },
    );
  }
}

/// 가격 구간을 **등간격으로 두지 않는다.**
///
/// 전세 2억과 아파트 매매 30억이 같은 축에 올라온다. 선형 슬라이더로 만들면
/// 전월세 전 구간이 손잡이 한 칸 안에 들어가 조절이 불가능하다. 사람이 실제로
/// 말하는 단위로 끊는다.
const List<int> _stops = [
  0,
  1000,
  3000,
  5000,
  10000,
  15000,
  20000,
  30000,
  50000,
  70000,
  100000,
  150000,
  200000,
  300000,
  500000,
];

class _PriceRange extends ConsumerWidget {
  const _PriceRange();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final low = _indexOf(filter.minAmount, fallback: 0);
    final high = _indexOf(filter.maxAmount, fallback: _stops.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_label(low, isMin: true)} ~ ${_label(high, isMin: false)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Palette.ink,
          ),
        ),
        RangeSlider(
          values: RangeValues(low.toDouble(), high.toDouble()),
          max: (_stops.length - 1).toDouble(),
          divisions: _stops.length - 1,
          activeColor: Palette.accent,
          onChanged: (values) {
            final lo = values.start.round();
            final hi = values.end.round();
            ref
                .read(filterProvider.notifier)
                .setAmountRange(
                  // 양 끝은 "제한 없음"이다. 0원 이상·500억 이하로 걸어 두면
                  // 값이 없는 거래(전월세의 amount 등)가 조용히 빠진다.
                  min: lo == 0 ? null : _stops[lo],
                  max: hi == _stops.length - 1 ? null : _stops[hi],
                );
          },
        ),
        const Text(
          '매매는 거래금액, 전월세는 보증금 기준입니다.',
          style: TextStyle(fontSize: 11.5, color: Palette.ink3),
        ),
      ],
    );
  }

  int _indexOf(int? amount, {required int fallback}) {
    if (amount == null) return fallback;
    final i = _stops.indexOf(amount);
    return i == -1 ? fallback : i;
  }

  String _label(int index, {required bool isMin}) {
    if (isMin && index == 0) return '제한 없음';
    if (!isMin && index == _stops.length - 1) return '제한 없음';
    return formatMoney(_stops[index]);
  }
}

class _Chips extends StatelessWidget {
  const _Chips({
    required this.labels,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  final Map<String, String> labels;
  final Set<String> selected;

  /// 지금 조합으로 존재하는 것. 없는 것은 눌러도 아무 일이 없으므로 못 누르게 한다.
  final Set<String> available;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in labels.entries)
        FilterChip(
          label: Text(entry.value),
          selected: selected.contains(entry.key),
          onSelected: available.contains(entry.key)
              ? (_) => onTap(entry.key)
              : null,
          selectedColor: Palette.accentSoft,
          checkmarkColor: Palette.accent,
        ),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      message,
      style: const TextStyle(fontSize: 13, color: Palette.ink3),
    ),
  );
}
