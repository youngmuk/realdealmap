/// 한 자리에 겹친 거래들 (T5.4).
///
/// **왜 필요한가.** 좌표 사전은 `법정동|지번 → 한 점`이라, 한 아파트 단지의
/// 거래는 전부 같은 좌표를 갖는다. 실제 데이터로 재 보니 동대문구 아파트
/// 전월세 939건이 좌표 155개에 앉아 있었고 한 점에 132건이 겹친 곳도 있었다 —
/// 정확좌표 거래의 94%가 누군가와 자리를 나눠 쓴다.
///
/// 그 묶음은 **확대해도 갈라지지 않는다.** 파고들기만 있으면 사용자는 눌러도
/// 같은 것이 다시 나오는 것을 보고 앱이 반응하지 않는다고 읽는다. 여기로 온다.
library;

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../format.dart';
import '../../theme.dart';
import '../detail/detail_sheet.dart';

class StackSheet extends StatelessWidget {
  const StackSheet(this.rows, {super.key});

  final List<TxRow> rows;

  static Future<void> show(BuildContext context, List<TxRow> rows) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Palette.paper,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => StackSheet(rows),
      );

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.6,
    maxChildSize: 0.92,
    expand: false,
    builder: (context, controller) => Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Palette.rule,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '이 자리의 거래 ${formatCount(rows.length)}건',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Palette.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 같은 지번이라 주소로는 갈리지 않는다. 무엇으로 고르는지 말해 준다.
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '같은 지번이라 지도에서 한 점으로 겹칩니다',
              style: TextStyle(fontSize: 11.5, color: Palette.ink3),
            ),
          ),
        ),
        const Divider(height: 1, color: Palette.rule),
        Expanded(
          child: ListView.separated(
            controller: controller,
            itemCount: rows.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 16, color: Palette.rule),
            itemBuilder: (context, i) => _Row(rows[i]),
          ),
        ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.tx);

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
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    price,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Palette.ink,
                      // 해제된 거래는 목록에서도 취소선을 긋는다. 여기서만
                      // 멀쩡해 보이면 상세를 열기 전까지 알 수 없다.
                      decoration: tx.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bits.join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: Palette.ink3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Palette.ink3),
          ],
        ),
      ),
    );
  }
}
