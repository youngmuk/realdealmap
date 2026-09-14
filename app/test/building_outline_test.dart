import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/data/sync/remote.dart';
import 'package:realdealmap/features/detail/building_outline.dart';
import 'package:realdealmap/state/app_state.dart';

/// 상세창의 건물 그림.
///
/// **없을 때 아무것도 안 보이는 것**이 이 위젯의 절반이다. 빈 상자를 남기면
/// 사용자는 "불러오지 못했다"로 읽고, 그것은 자기 회선이나 앱을 의심하게 만든다.

class _FakeRemote implements RemoteSource {
  _FakeRemote(this.bodies);
  final Map<String, Uint8List> bodies;

  @override
  Future<Uint8List?> get(String key) async => bodies[key];
}

Uint8List _bytes(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

List<double> _square(double lng, double lat, {double size = 0.0002}) => [
  lng, lat, //
  lng + size, lat,
  lng + size, lat + size,
  lng, lat + size,
  lng, lat,
];

Map<String, Uint8List> _served({Map<String, List<int>>? buildings}) => {
  'v1/shapes/11215/index.json': _bytes({
    'schemaVersion': 1,
    'sggCd': '11215',
    'source': '20260901',
    'attribution': '행정안전부 도로명주소 건물 도형 · 공공누리 제1유형',
    'dongs': {
      '중곡동': {
        'bjdCd': '1121510100',
        'buildings': 1,
        'bytes': 100,
        'parts': [
          {'file': '1121510100.1.json.gz', 'from': '1', 'to': '199-9'},
        ],
      },
    },
  }),
  'v1/shapes/11215/1121510100.1.json.gz': _bytes({
    'schemaVersion': 1,
    'sggCd': '11215',
    'bjdCd': '1121510100',
    'umdNm': '중곡동',
    'source': '20260901',
    'attribution': '행정안전부 도로명주소 건물 도형 · 공공누리 제1유형',
    'shapes': [
      _square(127.0700, 37.5540),
      _square(127.0703, 37.5540),
      _square(127.0706, 37.5540),
    ],
    'buildings':
        buildings ??
        {
          '12-3': [0],
        },
  }),
};

TxRow _tx({String? jibun = '12-3'}) => TxRow(
  rid: 1,
  txId: 'tx-1',
  sggCd: '11215',
  datasetKey: 'apartment/sale',
  period: '202608',
  umdNm: '중곡동',
  jibun: jibun,
  contractedOn: '2026-08-14',
  cancelled: false,
  precision: 'exact',
  raw: '{}',
);

Future<void> _pump(
  WidgetTester tester,
  TxRow tx, {
  Map<String, Uint8List>? served,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        remoteProvider.overrideWithValue(_FakeRemote(served ?? _served())),
      ],
      child: MaterialApp(
        home: Scaffold(body: BuildingOutlineBlock(tx: tx)),
      ),
    ),
  );
  // 첫 프레임은 자리 없음, 받아온 뒤 한 번 더.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('건물이 있으면 그림과 출처가 나온다', (tester) async {
    await _pump(tester, _tx());

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('행정안전부 도로명주소 건물 도형'), findsOneWidget);
    // 공공누리 제1유형의 조건이고, 언제 자료인지도 함께 밝힌다.
    expect(find.textContaining('2026년 9월'), findsOneWidget);
  });

  testWidgets('그림에 이 건물과 이웃이 함께 들어간다', (tester) async {
    await _pump(tester, _tx());

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<BuildingOutlinePainter>()
        .first;

    expect(painter.outlines.target.length, 1);
    expect(painter.outlines.neighbours, isNotEmpty);
  });

  // 원천이 지번을 가린 거래다. 비슷한 번호의 남의 건물을 그리느니 자리를 비운다.
  testWidgets('가려진 지번이면 블록 자체가 없다', (tester) async {
    await _pump(tester, _tx(jibun: '3**'));

    expect(find.byType(BuildingOutlinePainter), findsNothing);
    expect(find.textContaining('행정안전부'), findsNothing);
  });

  testWidgets('아직 안 올린 지역이면 블록 자체가 없다', (tester) async {
    await _pump(tester, _tx(), served: const {});

    expect(find.textContaining('행정안전부'), findsNothing);
  });

  // 단지는 동이 여럿인데 거래 자료에는 동 번호가 없다. 하나만 그리면
  // 사용자는 그 동의 거래라고 읽는다 — 우리가 모르는 것을 아는 척하게 된다.
  testWidgets('한 지번에 여러 동이면 모두 그리고 그렇다고 말한다', (tester) async {
    await _pump(
      tester,
      _tx(),
      served: _served(
        buildings: {
          '12-3': [0, 1, 2],
        },
      ),
    );

    expect(find.textContaining('건물 3동'), findsOneWidget);
    expect(find.textContaining('어느 동인지는 알 수 없습니다'), findsOneWidget);
  });

  testWidgets('그리다 죽지 않는다', (tester) async {
    await _pump(tester, _tx());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
