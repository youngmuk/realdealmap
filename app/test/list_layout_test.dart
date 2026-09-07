import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/list/list_page.dart';
import 'package:realdealmap/state/app_state.dart';
import 'package:realdealmap/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 목록 한 줄이 **실제 기기 폭에서** 읽히는가.
///
/// 다른 목록 테스트는 글자가 있는지만 본다. 그것만으로는 부족했다 —
/// 가격을 오른쪽에 두었더니 글자 배율 2배에서 가격이 폭을 거의 다 가져갔고,
/// 부가정보가 한 글자씩 세로로 접혀 열다섯 줄이 되었다. 글자는 다 있었으므로
/// 기존 테스트는 전부 통과했고, 실기기 화면을 보고서야 알았다.
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  const meta = '아파트 전월세 · 49.5m² (15.0평) · 8층 · 2026.09.04';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({'region.selected': '11680'});
    prefs = await SharedPreferences.getInstance();

    await db
        .into(db.txRows)
        .insert(
          TxRowsCompanion.insert(
            txId: 'rent',
            sggCd: '11680',
            datasetKey: 'apartment/rent',
            period: '202609',
            umdNm: '역삼동',
            contractedOn: '2026-09-04',
            cancelled: false,
            precision: 'exact',
            raw: '{}',
            lat: const Value(37.5),
            lng: const Value(127.0),
            name: const Value('역삼래미안'),
            deposit: const Value(25000),
            monthlyRent: const Value(145),
            areaSqm: const Value(49.5),
            floor: const Value(8),
          ),
        );
  });

  tearDown(() => db.close());

  testWidgets('배율 2배 · 폰 폭에서 부가정보가 짓눌리지 않는다', (tester) async {
    // 실기기와 같은 논리 폭 393. 기존 목록 테스트는 dpr 1로 1080을 썼는데,
    // 그 폭에서는 이 결함이 재현되지 않는다.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1080 / 393;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(kTextScale)),
              child: const Scaffold(body: ListPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.text(meta));
    // 좌우 여백과 색 막대를 뺀 나머지를 거의 다 써야 한다. 예전에는 약 60이었다.
    expect(
      size.width,
      greaterThan(300),
      reason: '부가정보가 좁은 칸에 갇혔다 — 가격이 폭을 가져갔을 때 그렇게 된다',
    );
    // 글자 크기에 기대지 않고 모양으로 잰다. 한 글자씩 접힌 문단은 좁고 길다 —
    // 결함이 있던 화면에서는 폭 약 60에 높이 400이었다. 정상 문단은 세로보다
    // 가로가 길다.
    expect(
      size.height,
      lessThan(size.width),
      reason: '부가정보가 세로로 접혔다 (폭 ${size.width}, 높이 ${size.height})',
    );
  });

  testWidgets('배율 2배에서 금액이 잘리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1080 / 393;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(kTextScale)),
              child: const Scaffold(body: ListPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2억 5,000만원 / 145만원'), findsOneWidget);
  });
}
