import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/sync/building_shapes.dart';
import 'package:realdealmap/data/sync/remote.dart';

/// 건물 외곽선을 고르는 규칙.
///
/// 여기가 틀리면 상세창이 **남의 건물을 그린다.** 좌표도 그림도 각각은 멀쩡해
/// 보이므로 화면만 봐서는 잡히지 않는다. 그래서 "무엇을 요청했는가"까지 센다.

class _FakeRemote implements RemoteSource {
  _FakeRemote(this.bodies, {this.offline = false});

  /// 키 → 바이트. 없는 키는 404로 답한다
  final Map<String, Uint8List> bodies;
  bool offline;

  final List<String> asked = [];

  @override
  Future<Uint8List?> get(String key) async {
    asked.add(key);
    if (offline) throw RemoteException(key, '네트워크에 닿지 않는다');
    return bodies[key];
  }
}

Uint8List _bytes(Object json, {bool compress = false}) {
  final raw = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  return compress ? Uint8List.fromList(gzip.encode(raw)) : raw;
}

/// 남서쪽 모서리에서 [size]도만큼 뻗은 사각 건물.
List<double> _square(double lng, double lat, {double size = 0.0002}) => [
  lng, lat, //
  lng + size, lat,
  lng + size, lat + size,
  lng, lat + size,
  lng, lat,
];

Map<String, dynamic> _catalogJson({
  int schemaVersion = 1,
  List<Map<String, dynamic>> parts = const [
    {'file': '1121510100.1.json.gz', 'from': '1', 'to': '199-9'},
    {'file': '1121510100.2.json.gz', 'from': '2', 'to': '산 99'},
  ],
}) => {
  'schemaVersion': schemaVersion,
  'sggCd': '11215',
  'source': '20260901',
  'attribution': '행정안전부 도로명주소 건물 도형 · 공공누리 제1유형',
  'dongs': {
    '중곡동': {
      'bjdCd': '1121510100',
      'buildings': 2,
      'bytes': 100,
      'parts': parts,
    },
  },
};

Map<String, dynamic> _dongJson({
  int schemaVersion = 1,
  List<List<double>>? shapes,
  Map<String, List<int>>? buildings,
}) => {
  'schemaVersion': schemaVersion,
  'sggCd': '11215',
  'bjdCd': '1121510100',
  'umdNm': '중곡동',
  'source': '20260901',
  'attribution': '행정안전부 도로명주소 건물 도형 · 공공누리 제1유형',
  'shapes':
      shapes ??
      [
        _square(127.0700, 37.5540), // 이 거래의 건물
        _square(127.0703, 37.5540), // 바로 옆
        _square(127.0900, 37.5540), // 2km 밖
      ],
  'buildings':
      buildings ??
      {
        '12-3': [0],
      },
};

const String _catalogKey = 'v1/shapes/11215/index.json';
const String _partKey = 'v1/shapes/11215/1121510100.1.json.gz';

