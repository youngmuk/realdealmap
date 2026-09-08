import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/app.dart';
import 'package:realdealmap/config.dart';
import 'package:realdealmap/state/app_state.dart';

/// 실행 설정 — 무엇으로 그리고, 어디서 받는가.
///
/// 뒤쪽 '빠진 설정' 묶음은 실제로 당한 뒤에 생겼다. `--dart-define`을 빠뜨린
/// 릴리스 APK는 **멀쩡히 실행됐다** — 지도는 OSM 폴백으로 그려지고 데이터만
/// 비어서 "아직 안 받았나 보다"처럼 보였다. 지역 목록을 열어 보고서야 알았다.
/// 스토어에 올린 뒤에 알았다면 되돌리는 비용이 전혀 달랐다.
AppConfig config({String style = ''}) =>
    AppConfig(dataBaseUrl: '', workerBaseUrl: '', mapStyle: style);

void main() {
  const good = AppConfig(
    dataBaseUrl: 'https://example.invalid',
    workerBaseUrl: 'https://worker.invalid',
    mapStyle: '{}',
  );

  group('지도 스타일 선택', () {
    test('직접 준 스타일이 가장 세다', () {
      expect(config(style: '{}').resolvedMapStyle, '{}');
    });

    // OSM 타일 서버의 이용 정책은 앱 트래픽을 허용하지 않는다. 개발용 폴백이다.
    test('스타일이 없으면 OSM으로 떨어진다', () {
      expect(config().resolvedMapStyle, contains('tile.openstreetmap.org'));
    });
  });

  group('OSM 폴백 스타일', () {
    final style = jsonDecode(kDefaultMapStyle) as Map<String, dynamic>;
    final tiles = ((style['sources'] as Map)['osm'] as Map)['tiles'] as List;

    test('스타일이 올바른 JSON이다', () {
      expect(style['version'], 8);
      expect(style['layers'], hasLength(1));
    });

    // 순서를 바꾸면 지도가 나오긴 하는데 위치가 틀린다. "안 나온다"보다 알아채기 어렵다.
    test('타일 경로가 z/x/y 순서다', () {
      expect(tiles.single, endsWith('/{z}/{x}/{y}.png'));
    });

    // ODbL은 출처 표기를 요구한다.
    test('출처를 밝힌다', () {
      expect(
        ((style['sources'] as Map)['osm'] as Map)['attribution'],
        contains('OpenStreetMap'),
      );
    });
  });

  group('빠진 설정', () {
    test('전부 있으면 출시 가능하다', () {
      expect(good.issues, isEmpty);
      expect(good.isReleasable, isTrue);
    });

    test('데이터 주소가 없으면 잡아낸다', () {
      const c = AppConfig(
        dataBaseUrl: '',
        workerBaseUrl: 'https://worker.invalid',
        mapStyle: '',
      );

      expect(c.issues, contains(ConfigIssue.noData));
      expect(c.isReleasable, isFalse);
    });

    // 기능은 멀쩡해 보이지만 남의 서버를 이용정책 밖으로 쓰는 상태다.
    // 화면만 봐서는 절대 드러나지 않는다.
    test('MAP_STYLE이 없으면 OSM 폴백임을 잡아낸다', () {
      const c = AppConfig(
        dataBaseUrl: 'https://example.invalid',
        workerBaseUrl: 'https://worker.invalid',
        mapStyle: '',
      );

      expect(c.issues, contains(ConfigIssue.fallbackTiles));
      expect(c.resolvedMapStyle, contains('openstreetmap.org'));
    });

    test('스타일을 주면 폴백이 아니다', () {
      const c = AppConfig(
        dataBaseUrl: 'https://example.invalid',
        workerBaseUrl: 'https://worker.invalid',
        mapStyle: '{"version":8}',
      );

      expect(c.issues, isEmpty);
    });

    test('사유마다 무엇을 빠뜨렸는지 이름을 댄다', () {
      // 경고를 보고 무엇을 고쳐야 할지 모르면 경고가 아니라 잡음이다.
      expect(ConfigIssue.noData.message, contains('DATA_BASE_URL'));
      expect(ConfigIssue.fallbackTiles.message, contains('MAP_STYLE'));
    });
  });

  group('경고 줄', () {
    Future<Size> pumpWarning(WidgetTester tester, AppConfig config) async {
      tester.view.physicalSize = const Size(1080, 400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [configProvider.overrideWithValue(config)],
          child: const MaterialApp(
            home: Scaffold(body: Align(child: ConfigWarning())),
          ),
        ),
      );
      await tester.pump();

      final found = find.byType(ConfigWarning);
      return tester.getSize(found);
    }

    testWidgets('멀쩡한 빌드에서는 아무것도 그리지 않는다', (tester) async {
      final size = await pumpWarning(tester, good);

      expect(size.height, 0);
    });

    testWidgets('빠진 것이 있으면 그것을 적어 보인다', (tester) async {
      await pumpWarning(
        tester,
        const AppConfig(dataBaseUrl: '', workerBaseUrl: '', mapStyle: ''),
      );

      // 사유마다 한 줄이다. 뭉뚱그리면 무엇을 고쳐야 하는지 하나만 읽힌다
      expect(find.textContaining('출시 불가'), findsNWidgets(2));
      expect(find.textContaining('DATA_BASE_URL'), findsOneWidget);
      expect(find.textContaining('MAP_STYLE'), findsOneWidget);
    });

    // 상태바가 내주는 높이와 실제로 쓰는 높이가 어긋나면 경고가 잘린다.
    // 잘린 경고는 경고가 아니다 — 고지 배너에서 이미 한 번 겪었다.
    testWidgets('상태바가 내준 예산 안에 들어간다', (tester) async {
      const broken = AppConfig(
        dataBaseUrl: '',
        workerBaseUrl: '',
        mapStyle: '',
      );
      final size = await pumpWarning(tester, broken);

      expect(
        size.height,
        lessThanOrEqualTo(broken.issues.length * (kConfigWarningHeight + 2)),
      );
    });

    // 글자 배율을 키우면 줄이 접히고, 접히면 예산을 넘는다. 고지 배너에서
    // 그대로 겪은 실패라서 여기서도 같은 방식으로 막는다 — 접지 말고 줄인다.
    testWidgets('글자 배율이 커져도 한 줄로 줄어든다', (tester) async {
      tester.view.physicalSize = const Size(1080, 400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWithValue(
              const AppConfig(dataBaseUrl: '', workerBaseUrl: '', mapStyle: ''),
            ),
          ],
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.6)),
            child: const MaterialApp(
              home: Scaffold(body: Align(child: ConfigWarning())),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(ConfigWarning),
          matching: find.byType(Text),
        ),
      )) {
        expect(text.maxLines, 1);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
