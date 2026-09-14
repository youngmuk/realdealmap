import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/search/place_search.dart';
import 'package:realdealmap/data/search/umd_index.dart';
import 'package:realdealmap/data/sync/region_index.dart';
import 'package:realdealmap/data/sync/remote.dart';

/// 검색이 고르는 규칙.
///
/// 여기가 틀리면 **남의 동네로 데려간다.** 지도는 아무 말 없이 그쪽을 보여주므로
/// 사용자는 자기가 고른 자리라고 믿는다. 그래서 "무엇이 위에 오는가"까지 센다.

RegionIndex _regions() => RegionIndex([
  RegionSummary(
    sggCd: '11215',
    name: '서울특별시 광진구',
    sidoName: '서울특별시',
    sggName: '광진구',
    records: 100,
    located: 100,
    refreshedAt: '2026-09-13T16:13:00Z',
    center: const LatLng(37.5385, 127.0823),
    bbox: const BoundingBox(
      south: 37.52,
      north: 37.56,
      west: 127.06,
      east: 127.10,
    ),
  ),
  RegionSummary(
    sggCd: '26350',
    name: '부산광역시 해운대구',
    sidoName: '부산광역시',
    sggName: '해운대구',
    records: 50,
    located: 50,
    refreshedAt: '2026-09-13T16:13:00Z',
    center: const LatLng(35.1631, 129.1636),
    bbox: const BoundingBox(
      south: 35.14,
      north: 35.20,
      west: 129.10,
      east: 129.20,
    ),
  ),
]);

Uint8List _umdBytes({bool compress = false, int schemaVersion = 1}) {
  final raw = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schemaVersion': schemaVersion,
        'source': '20260901',
        'attribution': '행정안전부 도로명주소 · 공공누리 제1유형',
        'umds': [
          ['중곡동', '11215', 37.561153, 127.084264],
          ['자양동', '11215', 37.5335, 127.0812],
          // 같은 이름의 동이 전국에 여럿이다. 어느 구인지 못 붙이면 고를 수 없다.
          ['중동', '11215', 37.55, 127.07],
          ['중동', '26350', 35.1631, 129.1636],
          // 지역 색인에 없는 시군구다 — 이름을 못 붙이므로 나오면 안 된다.
          ['없는동', '99999', 36.0, 127.0],
        ],
      }),
    ),
  );
  return compress ? Uint8List.fromList(gzip.encode(raw)) : raw;
}

final _local = [
  LocalPlace(
    umdNm: '구의동',
    jibun: '251-157',
    name: '아델리아 구의타워',
    center: LatLng(37.5401, 127.0899),
  ),
  LocalPlace(
    umdNm: '중곡동',
    jibun: '12-3',
    name: '',
    center: LatLng(37.5612, 127.0843),
  ),
];

