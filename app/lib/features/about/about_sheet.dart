import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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

        // Play 첫 심사가 "혼동을 야기하는 주장"으로 거부됐다(2026-09-11).
        // 정부 자료를 옮기는 앱은 정부기관이 아니라는 고지와 원본으로 가는
        // 링크를 사용자가 바로 볼 수 있어야 한다. 그래서 둘 다 맨 위로 올렸다.
        _Body(
          '이 앱은 국토교통부 등 정부기관이 만들거나 운영하는 앱이 아니며, '
          '기관과 아무 관계가 없습니다. 거래 정보의 원본은 아래 출처에서 '
          '직접 확인할 수 있습니다.',
          strong: true,
        ),

        SectionLabel('출처'),
        _Source('거래 정보 원본', '국토교통부 실거래가 공개시스템', url: 'https://rt.molit.go.kr'),
        _Source(
          '거래 정보 제공 (Open API)',
          '공공데이터포털 · 국토교통부 실거래가 자료',
          url: 'https://www.data.go.kr',
        ),
        _Source(
          '배경 지도',
          '© OpenStreetMap contributors',
          url: 'https://www.openstreetmap.org/copyright',
        ),
        _Source('주소와 좌표', '도로명주소 © 행정안전부', url: 'https://www.juso.go.kr'),
        // 상세창의 건물 외곽선이 이 자료다. 좌표와 같은 출처지만 받는 자료가
        // 달라(건물 도형) 따로 적는다 — 무엇을 보고 그린 것인지 화면에서
        // 알 수 있어야 한다.
        _Source(
          '건물 외곽선',
          '도로명주소 건물 도형 © 행정안전부',
          url: 'https://business.juso.go.kr',
        ),
        _Source('행정구역 코드', '행정안전부 행정표준코드관리시스템', url: 'https://www.code.go.kr'),
        // CC BY 4.0은 출처 표기가 조건이다. 지우면 라이선스 위반이라
        // 화면에서 뺄 수 없다. 같은 문구가 경계 파일 안에도 들어 있다.
        _Source(
          '시군구 경계',
          '통계청 SGIS 행정동 경계(공공누리 제1유형)를 vuski/admdongkor이 '
              '가공한 것 · CC BY 4.0',
        ),
        _Body(
          '자료의 내용에 대한 책임은 원천 기관에 있고, 옮기는 과정의 '
          '잘못은 우리에게 있습니다.',
        ),

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
          '지번을 알 수 있을 때만 그 자리에 찍습니다. 원천이 지번을 가린 경우에는 '
              '법정동 중심의 근사 좌표에 찍고 "근사"로 표시합니다. 좌표를 만들 수 없는 '
              '건은 지도에 없고 목록에만 있으며, 그 건수를 목록 위에 밝힙니다.',
        ),
        _Point(
          '값을 쓰기 전에',
          '시세 판단·계약·투자 결정의 근거로 삼기 전에 국토교통부 실거래가 '
              '공개시스템에서 원문을 확인하십시오.',
        ),

        SectionLabel('갱신'),
        _Body(
          '지역 자료는 1시간 주기로 새것이 있는지 확인합니다. 지금 보고 있는 '
          '지역의 기준 시각은 화면 위쪽에 늘 적어 둡니다. 인터넷이 없으면 '
          '저장된 자료를 보여주고 "오프라인"이라고 밝힙니다.',
        ),

        SectionLabel('개인정보'),
        _Point(
          '우리는 수집하지 않습니다',
          '계정을 만들지 않고, 이름·연락처·이메일을 받지 않습니다. '
              '우리 서버에 사용자를 구별해 저장하는 값이 없습니다.',
        ),
        // 광고 식별자를 빼놓고 "식별자를 보내지 않는다"고 적을 수는 없다.
        // 우리가 그 값을 읽지 않는 것과 앱이 수집하지 않는 것은 다른 말이고,
        // Play는 앱에 들어간 제3자 SDK의 수집을 앱의 수집으로 신고하게 한다.
        _Point(
          '광고는 광고 식별자를 씁니다',
          '앱에 구글 AdMob 광고가 들어 있고, 광고 식별자(AAID)를 구글이 수집합니다. '
              '앱은 그 값을 읽지도 보관하지도 않습니다. 기기 설정에서 재설정하거나 '
              '삭제할 수 있습니다. 위치는 광고에 쓰지 않습니다.',
        ),
        _Point(
          '위치는 기기 밖으로 나가지 않습니다',
          '위치 권한은 지금 있는 곳의 지도를 여는 데만 씁니다. 좌표를 서버에 '
              '보내 지역을 묻는 것이 아니라, 앱 안에 들어 있는 시군구 경계로 '
              '기기 안에서 풉니다.',
        ),
        _Point(
          '정밀 위치는 버튼을 누를 때만',
          '앱을 처음 열 때는 대략적인 위치만 씁니다. 지도의 현재 위치 버튼을 '
              '누른 때에만 정확한 위치를 묻습니다 — 대략적인 위치는 안드로이드가 '
              '1~2km 격자로 흐려서 옆 동네가 나오기 때문입니다.',
        ),
        _Point('권한을 주지 않아도 됩니다', '위치를 거부해도 모든 기능을 그대로 씁니다. 지역을 직접 고르면 됩니다.'),
        _Point(
          '기기에 저장하는 것',
          '마지막으로 본 지역과, 화면에 필요한 거래 자료와, 광고를 마지막으로 '
              '보여준 시각을 기기 안에 둡니다. 앱을 지우면 함께 사라집니다.',
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
  const _Source(this.label, this.name, {this.url});
  final String label;
  final String name;

  /// 원본으로 가는 주소. 있으면 이름 아래에 **주소 그대로** 보여준다 —
  /// "바로가기" 같은 말로 감추면 어디로 가는지 누르기 전에는 모른다.
  final String? url;

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
        if (url case final url?) _Link(url),
      ],
    ),
  );
}

