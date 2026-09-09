import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../theme.dart';
import '../about/about_sheet.dart';
import '../map/map_focus.dart';
import 'detail_model.dart';

/// 상세 정보 시트 (T5.6 · FR-3).
///
/// 위에서부터 **도면 → 요약 → 표**(`Doc/상세정보명세.html`).
/// 도면 자리는 아직 비어 있다 — 국토부 실거래가 API에 도면이 없어서 건축HUB를
/// 따로 붙여야 하는데 커버리지와 이용조건을 확인하지 못했다(D-1~D-4).
/// 그래서 **도면이 없으면 그 블록 자체가 없다.** 빈 상자를 남기면 "불러오지 못했다"로
/// 읽히고, 나중에 도면이 붙어도 화면이 흔들리지 않는다.
class DetailSheet extends StatelessWidget {
  const DetailSheet({required this.tx, this.fromMap = false, super.key});

  final TxRow tx;

  /// 지도에서 열렸는가. 그러면 "지도에서 보기"를 감춘다.
  final bool fromMap;

  /// [fromMap]이면 "지도에서 보기"를 감춘다.
  ///
  /// 지도에서 마커를 눌러 연 상세다 — 이미 그 자리를 보고 있는데 같은 곳으로
  /// 데려가겠다고 말하는 것은 아무 일도 안 하겠다는 뜻이다. 목록에서 연
  /// 상세에서는 여전히 필요하다.
  static Future<void> show(
    BuildContext context,
    TxRow tx, {
    bool fromMap = false,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      // 앱 전체 배율에 곱한다. 사용자가 시스템 글자 크기를 올려 두었다면
      // 그 비율은 그대로 살아 있고, 상세만 한 단계 작아진다.
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          textScaler: TextScaler.linear(
            media.textScaler.scale(1) * kDetailTextScale,
          ),
        ),
        child: DetailSheet(tx: tx, fromMap: fromMap),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final detail = buildDetail(tx);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          const _Grip(),
          _Header(detail.header),
          // 도면 블록 자리 (D-1~D-4).
          //
          // 도면 자체는 국토부 실거래가에 없어서 건축HUB가 필요하고(D-1~D-3),
          // 그것은 별도 활용신청이 선행이다. 명세의 D-4는 "도면이 없을 때 그
          // 자리를 지도로 대체할지"를 물었고, **지도로 데려가는 쪽을 골랐다.**
          //
          // 여기에 지도 그림을 붙이려면 타일을 받아야 하는데, 우리 배경지도는
          // 벡터(PMTiles)라 이미지로 못 붙이고, 렌더러를 하나 더 띄우면 그래픽
          // 메모리가 두 배가 된다(지도 하나가 139 MB · 실측). 예전에는 OSM 타일을
          // 직접 받아 붙였는데 **OSM 이용정책이 배포 앱의 트래픽을 허용하지 않는다.**
          //
          // **좌표가 없으면 이 줄 자체가 없다.** 못 가는 곳으로 데려가겠다고
          // 말하지 않는다. 원천이 지번을 안 준 거래가 그렇다.
          if (!fromMap && tx.lat != null && tx.lng != null)
            _ShowOnMap(
              lat: tx.lat!,
              lng: tx.lng!,
              approximate: detail.header.approximate,
            ),
          for (final section in detail.sections) ...[
            SectionLabel(section.title),
            _Table(section.rows),
          ],
          if (detail.raw.isNotEmpty) _RawBlock(detail.raw),
          // 참고용 고지 (G6).
          //
          // **금액을 실제로 읽는 자리가 여기다.** 머리말에 상시 노출하던 것을
          // 걷으면서, 감추는 대신 뜻이 있는 자리로 옮겼다 — 숫자를 본 사람이
          // 그 숫자를 어떻게 받아들여야 하는지 같은 화면에서 읽는다.
          const _Notice(),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Center(
      child: InkWell(
        onTap: () => AboutSheet.show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kNotice,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Palette.slate,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.info_outline, size: 11, color: Palette.slate),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Palette.rule,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.header);
  final DetailHeader header;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(header.datasetLabel, style: text.labelSmall),
            const Spacer(),
            if (header.cancelled)
              const Tag(
                '해제된 거래',
                color: Palette.danger,
                background: Color(0xFFFCE7EC),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(header.title, style: text.titleMedium),
        Text(
          header.address,
          style: text.bodyMedium?.copyWith(color: Palette.ink3),
        ),
        const SizedBox(height: 14),
        // 실거래가는 값이 주인공이다. 화면에서 가장 큰 글자가 금액이어야 한다.
        Text(
          header.price,
          style: text.headlineMedium?.copyWith(
            color: header.cancelled ? Palette.ink3 : Palette.ink,
            decoration: header.cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
        if (header.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            header.summary,
            style: text.bodyMedium?.copyWith(color: Palette.ink2),
          ),
        ],
        if (header.approximate) ...[
          const SizedBox(height: 12),
          const _ApproximateNotice(),
        ],
      ],
    );
  }
}

