import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/data/search/umd_index.dart';
import 'package:realdealmap/data/sync/region_index.dart';
import 'package:realdealmap/data/sync/remote.dart';
import 'package:realdealmap/features/map/map_focus.dart';
import 'package:realdealmap/features/map/search_box.dart';
import 'package:realdealmap/state/app_state.dart';

/// 지도 위 검색창.
///
/// 무엇을 고르는지는 `place_search_test.dart`에서 따로 센다. 여기서 보는 것은
/// **배선**이다 — 친 글자가 색인과 데이터베이스에 닿는지, 고른 것이 지도를
/// 움직이는지. 이 배선이 끊기면 규칙이 아무리 맞아도 화면에서는 아무 일도
/// 일어나지 않고, 그것은 화면을 세워야만 잡힌다.

RegionSummary _at(String sggCd, String sido, String sgg, LatLng at) =>
    RegionSummary(
      sggCd: sggCd,
      name: '$sido $sgg',
      sidoName: sido,
      sggName: sgg,
      records: 10,
      located: 10,
      refreshedAt: '2026-09-14T00:00:00Z',
      center: at,
      bbox: BoundingBox(
        south: at.lat - 0.02,
        north: at.lat + 0.02,
        west: at.lng - 0.02,
        east: at.lng + 0.02,
      ),
    );

final _index = RegionIndex([
  _at('11215', '서울특별시', '광진구', const LatLng(37.5385, 127.0823)),
  _at('26350', '부산광역시', '해운대구', const LatLng(35.1631, 129.1636)),
]);

Uint8List _umdBytes() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'source': '20260901',
      'umds': [
        ['중곡동', '11215', 37.561153, 127.084264],
        ['우동', '26350', 35.1631, 129.1636],
      ],
    }),
  ),
);

class _Remote implements RemoteSource {
  _Remote({this.offline = false});
  final bool offline;

  @override
  Future<Uint8List?> get(String key) async {
    if (offline) throw RemoteException(key, '네트워크에 닿지 않는다');
    return key == kUmdIndexKey ? _umdBytes() : null;
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.batch((b) {
      b.insertAll(db.txRows, [
        TxRowsCompanion.insert(
          txId: 'a',
          sggCd: '11215',
          datasetKey: 'apartment/sale',
          period: '202608',
          umdNm: '구의동',
          contractedOn: '2026-08-14',
          cancelled: false,
          precision: 'exact',
          raw: '{}',
          jibun: const Value('251-157'),
          name: const Value('아델리아 구의타워'),
          lat: const Value(37.5401),
          lng: const Value(127.0899),
        ),
      ]);
    });
  });

  tearDown(() => db.close());

  Widget app({bool offline = false, RegionIndex? regions}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      remoteProvider.overrideWithValue(_Remote(offline: offline)),
      regionIndexProvider.overrideWith(() => _FixedIndex(regions ?? _index)),
      selectedRegionProvider.overrideWith(() => _FixedRegion('11215')),
    ],
    child: const MaterialApp(
      home: Scaffold(body: Align(child: MapSearchBox())),
    ),
  );

  Future<void> open(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('주소 검색'));
    await tester.pumpAndSettle();
  }

  /// 입력칸에 친 글자도 Text다. 목록 안만 센다.
  Finder inList(String text) =>
      find.descendant(of: find.byType(InkWell), matching: find.text(text));

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    // 치는 동안은 세지 않는다. 손이 멈춘 뒤에야 목록이 나온다.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  // 늘 펼쳐 두면 지도 위쪽을 계속 덮는다. 지도가 이 앱의 본체다.
  testWidgets('평소에는 돋보기 하나다', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('주소 검색'), findsOneWidget);
  });

  testWidgets('누르면 펼쳐지고 닫으면 접힌다', (tester) async {
    await open(tester, app());
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('친 글자가 동 색인에 닿는다', (tester) async {
    await open(tester, app());

    await type(tester, '중곡동');

    expect(inList('중곡동'), findsOneWidget);
    expect(inList('서울특별시 광진구'), findsOneWidget);
  });

  testWidgets('이 지역 단지 이름은 데이터베이스에서 온다', (tester) async {
    await open(tester, app());

    await type(tester, '아델리아');

    expect(inList('아델리아 구의타워'), findsOneWidget);
    expect(inList('구의동 251-157'), findsOneWidget);
  });

  // 치는 동안 지도가 따라 움직이면 사용자는 보던 자리를 잃는다. 되돌릴 방법도 없다.
  testWidgets('고르기 전에는 지도가 움직이지 않는다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        remoteProvider.overrideWithValue(_Remote()),
        regionIndexProvider.overrideWith(() => _FixedIndex(_index)),
        selectedRegionProvider.overrideWith(() => _FixedRegion('11215')),
      ],
    );
    addTearDown(container.dispose);

    await open(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Align(child: MapSearchBox())),
        ),
      ),
    );

    await type(tester, '중곡동');
    expect(container.read(mapFocusProvider), isNull);

    await tester.tap(inList('중곡동'));
    await tester.pumpAndSettle();

    final focus = container.read(mapFocusProvider);
    expect(focus, isNotNull);
    expect(focus!.lat, closeTo(37.561153, 1e-6));
    expect(focus.lng, closeTo(127.084264, 1e-6));
    // 고른 뒤에도 열려 있으면 방금 간 자리를 검색창이 덮는다.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('못 찾으면 무엇까지 찾는지 밝힌다', (tester) async {
    await open(tester, app());

    await type(tester, '테헤란로 123');

    expect(find.textContaining('도로명'), findsOneWidget);
  });

  // 자료를 못 받은 것을 "없습니다"로 말하면 거짓말이 된다. 사용자는 동 이름을
  // 잘못 안 줄 알고 몇 번이고 다시 친다.
  testWidgets('지역 목록을 못 받았으면 없다고 하지 않는다', (tester) async {
    await open(tester, app(offline: true, regions: const RegionIndex([])));

    await type(tester, '중곡동');

    expect(find.textContaining('아직 받지 못했습니다'), findsOneWidget);
    expect(find.textContaining('찾는 것이 없습니다'), findsNothing);
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
