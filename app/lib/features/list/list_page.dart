import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../format.dart';
import '../../state/app_state.dart';
import '../../state/filters.dart';
import '../../theme.dart';
import '../detail/detail_sheet.dart';

/// 목록 탭 (T5.7 · FR-2).
///
/// **지도에 없는 거래가 여기에는 있다.** 단독·토지는 원천이 지번을 가려 지번
/// 좌표를 만들 수 없고, 그런 거래는 지도에서 법정동 중심점에 뭉치거나 아예
/// 빠진다. 목록이 그 차이를 메우는 자리다 — "지도 미표시 N건" 배지를 위에 둔다.
class ListPage extends ConsumerWidget {
  const ListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sggCd = ref.watch(selectedRegionProvider);
    if (sggCd == null) {
      return const _Empty('지역을 먼저 고르세요');
    }

    final filter = ref.watch(filterProvider);
    final db = ref.watch(databaseProvider);
    // 동기화가 끝나면 목록을 다시 읽는다.
    ref.watch(syncProvider);

    return FutureBuilder<(List<TxRow>, int)>(
      future: _load(db, sggCd, filter),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final (rows, unmapped) = data;
        if (rows.isEmpty) {
          return const _Empty('조건에 맞는 거래가 없습니다');
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: rows.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
          itemBuilder: (context, i) {
            if (i == 0) return _UnmappedBanner(count: unmapped);
            return _Tile(rows[i - 1]);
          },
        );
      },
    );
  }

  Future<(List<TxRow>, int)> _load(
    AppDatabase db,
    String sggCd,
    TxFilter filter,
  ) async => (
    await db.listTransactions(
      sggCd: sggCd,
      datasetKeys: filter.datasetKeysOrNull,
      includeCancelled: filter.includeCancelled,
      minAmount: filter.minAmount,
      maxAmount: filter.maxAmount,
      months: filter.months.isEmpty ? null : filter.months,
    ),
    await db.unmappedCount(sggCd),
  );
}

/// 지도에 못 그리는 건수.
///
/// 감추면 사용자는 데이터가 없는 것으로 오해한다. 실제로는 원천이 지번을 가려
/// 좌표를 만들 수 없었을 뿐이고, 목록에는 전부 있다.
class _UnmappedBanner extends StatelessWidget {
  const _UnmappedBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.warnSoft,
        borderRadius: BorderRadius.circular(6),
        border: const Border(left: BorderSide(color: Palette.warn, width: 3)),
      ),
      child: Text(
        '지도 미표시 $count건 — 원천이 지번을 공개하지 않아 좌표를 만들 수 없는 '
        '거래입니다. 목록에는 전부 있습니다.',
        style: const TextStyle(
          fontSize: 12.5,
          color: Palette.ink2,
          height: 1.45,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.tx);
  final TxRow tx;

  @override
  Widget build(BuildContext context) {
    final isRent = tx.datasetKey.endsWith('/rent');
    final price = isRent
        ? formatRent(tx.deposit, tx.monthlyRent)
        : formatMoney(tx.amount);
    final bits = <String>[
      if (tx.areaSqm != null) formatArea(tx.areaSqm),
      if (tx.floor != null) '${tx.floor}층',
      formatDate(tx.contractedOn),
    ];

    return InkWell(
      onTap: () => DetailSheet.show(context, tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 40,
              margin: const EdgeInsets.only(top: 3, right: 12),
              color: colorOfDataset(tx.datasetKey),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tx.name?.isNotEmpty == true ? tx.name! : tx.umdNm,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (tx.cancelled)
                        const Tag(
                          '해제',
                          color: Palette.danger,
                          background: Color(0xFFFCE7EC),
                        ),
                      // 지도에 없는 이유를 목록에서 바로 알 수 있어야 한다.
                      if (tx.lat == null)
                        const Tag(
                          '지도 미표시',
                          color: Palette.warn,
                          background: Palette.warnSoft,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${datasetLabel(tx.datasetKey)} · ${bits.join(' · ')}',
                    style: const TextStyle(fontSize: 12.5, color: Palette.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              price,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: tx.cancelled ? Palette.ink3 : Palette.ink,
                decoration: tx.cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      style: const TextStyle(color: Palette.ink3, fontSize: 14),
    ),
  );
}