/// 근사 좌표 안내.
///
/// 감추면 사용자는 지도의 핀을 그 건물이라고 믿는다. 실측 오차가 226~582 m다.
class _ApproximateNotice extends StatelessWidget {
  const _ApproximateNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Palette.warnSoft,
      borderRadius: BorderRadius.circular(6),
      border: const Border(left: BorderSide(color: Palette.warn, width: 3)),
    ),
    child: const Text(
      '원천이 지번을 공개하지 않아 지도 위치는 법정동 중심점입니다. '
      '실제 위치와 다를 수 있습니다.',
      style: TextStyle(fontSize: 12.5, color: Palette.ink2, height: 1.45),
    ),
  );
}

class _Table extends StatelessWidget {
  const _Table(this.rows);
  final List<DetailRow> rows;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Palette.rule),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i += 1)
          _Row(rows[i], last: i == rows.length - 1),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.row, {required this.last});
  final DetailRow row;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: Palette.rule)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 라벨 열을 픽셀로 고정하지 않는다. 글자 배율이 올라가면 고정 폭이
        // 화면의 절반을 먹어 값이 두 줄로 접힌다. 비율로 나누면 어떤 배율에서도
        // 라벨과 값의 균형이 유지된다.
        Expanded(
          flex: 4,
          child: Text(
            row.label,
            style: const TextStyle(fontSize: 13, color: Palette.ink3),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            row.value,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: row.emphasis ? FontWeight.w700 : FontWeight.w500,
              color: row.emphasis ? Palette.accent : Palette.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 표에 자리를 못 잡은 원문.
///
/// 접어 두되 반드시 넣는다. 우리가 이름을 붙이지 못한 항목도 사용자에게
/// 도달해야 한다 — 원천이 준 것을 앱이 삼키면 그 정보는 없는 것이 된다(FR-3).
class _RawBlock extends StatelessWidget {
  const _RawBlock(this.raw);
  final Map<String, String> raw;

  @override
  Widget build(BuildContext context) {
    final keys = raw.keys.toList()..sort();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '원문 전체 (${raw.length}개 항목)',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        children: [
          _Table([for (final key in keys) DetailRow(key, raw[key]!)]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// "지도에서 보기". 상세창을 닫고 지도 탭을 그 좌표로 보낸다.
///
/// 근사 좌표면 그렇다고 미리 말한다. 누르고 나서 핀이 엉뚱한 데 있으면
/// 사용자는 지도가 틀렸다고 읽는다 — 틀린 것은 지도가 아니라 원천의 지번이다.
class _ShowOnMap extends ConsumerWidget {
  const _ShowOnMap({
    required this.lat,
    required this.lng,
    required this.approximate,
  });

  final double lat;
  final double lng;
  final bool approximate;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              ref.read(mapFocusProvider.notifier).request(lat, lng);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.place_outlined, size: 18),
            label: const Text('지도에서 보기'),
            style: OutlinedButton.styleFrom(
              // 글자 배율이 2배인 앱이다. 높이를 고정하면 글자가 잘린다.
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (approximate)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '지번을 몰라 법정동 근처로만 찍습니다',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    ),
  );
}
