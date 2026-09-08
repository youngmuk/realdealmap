import 'package:flutter/material.dart';

import '../../theme.dart';

/// 출처 · 이 정보의 한계 · 개인정보 (T6.6 · G6).
///
/// **여기 적힌 것은 법적 고지가 아니라 사실 진술이다.** 실거래가는 신고 자료이고,
/// 신고에는 기한과 해제와 정정이 있다. 그것을 감추고 "실거래가"라고만 적으면
/// 사용자는 지금 시세로 읽는다. 우리가 아는 한계는 우리가 말해야 한다.
///
/// 상시 노출은 상태바가 맡는다 ([AboutBanner]). 이 화면은 그 한 줄의 전문이다.
class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const AboutSheet(),
  );

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.8,
    maxChildSize: 0.95,
    expand: false,
    builder: (context, scroll) => ListView(
      controller: scroll,
      // 글자 배율이 커지면 내용이 화면을 넘는다. 잘려서 안 보이는 고지는 고지가 아니다.
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: const [
        _Header(),

        SectionLabel('이 정보의 한계'),
        _Body(
          '이 앱은 국토교통부가 공개한 부동산 거래 신고 자료를 그대로 옮겨 보여줍니다. '
          '참고용이며 법적 효력이 없습니다.',
          strong: true,
        ),
        _Point(
          '신고 기한',
          '계약일로부터 30일 안에 신고하게 되어 있습니다. 그래서 최근 거래는 아직 '
              '올라오지 않았을 수 있습니다. 없는 것과 아직 안 올라온 것은 다릅니다.',
        ),
        _Point(
          '해제와 정정',
          '신고 뒤 해제되거나 정정되는 거래가 있습니다. 해제된 거래는 "해제"로 '
              '표시하지만, 원천에 반영되기 전까지는 우리도 알 수 없습니다.',
        ),
        _Point(
          '지도 위 위치',
          '원천이 지번을 일부 가리는 경우가 있습니다. 그럴 때는 법정동 중심의 '
              '근사 좌표에 찍고 "근사"로 표시합니다. 좌표를 만들 수 없는 건은 지도에 '
              '없고 목록에만 있으며, 그 건수를 목록 위에 밝힙니다.',
        ),
        _Point(
          '값을 쓰기 전에',
          '시세 판단·계약·투자 결정의 근거로 삼기 전에 국토교통부 실거래가 '
              '공개시스템에서 원문을 확인하십시오.',
        ),

        SectionLabel('출처'),
        _Source('거래 정보', '국토교통부 실거래가 공개시스템 (RTMS Open API)'),
        _Source('배경 지도', '© OpenStreetMap contributors'),
        _Source('행정구역 코드', '행정안전부 행정표준코드관리시스템'),
        _Body(
          '이 앱은 위 기관이 만들거나 운영하는 것이 아니며, 기관과 아무 관계가 '
          '없습니다. 자료의 내용에 대한 책임은 원천 기관에 있고, 옮기는 과정의 '
          '잘못은 우리에게 있습니다.',
        ),

        SectionLabel('갱신'),
        _Body(
          '지역 자료는 1시간 주기로 새것이 있는지 확인합니다. 지금 보고 있는 '
          '지역의 기준 시각은 화면 위쪽에 늘 적어 둡니다. 인터넷이 없으면 '
          '저장된 자료를 보여주고 "오프라인"이라고 밝힙니다.',
        ),

        SectionLabel('개인정보'),
        _Point(
          '수집하지 않습니다',
          '계정을 만들지 않고, 개인을 식별할 수 있는 정보를 모으지 않습니다. '
              '이름·연락처·기기 식별자를 받지도 보내지도 않습니다.',
        ),
        _Point(
          '위치는 기기 밖으로 나가지 않습니다',
          '위치 권한은 처음 열 지역(시군구)을 고르는 데만 씁니다. 좌표를 서버에 '
              '보내 지역을 묻는 것이 아니라, 이미 내려받아 둔 지역 목록에서 '
              '기기 안에서 고릅니다. 그래서 정밀 위치도 필요 없습니다.',
        ),
        _Point('권한을 주지 않아도 됩니다', '위치를 거부해도 모든 기능을 그대로 씁니다. 지역을 직접 고르면 됩니다.'),
        _Point(
          '기기에 저장하는 것',
          '마지막으로 본 지역과, 화면에 필요한 거래 자료를 기기 안에 둡니다. '
              '앱을 지우면 함께 사라집니다.',
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('정보와 출처', style: Theme.of(context).textTheme.labelSmall),
      const Spacer(),
      IconButton(
        tooltip: '닫기',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.close, size: 20),
      ),
    ],
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.5,
        color: strong ? Palette.ink : Palette.ink2,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point(this.title, this.text);
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Palette.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: Palette.ink2,
          ),
        ),
      ],
    ),
  );
}

class _Source extends StatelessWidget {
  const _Source(this.label, this.name);
  final String label;
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    // 라벨과 값을 나란히 두지 않는다. 글자 배율 2배에서는 라벨 칸이 아무리
    // 넉넉해도 "거래 정보"가 두 줄로 접히거나 값과 맞붙는다. 위아래로 두면
    // 배율이 얼마든 무너지지 않는다.
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Palette.ink3)),
        const SizedBox(height: 2),
        Text(
          name,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: Palette.ink,
          ),
        ),
      ],
    ),
  );
}

/// 상태바가 [AboutBanner]에 내주는 높이 (글자 배율을 곱하기 전).
///
/// `app.dart`의 상태바 높이가 이 값을 더해 잡는다. 여기를 늘리면 저기도 늘어난다 —
/// 한쪽만 바꾸면 고지가 상태바 밖으로 밀려 잘린다.
const double kAboutBannerHeight = 18;

/// 상시 노출되는 한 줄 (G6).
///
/// 기준 시각 줄에 이어 붙이지 않고 **따로 둔다**. 이어 붙이면 지역 이름이나
/// 오프라인 경고가 길 때 뒤가 잘리는데, 잘린 고지는 고지가 아니다.
class AboutBanner extends StatelessWidget {
  const AboutBanner({super.key});

  /// 이 문구가 G6의 "참고용 고지"다. 바꾸려면 그 조건을 다시 읽고 바꿔야 한다.
  ///
  /// 짧은 것은 게을러서가 아니다. 글자 배율 2배에서 한 줄에 들어가야 하고,
  /// 넘쳐서 줄바꿈되면 상태바 높이를 넘어 잘린다 — 잘린 고지는 고지가 아니다.
  /// 온전한 문장은 [AboutSheet]에 있고, 이 줄을 누르면 거기로 간다.
  static const String notice = '참고용 · 법적 효력 없음';

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => AboutSheet.show(context),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      // 줄바꿈 대신 **줄어들게** 한다.
      //
      // 우리 배율 2배 위에 사용자의 시스템 확대까지 겹치면 이 줄은 폭을 넘는다.
      // 그때 넘치면 두 줄이 되고, 상태바 높이는 한 줄을 전제로 잡혀 있어 아랫줄이
      // 잘린다. 잘린 고지는 고지가 아니다. 조금 작아지는 쪽이 낫고, 그래도
      // 시스템 기본 크기보다는 훨씬 크다.
      //
      // '출처' 같은 낱말을 덧붙이지 않는 것도 같은 이유다. 밑줄과 아이콘만으로
      // 누를 수 있다는 것은 전해진다.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              notice,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10.5,
                color: Palette.slate,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ).copyWith(decorationColor: Palette.slate),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.info_outline, size: 11, color: Palette.slate),
          ],
        ),
      ),
    ),
  );
}