/// 누르면 외부 브라우저로 여는 주소 한 줄.
class _Link extends StatelessWidget {
  const _Link(this.url);
  final String url;

  Future<void> _open(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on PlatformException {
      opened = false;
    } on Exception {
      // MissingPluginException 등 플랫폼 채널 쪽 실패도 여기서 받는다.
      // 어떤 이유든 못 열었으면 아래 대화상자로 주소를 보여 주는 게 할 일이다.
      opened = false;
    }
    if (opened || !context.mounted) return;
    // 스낵바는 이 시트 뒤의 화면에 떠서 시트에 가려진다. 대화상자로 알리고,
    // 주소를 옮겨 적을 수 있게 선택 가능한 글자로 둔다.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('브라우저를 열 수 없습니다'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    // container가 없으면 위의 라벨·기관 이름과 한 노드로 합쳐져서
    // 스크린 리더가 링크를 따로 짚지 못한다.
    container: true,
    link: true,
    label: '$url 열기',
    // excludeSemantics는 InkWell의 탭 동작까지 지운다. 여기서 다시 달지 않으면
    // TalkBack으로는 링크를 들을 수만 있고 열 수는 없다.
    excludeSemantics: true,
    onTap: () => _open(context),
    child: InkWell(
      onTap: () => _open(context),
      // 손가락이 닿을 높이(48dp)를 준다. 글자만큼만이면 누르기 어렵다.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Text(
            url,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Palette.slate,
              decoration: TextDecoration.underline,
              decorationColor: Palette.slate,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 참고용 고지 한 줄.
///
/// 이 문구가 G6의 "참고용 고지"다. 바꾸려면 그 조건을 다시 읽고 바꿔야 한다.
///
/// **전에는 머리말에 상시 노출하는 배너였다.** 그 한 줄이 지도 위쪽을 계속
/// 차지하면서도 사용자가 하루에 한 번도 누르지 않는 자리여서, 설정 화면과
/// 상세 화면 두 곳으로 옮겼다. G6가 요구하는 것은 "표시된다"이지 상시가 아니다.
///
/// 짧은 것은 게을러서가 아니다. 글자 배율 2배에서 한 줄에 들어가야 한다.
/// 온전한 문장은 [AboutSheet]에 있다.
const String kNotice = '참고용 · 법적 효력 없음';
