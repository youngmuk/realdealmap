import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/features/about/about_sheet.dart';
import 'package:realdealmap/theme.dart';

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
  group('상시 고지', () {
    testWidgets('참고용이며 법적 효력이 없다고 늘 적혀 있다', (tester) async {
      await tester.pumpWidget(_wrap(const AboutBanner()));

      expect(find.text(AboutBanner.notice), findsOneWidget);
      expect(AboutBanner.notice, contains('참고용'));
      expect(AboutBanner.notice, contains('법적 효력'));
    });

    // 잘린 고지는 고지가 아니다.
    //
    // 상태바 안에 있을 때는 [kAboutBannerHeight]가 천장이었다. 화면 아래
    // 가운데로 옮긴 뒤로는 그 천장이 없지만, **한 줄을 넘지 않는 것**은 여전히
    // 지켜야 한다 — 두 줄이 되면 지도를 그만큼 더 가리고 탭 막대와 부딪힌다.
    //
    // 배율은 우리가 곱하는 2배 위에 사용자의 시스템 확대가 또 겹칠 수 있다.
    // 그 조합까지 견뎌야 한다.
    testWidgets('배율을 키워도 한 줄에 온전히 들어간다', (tester) async {
      // 화면 폭. 아래 가운데에 떠 있으므로 좌우 여백을 뺄 이유가 없다.
      const available = 393.0;

      for (final scale in [1.0, kTextScale, kTextScale * 1.3]) {
        await tester.pumpWidget(
          _wrap(const AboutBanner(), scale: scale, width: available),
        );
        await tester.pumpAndSettle();

        final painted = tester.renderObject<RenderParagraph>(
          find.text(AboutBanner.notice),
        );
        // maxLines가 1이므로, 못 들어가면 두 번째 줄이 생기는 대신 여기가
        // 참이 된다 — 즉 사용자는 뒷부분을 못 본다.
        expect(
          painted.didExceedMaxLines,
          isFalse,
          reason: '배율 $scale에서 고지가 잘렸다',
        );
        // 한 줄 + 위아래 여백. 천장이 아니라 **두 줄이 되지 않았다는 증거**로
        // 본다 — 두 줄이면 이 값이 대략 두 배가 된다.
        expect(
          tester.getSize(find.byType(AboutBanner)).height,
          lessThanOrEqualTo((kAboutBannerHeight + 4) * scale),
          reason: '배율 $scale에서 고지가 한 줄을 넘었다',
        );
        expect(
          tester.getSize(find.byType(AboutBanner)).width,
          lessThanOrEqualTo(available),
          reason: '배율 $scale에서 폭을 넘었다',
        );
      }
    });

    testWidgets('누르면 전문이 열린다', (tester) async {
      await tester.pumpWidget(_wrap(const AboutBanner()));

      await tester.tap(find.byType(AboutBanner));
      await tester.pumpAndSettle();

      expect(find.byType(AboutSheet), findsOneWidget);
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

    testWidgets('닫을 수 있다', (tester) async {
      await pump(tester);

      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}