class _FakeRemote implements RemoteSource {
  _FakeRemote(this.bodies, {this.offline = false});
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

void main() {
  group('초성', () {
    test('음절에서 첫 자음을 뽑는다', () {
      expect(choseongOf('중곡동'), 'ㅈㄱㄷ');
      expect(choseongOf('까치울'), 'ㄲㅊㅇ');
    });

    test('한글이 아닌 글자는 그대로 둔다', () {
      expect(choseongOf('e편한세상'), 'eㅍㅎㅅㅅ');
    });

    test('자음만 친 검색어를 가려낸다', () {
      expect(isChoseongQuery('ㅈㄱㄷ'), isTrue);
      expect(isChoseongQuery('중곡'), isFalse);
    });
  });

  group('점수', () {
    // 굽는 쪽(search.ts)과 같은 규칙이어야 한다. 어긋나면 확인한 결과와
    // 화면에 나오는 결과가 달라진다.
    test('완전히 같은 것이 가장 높다', () {
      expect(scoreOf('중곡동', '중곡동'), 1000);
    });

    test('앞에서 맞는 것이 가운데서 맞는 것보다 높다', () {
      expect(scoreOf('중곡동', '중곡'), greaterThan(scoreOf('용중곡리', '중곡')));
    });

    test('글자로 맞는 것이 초성으로 맞는 것보다 항상 높다', () {
      expect(scoreOf('중곡동', '중곡'), greaterThan(scoreOf('중곡동', 'ㅈㄱ')));
    });

    test('공백을 지우고 맞춘다', () {
      expect(scoreOf('성산동1가', normalizeQuery('성산동 1가')), 1000);
    });
  });

  group('색인 읽기', () {
    test('gzip이든 아니든 같게 읽는다', () {
      final plain = UmdIndex.decode(_umdBytes())!;
      final zipped = UmdIndex.decode(_umdBytes(compress: true))!;

      expect(plain.entries.length, 5);
      expect(zipped.entries.length, 5);
      expect(zipped.source, '20260901');
      expect(zipped.attribution, contains('공공누리'));
    });

    // 반쯤 읽으면 어느 줄이 옛 규칙으로 들어왔는지 알 수 없다.
    test('모르는 판은 통째로 버린다', () {
      expect(UmdIndex.decode(_umdBytes(schemaVersion: 2)), isNull);
    });

    test('내용이 아니면 null이다', () {
      expect(UmdIndex.decode(Uint8List.fromList(utf8.encode('{'))), isNull);
      expect(
        UmdIndex.decode(
          Uint8List.fromList(utf8.encode(jsonEncode({'schemaVersion': 1}))),
        ),
        isNull,
      );
    });

    test('줄이 깨졌으면 통째로 버린다', () {
      final broken = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'umds': [
              ['중곡동', '11215'],
            ],
          }),
        ),
      );

      expect(UmdIndex.decode(broken), isNull);
    });
  });

  group('고르기', () {
    final umds = UmdIndex.decode(_umdBytes())!;

    // 한 글자면 전국이 다 걸려 목록이 무의미해진다.
    test('한 글자로는 찾지 않는다', () {
      expect(
        searchPlaces(query: '동', regions: _regions(), umds: umds),
        isEmpty,
      );
    });

    test('시군구를 찾는다', () {
      final hits = searchPlaces(query: '해운대', regions: _regions(), umds: umds);

      expect(hits.first.kind, PlaceKind.region);
      expect(hits.first.title, '해운대구');
      expect(hits.first.sggCd, '26350');
    });

    test('시도 이름을 붙여 쳐도 찾는다', () {
      final hits = searchPlaces(
        query: '부산광역시 해운대',
        regions: _regions(),
        umds: umds,
      );

      expect(hits.map((h) => h.title), contains('해운대구'));
    });

    test('법정동을 찾고 어느 구인지 함께 준다', () {
      final hits = searchPlaces(query: '중곡동', regions: _regions(), umds: umds);
      final hit = hits.firstWhere((h) => h.kind == PlaceKind.umd);

      expect(hit.title, '중곡동');
      expect(hit.subtitle, '서울특별시 광진구');
      expect(hit.center.lat, closeTo(37.561153, 1e-6));
    });

    // 같은 이름의 동이 전국에 여럿이다. 둘 다 보여주고 사용자가 고르게 한다.
    test('같은 이름의 동은 모두 보여준다', () {
      final hits = searchPlaces(query: '중동', regions: _regions(), umds: umds);
      final dongs = hits.where((h) => h.kind == PlaceKind.umd).toList();

      expect(dongs.length, 2);
      expect(dongs.map((d) => d.sggCd), containsAll(['11215', '26350']));
    });

    // 어느 구인지 못 붙이면 목록에서 구별할 수가 없다.
    test('지역 색인에 없는 시군구의 동은 내보내지 않는다', () {
      final hits = searchPlaces(query: '없는동', regions: _regions(), umds: umds);

      expect(hits, isEmpty);
    });

    test('초성으로도 찾는다', () {
      final hits = searchPlaces(query: 'ㅈㄱㄷ', regions: _regions(), umds: umds);

      expect(hits.map((h) => h.title), contains('중곡동'));
    });

    test('이 지역의 단지 이름을 찾는다', () {
      final hits = searchPlaces(
        query: '아델리아',
        regions: _regions(),
        umds: umds,
        local: _local,
      );

      expect(hits.first.kind, PlaceKind.place);
      expect(hits.first.title, '아델리아 구의타워');
      expect(hits.first.subtitle, '구의동 251-157');
    });

    // 사람이 치는 주소의 가장 흔한 모양이다.
    test('"동 이름 + 지번"으로도 찾는다', () {
      final hits = searchPlaces(
        query: '구의동 251-157',
        regions: _regions(),
        umds: umds,
        local: _local,
      );

      expect(hits.first.kind, PlaceKind.place);
      expect(hits.first.center.lng, closeTo(127.0899, 1e-6));
    });

    // 지역을 찾는 사람에게 단지 이름을 먼저 보이면 맨 위가 늘 엉뚱한 것이 된다.
    test('점수가 같으면 넓은 것이 위다', () {
      final hits = searchPlaces(
        query: '중곡동',
        regions: _regions(),
        umds: umds,
        local: _local,
      );

      expect(hits.first.kind, PlaceKind.umd);
    });

    // 색인을 못 받았다고 검색이 통째로 죽으면 사용자에게는 고장으로 보인다.
    test('색인이 없어도 나머지로 답한다', () {
      final hits = searchPlaces(
        query: '해운대',
        regions: _regions(),
        umds: null,
        local: _local,
      );

      expect(hits.map((h) => h.title), contains('해운대구'));
    });

    test('상한을 넘기지 않는다', () {
      final many = [
        for (var i = 0; i < 40; i++)
          LocalPlace(
            umdNm: '중곡동',
            jibun: '$i',
            name: '테스트아파트$i',
            center: const LatLng(37.56, 127.08),
          ),
      ];

      final hits = searchPlaces(
        query: '테스트',
        regions: _regions(),
        local: many,
        limit: 12,
      );

      expect(hits.length, 12);
    });
  });

  group('색인 저장소', () {
    test('한 번만 받는다', () async {
      final remote = _FakeRemote({kUmdIndexKey: _umdBytes(compress: true)});
      final store = UmdIndexStore(remote);

      final first = await store.load();
      final second = await store.load();

      expect(first, isNotNull);
      expect(second, same(first));
      expect(remote.asked, [kUmdIndexKey]);
    });

    // 지하철에서 한 번 끊긴 것을 기억하면 앱을 다시 켤 때까지 검색이 안 된다.
    test('못 받은 것은 기억하지 않는다', () async {
      final remote = _FakeRemote({
        kUmdIndexKey: _umdBytes(compress: true),
      }, offline: true);
      final store = UmdIndexStore(remote);

      expect(await store.load(), isNull);

      remote.offline = false;
      expect(await store.load(), isNotNull);
      expect(remote.asked, [kUmdIndexKey, kUmdIndexKey]);
    });
  });
}