void main() {
  group('목차', () {
    test('지번이 든 조각을 고른다', () {
      final catalog = ShapeCatalog.decode(_bytes(_catalogJson()))!;

      expect(catalog.partFor('중곡동', '1')?.file, '1121510100.1.json.gz');
      expect(catalog.partFor('중곡동', '199-9')?.file, '1121510100.1.json.gz');
      expect(catalog.partFor('중곡동', '2')?.file, '1121510100.2.json.gz');
      // 산 지번도 사전 순 그대로다. 굽는 쪽이 같은 규칙으로 끊었다.
      expect(catalog.partFor('중곡동', '산 5')?.file, '1121510100.2.json.gz');
    });

    test('없는 동·없는 지번은 null이다', () {
      final catalog = ShapeCatalog.decode(_bytes(_catalogJson()))!;

      expect(catalog.partFor('군자동', '1'), isNull);
      expect(catalog.partFor('중곡동', '산 999'), isNull);
    });

    // 반쯤 읽으면 무엇이 옛 규칙으로 들어왔는지 알 수 없다.
    test('모르는 판은 통째로 버린다', () {
      expect(
        ShapeCatalog.decode(_bytes(_catalogJson(schemaVersion: 2))),
        isNull,
      );
    });

    test('내용이 아니면 null이다', () {
      expect(ShapeCatalog.decode(Uint8List.fromList(utf8.encode('{'))), isNull);
      expect(ShapeCatalog.decode(_bytes({'schemaVersion': 1})), isNull);
      expect(
        ShapeCatalog.decode(_bytes(_catalogJson(parts: const []))),
        isNull,
      );
    });
  });

  group('조각', () {
    test('gzip이든 아니든 같게 읽는다', () {
      final plain = DongShapes.decode(_bytes(_dongJson()))!;
      final zipped = DongShapes.decode(_bytes(_dongJson(), compress: true))!;

      expect(plain.shapes.length, 3);
      expect(zipped.shapes.length, 3);
      expect(zipped.attribution, contains('공공누리'));
    });

    test('지번이 가리키는 모양만 준다', () {
      final dong = DongShapes.decode(
        _bytes(
          _dongJson(
            buildings: {
              '12-3': [0, 2],
            },
          ),
        ),
      )!;

      expect(dong.outlinesFor('12-3').length, 2);
      expect(dong.outlinesFor('없는지번'), isEmpty);
    });

    // 좌표가 홀수면 그 뒤가 한 칸씩 밀린다. 그림은 그려지는데 자리가 틀린다 —
    // 화면에서는 "왜 저기지" 정도로만 보인다.
    test('좌표 개수가 홀수인 링이 있으면 통째로 버린다', () {
      final broken = _dongJson(
        shapes: [
          [127.07, 37.55, 127.071, 37.55, 127.07],
        ],
      );

      expect(DongShapes.decode(_bytes(broken)), isNull);
    });

    test('있지도 않은 번호를 가리키면 그 번호만 버린다', () {
      final dong = DongShapes.decode(
        _bytes(
          _dongJson(
            buildings: {
              '12-3': [0, 99],
            },
          ),
        ),
      )!;

      expect(dong.outlinesFor('12-3').length, 1);
    });
  });

  group('이웃과 그림 범위', () {
    final shapes = [
      Float64List.fromList(_square(127.0700, 37.5540)),
      Float64List.fromList(_square(127.0703, 37.5540)),
      Float64List.fromList(_square(127.0900, 37.5540)),
    ];

    test('가까운 것만 이웃으로 친다', () {
      final picked = neighboursAround(shapes, [shapes[0]]);

      expect(picked.length, 1);
      expect(picked.first, same(shapes[1]));
    });

    test('상한을 넘기지 않는다', () {
      final many = [
        for (var i = 0; i < 50; i++)
          Float64List.fromList(_square(127.0700 + i * 0.00001, 37.5540)),
      ];

      expect(neighboursAround(many, [many[0]], limit: 10).length, 10);
    });

    // 건물이 화면을 꽉 채우면 어디에 붙어 있는지 보이지 않는다.
    test('그림 범위에 여백이 붙는다', () {
      final target = [Float64List.fromList(_square(127.0700, 37.5540))];
      final window = outlineWindow(target);
      final bounds = outlineBounds(target);

      expect(window.west, lessThan(bounds.west));
      expect(window.east, greaterThan(bounds.east));
      expect(window.south, lessThan(bounds.south));
      expect(window.north, greaterThan(bounds.north));
    });
  });

  group('저장소', () {
    Map<String, Uint8List> served() => {
      _catalogKey: _bytes(_catalogJson()),
      _partKey: _bytes(_dongJson(), compress: true),
    };

    test('목차와 조각을 이어 이 거래의 건물을 찾는다', () async {
      final remote = _FakeRemote(served());
      final store = BuildingShapeStore(remote);

      final outlines = await store.outlines(
        sggCd: '11215',
        umdNm: '중곡동',
        jibun: '12-3',
      );

      expect(outlines, isNotNull);
      expect(outlines!.target.length, 1);
      expect(outlines.neighbours.length, 1); // 2km 밖은 빠진다
      expect(outlines.source, '20260901');
      expect(remote.asked, [_catalogKey, _partKey]);
    });

    // 원천이 지번을 가린 거래가 있다(`3**`). 비슷한 번호의 남의 건물을 그리는 것이
    // 빈자리보다 나쁘므로 아예 묻지 않는다.
    test('가려진 지번은 요청조차 하지 않는다', () async {
      final remote = _FakeRemote(served());
      final store = BuildingShapeStore(remote);

      expect(
        await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '3**'),
        isNull,
      );
      expect(
        await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: null),
        isNull,
      );
      expect(
        await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '  '),
        isNull,
      );
      expect(remote.asked, isEmpty);
    });

    test('같은 것을 두 번 받지 않는다', () async {
      final remote = _FakeRemote(served());
      final store = BuildingShapeStore(remote);

      await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '12-3');
      await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '12-3');

      expect(remote.asked, [_catalogKey, _partKey]);
    });

    // 아직 안 올린 지역이다. 다시 물어도 답이 같으므로 기억한다.
    test('없는 지역은 한 번만 묻는다', () async {
      final remote = _FakeRemote({});
      final store = BuildingShapeStore(remote);

      expect(
        await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '12-3'),
        isNull,
      );
      await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '12-3');

      expect(remote.asked, [_catalogKey]);
    });

    // 지하철에서 한 번 끊긴 것을 기억하면, 그 지역의 그림이 앱을 다시 켤 때까지
    // 영영 안 나온다.
    test('못 받은 것은 기억하지 않는다', () async {
      final remote = _FakeRemote(served(), offline: true);
      final store = BuildingShapeStore(remote);

      expect(
        await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '12-3'),
        isNull,
      );

      remote.offline = false;
      final retried = await store.outlines(
        sggCd: '11215',
        umdNm: '중곡동',
        jibun: '12-3',
      );

      expect(retried, isNotNull);
      expect(remote.asked, [_catalogKey, _catalogKey, _partKey]);
    });

    test('목차에 없는 지번이면 조각을 받지 않는다', () async {
      final remote = _FakeRemote(served());
      final store = BuildingShapeStore(remote);

      expect(
        await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '산 999'),
        isNull,
      );
      expect(remote.asked, [_catalogKey]);
    });

    test('조각에 그 지번이 없으면 null이다', () async {
      final remote = _FakeRemote(served());
      final store = BuildingShapeStore(remote);

      expect(
        await store.outlines(sggCd: '11215', umdNm: '중곡동', jibun: '11'),
        isNull,
      );
      expect(remote.asked, [_catalogKey, _partKey]);
    });
  });
}
