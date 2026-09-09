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

  /// 이 묶음이 법정동 근사인가. 하나라도 근사면 참이다 —
  /// [MapFeature.approximate]와 같은 규칙이라야 지도의 색과 설명이 어긋나지 않는다.
  bool get approximate =>
      rows.any((r) => r.precision == 'partial' || r.precision == 'umd');

  /// 머리말에 쓸 이름.
  ///
  /// 같은 지번에 모인 것이므로 **건물 이름이 곧 이 묶음의 이름**이다.
  /// 원천이 이름을 안 준 거래가 있어(단독·토지가 특히 그렇다) 없으면
  /// 법정동과 지번으로 떨어지고, 그것도 없으면 법정동만 쓴다.
  ///
  /// 근사 묶음은 건물이 여럿이라 이름을 쓸 수 없다. 법정동을 쓴다.
  String get title {
    if (approximate) return rows.first.umdNm;
    final named = rows.firstWhere(
      (r) => (r.name ?? '').isNotEmpty,
      orElse: () => rows.first,
    );
    final name = named.name ?? '';
    if (name.isNotEmpty) return name;
    final jibun = named.jibun ?? '';
    return jibun.isEmpty ? named.umdNm : '${named.umdNm} $jibun';
  }

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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Palette.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '거래 ${formatCount(rows.length)}건',
                // 15의 80%. 이름이 주인공이고 건수는 그 딸림이다.
                style: const TextStyle(fontSize: 12, color: Palette.ink3),
              ),
              // **근사 묶음에서만 한 줄을 더 붙인다.** 정확 좌표 묶음은 정말
              // 같은 건물이라 설명할 것이 없지만, 이쪽은 지번이 서로 다른데
              // 좌표를 못 만들어 동 중심에 모아 둔 것이다. 아무 말도 없으면
              // 이 자리에 있는 건물이라는 뜻이 되어 거짓이 된다.
              if (approximate) ...[
                const SizedBox(height: 5),
                const Text(
                  '실제 위치는 이 자리가 아니며, 서로 다른 곳일 수 있습니다',
                  style: TextStyle(fontSize: 11, color: Palette.warn),
                ),
              ],
            ],
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
      onTap: () => DetailSheet.show(context, tx, fromMap: true),
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
