import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:realdealmap/features/about/about_sheet.dart';
import 'package:realdealmap/theme.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// 실제로 브라우저를 열지 않고 "무엇을, 어떻게 열라고 했는가"만 받아 적는다.
class _FakeLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  _FakeLauncher({this.result = true});
  final bool result;
  final launched = <String>[];
  final modes = <PreferredLaunchMode>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    modes.add(options.mode);
    return result;
  }
}

/// 출처·면책·개인정보 고지 (T6.6 · G6).
///
/// 여기서 지키는 것은 **말이 도달하는가**다. 문구를 파일에 적어 두는 것과
/// 화면에 온전히 보이는 것은 다르다. 특히 글자 배율 2배가 기본인 이 앱에서는
/// 고지가 잘려 "참고용 ·"까지만 남는 실패가 실제로 가능하다.
Widget _wrap(Widget child, {double scale = kTextScale, double width = 393}) =>
    MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );

void main() {
  group('참고용 고지', () {
    // 위젯이 아니라 **문구**를 지킨다. 배너는 사라졌지만(설정과 상세로 옮겼다)
    // G6가 요구하는 것은 이 문장이 표시되는 것이다.
    test('참고용이며 법적 효력이 없다고 말한다', () {
      expect(kNotice, contains('참고용'));
      expect(kNotice, contains('법적 효력'));
    });
  });

  group('전문', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const AboutSheet(), width: 1080));
      await tester.pumpAndSettle();
    }

    /// 화면 밖의 고지까지 확인한다.
    ///
    /// 전문은 `ListView`라 보이지 않는 항목은 **아예 만들어지지도 않는다.**
    /// 그냥 `find`로 찾으면 "고지가 없다"와 "아래에 있다"가 구별되지 않는다 —
    /// 실제로 출처 한 줄을 늘렸더니 아래쪽 고지 검사가 통째로 실패했다.
    /// 사용자는 스크롤할 수 있으므로 여기서도 스크롤해서 찾는다.
    ///
    /// [target]은 **정확히 하나**에 맞아야 한다. `.first`를 붙이면 아직 안 만들어진
    /// 항목에서 빈 결과에 `first`를 부르다 던진다 — 이 함수의 목적이 사라진다.
    Future<void> seek(WidgetTester tester, Finder target) =>
        tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).first,
        );

    // 남의 자료를 옮겨 쓰는 앱이 출처를 감추면 그것은 자기 자료인 척하는 것이다.
    // 배경지도(OSM)는 ODbL상 출처 표기가 의무이기도 하다.
    testWidgets('원천 기관을 밝힌다', (tester) async {
      await pump(tester);

      expect(find.textContaining('국토교통부 실거래가 공개시스템'), findsWidgets);
      expect(find.textContaining('OpenStreetMap'), findsWidgets);
      // 좌표는 도로명주소에서 온다. 출처 표기가 제1유형의 유일한 의무다.
      expect(find.textContaining('도로명주소'), findsWidgets);
    });

    testWidgets('우리가 그 기관이 아님을 밝힌다', (tester) async {
      await pump(tester);

      expect(find.textContaining('기관과 아무 관계가'), findsOneWidget);
    });

    // 신고 기한·해제·근사 좌표는 사용자가 값을 오해하는 세 가지 경로다.
    // 셋 다 우리가 아는 사실이므로 우리가 말해야 한다.
    testWidgets('자료의 한계를 세 가지로 나눠 말한다', (tester) async {
      await pump(tester);

      expect(find.text('신고 기한'), findsOneWidget);
      expect(find.text('해제와 정정'), findsOneWidget);
      expect(find.text('지도 위 위치'), findsOneWidget);
    });

    testWidgets('법적 효력이 없다고 전문에서도 말한다', (tester) async {
      await pump(tester);

      expect(find.textContaining('법적 효력이 없습니다'), findsOneWidget);
    });

    // 위치 권한을 받는 앱이 "무엇에 쓰는지"를 스토어 설명에만 적으면
    // 사용자는 앱 안에서 확인할 길이 없다.
    testWidgets('위치가 기기 밖으로 나가지 않음을 밝힌다', (tester) async {
      await pump(tester);

      await seek(tester, find.text('위치는 기기 밖으로 나가지 않습니다'));
      expect(find.text('위치는 기기 밖으로 나가지 않습니다'), findsOneWidget);

      await seek(tester, find.text('권한을 주지 않아도 됩니다'));
      expect(find.textContaining('권한을 주지 않아도'), findsWidgets);
    });

    // 여기가 조용히 되돌아가기 쉬운 자리다. 광고 SDK를 붙이기 전에는
    // "기기 식별자를 받지도 보내지도 않습니다"가 사실이었고, 붙인 뒤에도
    // 그 문장이 그대로 남아 있었다. 앱과 방침이 어긋나면 Play 심사에서
    // 데이터 보안 양식과 대조된다 — 그것은 실수가 아니라 허위 신고가 된다.
    testWidgets('광고가 광고 식별자를 쓴다는 것을 밝힌다', (tester) async {
      await pump(tester);

      await seek(tester, find.text('광고는 광고 식별자를 씁니다'));
      expect(find.textContaining('광고 식별자'), findsWidgets);
      expect(find.textContaining('AdMob'), findsWidgets);
      // 우리가 안 모은다는 말이 "아무도 안 모은다"로 읽히면 안 된다.
      expect(find.textContaining('기기 식별자를 받지도'), findsNothing);
    });

    // Play가 첫 심사를 "혼동을 야기하는 주장"으로 거부했다(2026-09-11).
    // 정부 자료를 쓰는 앱은 원본 출처로 가는 **누를 수 있는 링크**와
    // "정부기관이 아니다"라는 고지를 앱 안에 둬야 한다. 기관 이름만 적은
    // 것으로는 부족했다. 고지는 스크롤하지 않아도 보이는 자리에 둔다.
    testWidgets('정부기관이 아니라는 고지가 맨 위에 있다', (tester) async {
      await pump(tester);

      expect(find.textContaining('정부기관이 만들거나 운영하는 앱이 아니며'), findsOneWidget);
    });

    testWidgets('원본 출처의 주소를 보여준다', (tester) async {
      await pump(tester);

      await seek(tester, find.text('https://rt.molit.go.kr'));
      expect(find.text('https://rt.molit.go.kr'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('rt.molit.go.kr')), findsWidgets);
    });

    testWidgets('원본 출처를 누르면 외부 브라우저로 연다', (tester) async {
      final launcher = _FakeLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      await pump(tester);

      await seek(tester, find.text('https://rt.molit.go.kr'));
      await tester.tap(find.text('https://rt.molit.go.kr'));
      await tester.pumpAndSettle();

      expect(launcher.launched, ['https://rt.molit.go.kr']);
      expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
    });

    testWidgets('열 수 없으면 조용히 넘기지 않고 알린다', (tester) async {
      final launcher = _FakeLauncher(result: false);
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      await pump(tester);

      await seek(tester, find.text('https://rt.molit.go.kr'));
      await tester.tap(find.text('https://rt.molit.go.kr'));
      await tester.pump();

      expect(find.textContaining('열 수 없습니다'), findsOneWidget);
    });

    // 심사자가 휴대폰에서 시트를 열었을 때 스크롤하지 않아도 원본 링크가
    // 보여야 "분명한 링크"다. 393×852, 글자 배율 기본값(2배)으로 본다.
    testWidgets('휴대폰 크기에서도 원본 링크가 스크롤 없이 보인다', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => AboutSheet.show(context),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      final link = find.text('https://rt.molit.go.kr');
      expect(link, findsOneWidget);
      final rect = tester.getRect(link);
      expect(rect.bottom, lessThanOrEqualTo(852));
      expect(rect.top, greaterThanOrEqualTo(0));
    });

    // 링크는 들리기만 해서는 안 되고 **열려야** 한다. excludeSemantics가
    // InkWell의 탭 동작을 지워 TalkBack으로는 열 수 없던 적이 있다.
    testWidgets('스크린 리더에서도 링크로 읽히고 누를 수 있다', (tester) async {
      final launcher = _FakeLauncher();
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      await pump(tester);

      final node = find.bySemanticsLabel('https://rt.molit.go.kr 열기');
      await seek(tester, node);
      expect(
        tester.getSemantics(node),
        matchesSemantics(
          label: 'https://rt.molit.go.kr 열기',
          isLink: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSize(find.text('https://rt.molit.go.kr')).height,
        lessThan(48),
      );
      expect(tester.getSize(node).height, greaterThanOrEqualTo(48));

      tester.semantics.tap(find.semantics.byLabel('https://rt.molit.go.kr 열기'));
      await tester.pumpAndSettle();
      expect(launcher.launched, ['https://rt.molit.go.kr']);
    });

    testWidgets('닫을 수 있다', (tester) async {
      await pump(tester);

      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}
