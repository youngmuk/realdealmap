import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/sync/region_index.dart';
import 'package:realdealmap/features/region/region_picker.dart';
import 'package:realdealmap/state/app_state.dart';

/// 지역 선택 화면.
///
/// 거르는 규칙은 [RegionIndex] 쪽에서 따로 시험한다. 여기서 보는 것은 **배선**이다 —
/// 입력칸에 친 글자가 목록에 닿는지, 지운 뒤에 다시 전부 돌아오는지. 모델만
/// 맞고 화면에 안 닿는 실수는 화면을 세워야만 잡힌다.
RegionSummary _at(String sggCd, String sido, String sgg) => RegionSummary(
  sggCd: sggCd,
  name: '$sido $sgg',
  sidoName: sido,
  sggName: sgg,
  records: 1234,
  located: 1000,
  refreshedAt: '2026-09-08T00:00:00Z',
);

void main() {
  final index = RegionIndex([
    _at('11680', '서울특별시', '강남구'),
    _at('26110', '부산광역시', '중구'),
    _at('31110', '울산광역시', '중구'),
  ]);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          regionIndexProvider.overrideWith(() => _FixedIndex(index)),
          selectedRegionProvider.overrideWith(() => _FixedRegion('11680')),
        ],
        child: const MaterialApp(home: Scaffold(body: RegionPicker())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('처음에는 전부 보인다', (tester) async {
    await pump(tester);

    expect(find.text('강남구'), findsOneWidget);
    expect(find.text('중구'), findsNWidgets(2));
  });

  testWidgets('친 글자가 목록에 닿는다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '강남');
    await tester.pumpAndSettle();

    expect(find.text('강남구'), findsOneWidget);
    expect(find.text('중구'), findsNothing);
  });

  // 어느 중구인지는 시도 이름으로만 갈린다. 머리말이 없으면 고를 수가 없다.
  testWidgets('같은 이름이 여럿이면 시도 머리말로 구별된다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '중구');
    await tester.pumpAndSettle();

    // 입력칸에 친 글자도 Text다. 목록 안만 센다.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('중구'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('부산광역시'), findsOneWidget);
    expect(find.text('울산광역시'), findsOneWidget);
  });

  testWidgets('걸리는 것이 없으면 그렇게 말한다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '없는동네');
    await tester.pumpAndSettle();

    expect(find.text('그 이름의 지역이 없습니다.'), findsOneWidget);
  });

  // 지우고도 안 돌아오면 사용자는 앱이 고장 났다고 읽는다.
  testWidgets('지우면 전부 돌아온다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '강남');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('중구'), findsNWidgets(2));
  });
}

class _FixedIndex extends RegionIndexController {
  _FixedIndex(this.value);
  final RegionIndex value;

  @override
  Future<RegionIndex> build() async => value;
}

class _FixedRegion extends SelectedRegion {
  _FixedRegion(this.value);
  final String value;

  @override
  String? build() => value;
}
