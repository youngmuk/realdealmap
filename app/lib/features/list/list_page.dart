import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../format.dart';
import '../../state/ads.dart';
import '../../state/app_state.dart';
import '../../state/filters.dart';
import '../../theme.dart';
import '../ads/ad_policy.dart';
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
    // 데이터가 실제로 바뀌었을 때만 다시 읽는다.
    //
    // 상태 전체를 보면 "도는 중"이 켜지고 꺼질 때마다 여기가 다시 그려지고,
    // 아래 FutureBuilder가 매번 질의를 새로 걸어 스피너가 번쩍인다.
    ref.watch(syncProvider.select((s) => s.revision));

    return FutureBuilder<_ListData>(
      future: _load(db, sggCd, filter),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final missing = missingLabels(filter, data.covered);
        if (data.rows.isEmpty) {
          // 아직 못 받은 유형만 고른 채로 "거래가 없습니다"라고 하면, 사용자는
          // 이 지역에 그런 거래가 없다고 읽는다. 실제로는 우리가 못 받은 것이다.
          return _Empty(
            missing.isEmpty
                ? '조건에 맞는 거래가 없습니다'
                : '${missing.join(' · ')} 자료를 아직 받지 못했습니다',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: data.rows.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MissingBanner(labels: missing),
                  _UnmappedBanner(count: data.unmapped),
                ],
              );
            }
            return _Tile(
              data.rows[i - 1],
              // 상세를 닫은 직후가 안전 전환 지점이다 (FR-6). ref는 여기에만
              // 있으므로 타일이 아니라 목록이 알린다.
              onClosed: () => ref.adMoment(AdMoment.detailClosed),
            );
          },
        );
      },
    );
  }

  Future<_ListData> _load(
    AppDatabase db,
    String sggCd,
    TxFilter filter,
  ) async => _ListData(
    rows: await db.listTransactions(
      sggCd: sggCd,
      datasetKeys: filter.datasetKeysOrNull,
      includeCancelled: filter.includeCancelled,
      minAmount: filter.minAmount,
      maxAmount: filter.maxAmount,
      months: filter.months.isEmpty ? null : filter.months,
    ),
    unmapped: await db.unmappedCount(sggCd),
    covered: await db.coveredDatasetKeys(sggCd),
  );
}

class _ListData {
  const _ListData({
    required this.rows,
    required this.unmapped,
    required this.covered,
  });
  final List<TxRow> rows;
  final int unmapped;

  /// 이 지역에서 실제로 받아 본 자료 유형
  final Set<String> covered;
}

/// 지금 보고 있는 조건 중 **아직 받지 못한** 매물 유형의 이름.
///
/// 한 유형의 일일 쿼터가 바닥나면 수집이 그 유형만 빼고 배포한다. 그 상태를
/// 말하지 않으면 "받았는데 0건"과 구별되지 않고, 사용자는 이 지역에 그런 거래가
/// 없다고 읽는다. 조건에 걸린 유형만 말한다 — 안 보고 있는 유형까지 알릴 일은 아니다.
List<String> missingLabels(TxFilter filter, Set<String> covered) {
  // 하나도 못 받은 상태는 "이 유형이 빠졌다"가 아니라 "아직 아무것도 안 받았다"다.
  // 그때까지 유형을 세면 첫 동기화 전에 다섯 유형을 늘어놓게 되고, 그건 안내가
  // 아니라 소음이다. 무엇이 빠졌는지는 뭔가 받아 본 뒤에야 말할 수 있다.
  if (covered.isEmpty) return const [];

  final asked = filter.datasetKeys.isEmpty ? kDatasetKeys : filter.datasetKeys;
  final types = <String>{};
  for (final key in asked) {
    if (covered.contains(key)) continue;
    types.add(kPropertyLabels[key.split('/').first] ?? key);
  }
  // kPropertyLabels의 순서를 따른다. Set 순서를 그대로 쓰면 실행마다 달라 보인다.
  return kPropertyLabels.values.where(types.contains).toList();
}

/// 아직 못 받은 유형을 밝힌다.
class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.warnSoft,
        borderRadius: BorderRadius.circular(6),
        border: const Border(left: BorderSide(color: Palette.warn, width: 3)),
      ),
      child: Text(
        '${labels.join(' · ')} 자료를 아직 받지 못했습니다 — 원천의 일일 한도 때문이며, '
        '다음 갱신에서 채워집니다. 없는 것이 아니라 아직 안 온 것입니다.',
        style: const TextStyle(
          fontSize: 12.5,
          color: Palette.ink2,
          height: 1.45,
        ),
      ),
    );
  }
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
        '지도 미표시 ${formatCount(count)}건 — 원천이 지번을 공개하지 않아 좌표를 만들 수 없는 '
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
  const _Tile(this.tx, {required this.onClosed});
  final TxRow tx;
  final VoidCallback onClosed;

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
      onTap: () async {
        await DetailSheet.show(context, tx);
        onClosed();
      },
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
              // 이름 · 가격 · 부가정보를 **세로로** 쌓는다.
              //
              // 가격을 오른쪽에 두면 글자 배율 2배에서 "2억 5,000만원 / 145만원"이
              // 폭의 대부분을 가져가고, 남은 자리에서 부가정보가 한 글자씩
              // 세로로 접힌다. 좌우 배치는 작은 글자를 전제로만 성립한다.
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
                  const SizedBox(height: 3),
                  // 실거래가는 값이 주인공이다. 줄을 통째로 내준다.
                  Text(
                    price,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: tx.cancelled ? Palette.ink3 : Palette.ink,
                      decoration: tx.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${datasetLabel(tx.datasetKey)} · ${bits.join(' · ')}',
                    style: const TextStyle(fontSize: 12.5, color: Palette.ink3),
                  ),
                ],
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
