import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/filter/filter_sheet.dart';
import 'package:realdealmap/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 필터 화면이 **모델에 실제로 닿는지** 본다.
///
/// 모델 테스트만으로는 부족하다. 칩을 눌러도 아무 일이 없거나, 누른 것과 다른
/// 값이 바뀌는 배선 실수는 화면을 세워야만 잡힌다 — 실기기에서 손으로 누르는
/// 확인은 좌표가 조금만 어긋나도 "안 눌렸다"와 "안 먹었다"를 구별하지 못했다.
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({'region.selected': '11680'});
    prefs = await SharedPreferences.getInstance();

    for (final period in ['202608', '202607']) {
      await db
          .into(db.txRows)
          .insert(
            TxRowsCompanion.insert(
              txId: 'tx-$period',
              sggCd: '11680',
              datasetKey: 'apartment/sale',
              period: period,
              umdNm: '논현동',
              contractedOn: '2026-08-14',
              cancelled: false,
              precision: 'exact',
              raw: '{}',
              lat: const Value(37.5),
              lng: const Value(127.0),
            ),
          );
    }
  });

  tearDown(() => db.close());

  Future<ProviderContainer> pump(WidgetTester tester) async {
    // 기본 시험 화면(800x600)에는 시트 내용이 다 안 들어가 아래쪽 항목을 누를 수
    // 없다. 실기기 크기를 준다 — 잘려서 못 누르는 것과 눌러도 안 먹는 것을
    // 구별하지 못하면 이 테스트가 존재할 이유가 없다.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        prefsProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: FilterSheet())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('거래 종류를 누르면 필터가 좁혀진다', (tester) async {
    final container = await pump(tester);
    expect(container.read(filterProvider).isEmpty, isTrue);

    await tester.tap(find.text('매매'));
    await tester.pumpAndSettle();

    final filter = container.read(filterProvider);
    expect(filter.selectedTrades, {'rent'});
    expect(filter.datasetKeys, everyElement(endsWith('/rent')));
  });

  testWidgets('매물 유형을 누르면 그 유형이 빠진다', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text('토지'));
    await tester.pumpAndSettle();

    expect(
      container.read(filterProvider).selectedProperties,
      isNot(contains('land')),
    );
  });

  testWidgets('데이터에 있는 달만 보여준다', (tester) async {
    await pump(tester);

    expect(find.text('2026년 8월'), findsOneWidget);
    expect(find.text('2026년 7월'), findsOneWidget);
    // 받지 않은 달은 고를 수 없어야 한다. 고르면 빈 화면이고, 사용자는 고장으로 읽는다
    expect(find.text('2026년 6월'), findsNothing);
  });

  testWidgets('달을 누르면 그 달만 남는다', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text('2026년 7월'));
    await tester.pumpAndSettle();

    expect(container.read(filterProvider).months, {'202607'});
  });

  testWidgets('해제 포함을 끄면 필터에 반영된다', (tester) async {
    final container = await pump(tester);
    expect(container.read(filterProvider).includeCancelled, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(container.read(filterProvider).includeCancelled, isFalse);
  });

  testWidgets('초기화는 필터를 비운다', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text('매매'));
    await tester.pumpAndSettle();
    expect(container.read(filterProvider).isEmpty, isFalse);

    await tester.tap(find.text('초기화'));
    await tester.pumpAndSettle();

    expect(container.read(filterProvider).isEmpty, isTrue);
  });

  // 토지는 전월세가 없다. 누를 수 있게 두면 눌러도 아무 일이 없어 고장으로 읽힌다.
  testWidgets('전월세만 고르면 토지 칩이 잠긴다', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text('매매'));
    await tester.pumpAndSettle();

    expect(
      container.read(filterProvider).availableProperties,
      isNot(contains('land')),
    );
    final chip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('토지'), matching: find.byType(FilterChip)),
    );
    expect(chip.onSelected, isNull, reason: '고를 수 없는 것은 누를 수 없어야 한다');
    expect(find.text('토지는 매매만 있습니다'), findsOneWidget);
  });
}
