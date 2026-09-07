import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/detail/detail_sheet.dart';
import 'package:realdealmap/features/list/list_page.dart';
import 'package:realdealmap/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 목록과 상세 화면 (T5.10).
///
/// 여기서 지키려는 것은 모양이 아니라 **말**이다. 지도에 못 그리는 건수를 감추면
/// 사용자는 데이터가 없다고 읽고, 해제된 거래를 조용히 보통 거래처럼 그리면
/// 값을 잘못 읽는다. 둘 다 화면을 세워야만 잡힌다.
TxRowsCompanion _tx(
  String id, {
  double? lat,
  double? lng,
  String datasetKey = 'apartment/sale',
  String? name = '개포주공',
  int? amount = 250000,
  int? deposit,
  int? monthlyRent,
  bool cancelled = false,
  String precision = 'exact',
  Map<String, String> raw = const {'sggNm': '강남구'},
}) => TxRowsCompanion.insert(
  txId: id,
  sggCd: '11680',
  datasetKey: datasetKey,
  period: '202608',
  umdNm: '개포동',
  contractedOn: '2026-08-14',
  cancelled: cancelled,
  precision: precision,
  raw: jsonEncode(raw),
  lat: Value(lat),
  lng: Value(lng),
  name: Value(name),
  amount: Value(amount),
  deposit: Value(deposit),
  monthlyRent: Value(monthlyRent),
  areaSqm: const Value(84.97),
  floor: const Value(12),
);

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({'region.selected': '11680'});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => db.close());

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: Scaffold(body: ListPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('목록', () {
    test('좌표가 없어도 목록에는 나온다 (FR-2)', () async {
      await db.into(db.txRows).insert(_tx('mapped', lat: 37.5, lng: 127.0));
      await db.into(db.txRows).insert(_tx('unmapped', name: null));

      final rows = await db.listTransactions(sggCd: '11680');

      expect(rows, hasLength(2));
      expect(await db.unmappedCount('11680'), 1);
    });

    testWidgets('지도 미표시 건수를 밝힌다', (tester) async {
      await db.into(db.txRows).insert(_tx('a', lat: 37.5, lng: 127.0));
      await db.into(db.txRows).insert(_tx('b'));
      await db.into(db.txRows).insert(_tx('c'));

      await pumpList(tester);

      // 감추면 사용자는 데이터가 없는 것으로 오해한다. 실제로는 원천이 지번을
      // 가려 좌표를 만들 수 없었을 뿐이고, 목록에는 전부 있다.
      expect(find.textContaining('지도 미표시 2건'), findsOneWidget);
    });

    testWidgets('전부 좌표가 있으면 배너를 띄우지 않는다', (tester) async {
      await db.into(db.txRows).insert(_tx('a', lat: 37.5, lng: 127.0));

      await pumpList(tester);

      expect(find.textContaining('지도 미표시'), findsNothing);
    });

    testWidgets('해제된 거래는 해제라고 말한다', (tester) async {
      await db
          .into(db.txRows)
          .insert(_tx('x', lat: 37.5, lng: 127.0, cancelled: true));

      await pumpList(tester);

      expect(find.text('해제'), findsOneWidget);
    });

    testWidgets('좌표 없는 행에는 지도 미표시 표를 단다', (tester) async {
      await db.into(db.txRows).insert(_tx('nogeo'));

      await pumpList(tester);

      // 배너와 행 표시가 각각 하나씩
      expect(find.text('지도 미표시'), findsOneWidget);
    });

    testWidgets('조건에 맞는 거래가 없으면 그렇게 말한다', (tester) async {
      await pumpList(tester);

      expect(find.text('조건에 맞는 거래가 없습니다'), findsOneWidget);
    });

    testWidgets('전월세는 보증금/월세로 적는다', (tester) async {
      await db
          .into(db.txRows)
          .insert(
            _tx(
              'rent',
              lat: 37.5,
              lng: 127.0,
              datasetKey: 'apartment/rent',
              amount: null,
              deposit: 50000,
              monthlyRent: 120,
            ),
          );

      await pumpList(tester);

      expect(find.text('5억 / 120만원'), findsOneWidget);
    });
  });

  group('상세', () {
    Future<void> pumpDetail(WidgetTester tester, TxRow tx) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DetailSheet(tx: tx)),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<TxRow> insert(TxRowsCompanion row) async {
      await db.into(db.txRows).insert(row);
      return (await db.select(db.txRows).get()).first;
    }

    testWidgets('금액이 화면에서 가장 큰 글자다', (tester) async {
      final tx = await insert(_tx('a', lat: 37.5, lng: 127.0));

      await pumpDetail(tester, tx);

      // 금액은 머리말과 표에 모두 나온다. 여기서 볼 것은 **가장 큰 쪽**이다.
      final biggest = tester
          .widgetList<Text>(find.text('25억'))
          .map((t) => t.style?.fontSize ?? 0)
          .reduce((a, b) => a > b ? a : b);
      // 주소도 머리말과 위치 표에 모두 나온다.
      final addresses = tester
          .widgetList<Text>(find.text('개포동'))
          .map((t) => t.style?.fontSize ?? 14);

      expect(
        addresses.every((size) => biggest > size),
        isTrue,
        reason: '실거래가는 값이 주인공이다. 화면에서 가장 큰 글자가 금액이어야 한다',
      );
    });

    testWidgets('표에 계약일과 면적이 있다', (tester) async {
      final tx = await insert(_tx('a', lat: 37.5, lng: 127.0));

      await pumpDetail(tester, tx);

      expect(find.text('계약일'), findsOneWidget);
      expect(find.text('면적'), findsOneWidget);
      expect(find.text('84.97m² (25.7평)'), findsOneWidget);
    });

    // 우리가 이름을 붙이지 못한 항목도 사용자에게 도달해야 한다 (FR-3).
    testWidgets('표에 못 실은 원문도 남긴다', (tester) async {
      final tx = await insert(
        _tx('a', lat: 37.5, lng: 127.0, raw: {'알수없는필드': '값123'}),
      );

      await pumpDetail(tester, tx);

      expect(find.textContaining('원문'), findsWidgets);
    });

    // 근사 좌표를 정확한 위치인 것처럼 두면 사용자가 엉뚱한 건물을 본다.
    testWidgets('법정동 근사 좌표임을 밝힌다', (tester) async {
      final tx = await insert(
        _tx('a', lat: 37.5, lng: 127.0, precision: 'umd'),
      );

      await pumpDetail(tester, tx);

      expect(find.textContaining('근사'), findsWidgets);
    });

    testWidgets('해제된 거래는 금액에 취소선을 긋는다', (tester) async {
      final tx = await insert(_tx('a', lat: 37.5, lng: 127.0, cancelled: true));

      await pumpDetail(tester, tx);

      expect(
        tester
            .widgetList<Text>(find.text('25억'))
            .any((t) => t.style?.decoration == TextDecoration.lineThrough),
        isTrue,
        reason: '해제된 거래를 보통 거래처럼 그리면 값을 잘못 읽는다',
      );
    });
  });
}
