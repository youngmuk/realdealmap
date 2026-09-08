import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/config.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/detail/detail_sheet.dart';
import 'package:realdealmap/features/detail/mini_map_view.dart';
import 'package:realdealmap/features/list/list_page.dart';
import 'package:realdealmap/state/app_state.dart';
import 'package:realdealmap/state/filters.dart';
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

/// 필터를 고정해 화면에 물린다. 화면을 세워 두고 칩을 눌러 가는 것보다
/// 무엇을 시험하는지가 분명하다.
class _FixedFilter extends FilterController {
  _FixedFilter(this.fixed);
  final TxFilter fixed;

  @override
  TxFilter build() => fixed;
}

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

    // 수집 쪽에서 한 유형의 일일 쿼터가 바닥나면 그 유형만 빠진 채 배포된다.
    // 그때 "거래가 없습니다"라고만 하면 사용자는 이 지역에 그런 거래가 없다고
    // 읽는다. 실제로는 우리가 아직 못 받은 것이다.
    group('아직 못 받은 유형', () {
      Future<void> chunk(String datasetKey) => db
          .into(db.chunkRows)
          .insert(
            ChunkRowsCompanion.insert(
              path: 'v1/data/11680/202608/$datasetKey.json.gz',
              sggCd: '11680',
              datasetKey: datasetKey,
              period: '202608',
              sha256: 'h',
              records: 0,
              appliedAt: '2026-09-08T00:00:00Z',
            ),
          );

      test('받아 본 유형만 센다', () async {
        await chunk('apartment/sale');

        expect(await db.coveredDatasetKeys('11680'), {'apartment/sale'});
      });

      // 0건짜리 유형도 청크 행이 남는다. 그것을 "못 받았다"로 세면 정상적인
      // 0건까지 안내가 붙어, 정작 중요한 때에 아무도 읽지 않게 된다.
      test('받았는데 0건인 것은 받은 것으로 센다', () async {
        await chunk('land/sale');

        final covered = await db.coveredDatasetKeys('11680');
        expect(covered, contains('land/sale'));
        expect(missingLabels(const TxFilter(), covered), isNot(contains('토지')));
      });

      test('조건에 걸린 유형만 말한다', () {
        const covered = {'apartment/sale', 'apartment/rent'};

        // 아파트만 보고 있으면 토지가 없어도 알릴 일이 아니다
        expect(
          missingLabels(
            const TxFilter(datasetKeys: {'apartment/sale'}),
            covered,
          ),
          isEmpty,
        );
        expect(
          missingLabels(const TxFilter(datasetKeys: {'land/sale'}), covered),
          ['토지'],
        );
      });

      // 첫 동기화 전에는 무엇이 빠졌는지 말할 수 없다. 그때 다섯 유형을 늘어놓으면
      // 안내가 아니라 소음이고, 정작 한 유형이 빠졌을 때 아무도 읽지 않는다.
      test('하나도 못 받았으면 아무 유형도 말하지 않는다', () {
        expect(missingLabels(const TxFilter(), const {}), isEmpty);
      });

      test('필터가 비어 있으면 9종 전부를 기준으로 본다', () {
        // 비어 있음은 "전부"다. 그때 빠진 유형을 안 세면 배너가 안 뜬다
        final missing = missingLabels(const TxFilter(), {'apartment/sale'});

        expect(missing, contains('토지'));
        expect(missing, contains('오피스텔'));
      });

      testWidgets('빠진 유형만 골랐으면 그렇게 말한다', (tester) async {
        await chunk('apartment/sale');
        await db.into(db.txRows).insert(_tx('a', lat: 37.5, lng: 127.0));

        SharedPreferences.setMockInitialValues({'region.selected': '11680'});
        prefs = await SharedPreferences.getInstance();

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              prefsProvider.overrideWithValue(prefs),
              filterProvider.overrideWith(
                () => _FixedFilter(const TxFilter(datasetKeys: {'land/sale'})),
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: ListPage())),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('아직 받지 못했습니다'), findsOneWidget);
        expect(find.text('조건에 맞는 거래가 없습니다'), findsNothing);
      });
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

      // 미니뷰가 설정(타일 출처)을 읽는다. 실제 앱에서는 늘 스코프 안이다.
      // 키를 비워 두면 OSM 폴백으로 간다 — 테스트에서 진짜 키를 쓸 이유가 없다.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWithValue(
              const AppConfig(
                dataBaseUrl: 'https://example.test',
                workerBaseUrl: 'https://example.test',
                mapStyle: '',
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: DetailSheet(tx: tx)),
          ),
        ),
      );
      // 타일은 테스트에서 실제로 받아지지 않는다(HTTP가 막혀 있다).
      // pumpAndSettle은 끝나지 않을 수 있으므로 프레임을 몇 번만 돌린다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
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

    // 도면 블록 자리를 지도 미니뷰로 채웠다(D-4). 도면 자체는 건축HUB가
    // 필요해 아직 없다.
    testWidgets('좌표가 있으면 지도 미니뷰를 얹는다', (tester) async {
      final tx = await insert(_tx('a', lat: 37.5, lng: 127.0));

      await pumpDetail(tester, tx);

      expect(find.byType(MiniMapView), findsOneWidget);
    });

    // 빈 상자를 남기면 "불러오지 못했다"로 읽힌다. 블록 자체가 없어야 한다.
    testWidgets('좌표가 없으면 미니뷰 자리를 아예 두지 않는다', (tester) async {
      final tx = await insert(_tx('a'));

      await pumpDetail(tester, tx);

      expect(find.byType(MiniMapView), findsNothing);
    });

    // 근사 좌표에 뾰족한 핀을 찍으면 "그 건물"이라고 말하는 것이 된다.
    // 실측으로 226~582 m가 빗나간다.
    testWidgets('근사 좌표는 미니뷰에서도 근사라고 말한다', (tester) async {
      final tx = await insert(
        _tx('a', lat: 37.5, lng: 127.0, precision: 'umd'),
      );

      await pumpDetail(tester, tx);

      final view = tester.widget<MiniMapView>(find.byType(MiniMapView));
      expect(view.approximate, isTrue);
      expect(find.textContaining('법정동 근사 위치'), findsOneWidget);
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
