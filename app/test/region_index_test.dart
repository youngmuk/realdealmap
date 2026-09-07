import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/sync/region_index.dart';
import 'package:realdealmap/data/sync/remote.dart';

class _FakeRemote implements RemoteSource {
  _FakeRemote(this.body, {this.offline = false});
  final String? body;
  final bool offline;

  @override
  Future<Uint8List?> get(String key) async {
    if (offline) throw RemoteException(key, '네트워크에 닿지 않는다');
    if (body == null) return null;
    return Uint8List.fromList(utf8.encode(body!));
  }
}

Map<String, dynamic> regionJson(
  String sggCd,
  String sggName, {
  required double south,
  required double north,
  required double west,
  required double east,
  double? centerLat,
  double? centerLng,
  bool withBox = true,
}) => {
  'sggCd': sggCd,
  'name': '서울특별시 $sggName',
  'sidoName': '서울특별시',
  'sggName': sggName,
  'records': 100,
  'located': 95,
  'refreshedAt': '2026-09-07T12:00:00.000Z',
  if (withBox)
    'bbox': {'south': south, 'north': north, 'west': west, 'east': east},
  if (withBox)
    'center': {
      'lat': centerLat ?? (south + north) / 2,
      'lng': centerLng ?? (west + east) / 2,
    },
};

String indexJson(List<Map<String, dynamic>> regions, {int version = 1}) =>
    jsonEncode({
      'version': version,
      'generatedAt': '2026-09-07T12:00:00.000Z',
      'regions': regions,
    });

/// 강남구·서초구의 실제 경계상자에 가깝게 잡은 값. 둘은 실제로 겹친다.
final _gangnam = regionJson(
  '11680',
  '강남구',
  south: 37.460,
  north: 37.533,
  west: 127.018,
  east: 127.116,
);
final _seocho = regionJson(
  '11650',
  '서초구',
  south: 37.440,
  north: 37.510,
  west: 126.990,
  east: 127.050,
);

void main() {
  group('색인 읽기', () {
    test('지역을 읽는다', () async {
      final index = await RegionIndexLoader(
        _FakeRemote(indexJson([_gangnam])),
      ).load();

      expect(index!.regions, hasLength(1));
      expect(index.byCode('11680')?.sggName, '강남구');
    });

    test('아직 아무것도 배포되지 않았으면 빈 색인이다', () async {
      final index = await RegionIndexLoader(_FakeRemote(null)).load();
      expect(index!.isEmpty, isTrue);
    });

    // 색인이 없다고 앱이 멈추면 안 된다. 이미 받아 둔 지역은 그대로 보여야 한다(FR-7).
    test('오프라인이면 null로 알려 이전 것을 이어 쓰게 한다', () async {
      final index = await RegionIndexLoader(
        _FakeRemote(null, offline: true),
      ).load();
      expect(index, isNull);
    });

    test('깨진 JSON이면 null이다', () async {
      expect(await RegionIndexLoader(_FakeRemote('{ not json')).load(), isNull);
    });

    test('모르는 판이면 읽지 않는다', () async {
      final index = await RegionIndexLoader(
        _FakeRemote(indexJson([_gangnam], version: 99)),
      ).load();
      expect(index, isNull);
    });

    test('시군구 코드가 5자리가 아닌 항목은 버린다', () async {
      final broken = {..._gangnam, 'sggCd': '116'};
      final index = await RegionIndexLoader(
        _FakeRemote(indexJson([broken, _gangnam])),
      ).load();
      expect(index!.regions.map((r) => r.sggCd), ['11680']);
    });
  });

  group('위치로 지역 찾기', () {
    final index = RegionIndex(
      [_gangnam, _seocho].map(RegionSummary.fromJson).toList(),
    );

    test('경계상자 안이면 그 지역이다', () {
      expect(index.at(const LatLng(37.52, 127.10))?.sggCd, '11680');
      expect(index.at(const LatLng(37.45, 127.00))?.sggCd, '11650');
    });

    // 경계상자는 실제 경계가 아니라 거래가 퍼진 범위라 이웃끼리 겹친다.
    test('겹치는 자리는 중심이 가까운 쪽을 고른다', () {
      // 겹침 구간(37.460~37.510, 127.018~127.050)의 서초 쪽 끝
      expect(index.at(const LatLng(37.470, 127.020))?.sggCd, '11650');
      // 같은 겹침 구간의 강남 쪽 끝
      expect(index.at(const LatLng(37.505, 127.048))?.sggCd, '11680');
    });

    // 엉뚱한 지역 데이터를 보여주면 사용자는 그 자리의 실거래라고 믿는다.
    test('담는 지역이 없으면 억지로 고르지 않는다', () {
      expect(index.at(const LatLng(35.15, 129.05)), isNull);
    });

    test('경계상자가 없는 지역은 후보가 아니다', () {
      final noBox = RegionIndex([
        RegionSummary.fromJson(
          regionJson(
            '11110',
            '종로구',
            south: 0,
            north: 0,
            west: 0,
            east: 0,
            withBox: false,
          ),
        ),
      ]);
      expect(noBox.at(const LatLng(37.57, 126.98)), isNull);
      expect(noBox.regions.single.hasMap, isFalse);
    });
  });

  group('가장 가까운 지역 (첫 진입)', () {
    final index = RegionIndex(
      [_gangnam, _seocho].map(RegionSummary.fromJson).toList(),
    );

    test('상자 밖이어도 가까우면 고른다', () {
      // 강남 상자 바로 북쪽
      expect(index.nearest(const LatLng(37.55, 127.06))?.sggCd, '11680');
    });

    // 부산에서 서울을 열어 주면 사용자는 자기 동네 실거래로 오해한다.
    test('너무 멀면 고르지 않는다', () {
      expect(index.nearest(const LatLng(35.15, 129.05)), isNull);
    });

    test('상자 안이면 그 지역이 이긴다', () {
      expect(index.nearest(const LatLng(37.52, 127.10))?.sggCd, '11680');
    });
  });

  group('지역 목록', () {
    test('시도로 묶고 시군구 이름 순으로 정렬한다', () {
      final index = RegionIndex(
        [_gangnam, _seocho].map(RegionSummary.fromJson).toList(),
      );
      expect(index.bySido['서울특별시']!.map((r) => r.sggName), ['강남구', '서초구']);
    });
  });

  // 세종특별자치시는 시군구가 없어 sggName이 빈 문자열이다. 그대로 쓰면 지역
  // 목록에 이름 없는 칸이 뜨고(건수만 덩그러니 남는다), 골라도 머리말이 빈 채다.
  // 실기기에서 보고 알았다 — 원천 카탈로그를 읽는 것만으로는 눈에 띄지 않는다.
  group('시군구가 없는 시도', () {
    RegionSummary sejong() => RegionSummary(
      sggCd: '36110',
      name: '세종특별자치시',
      sidoName: '세종특별자치시',
      sggName: '',
      records: 25046,
      located: 0,
      refreshedAt: '2026-09-08T00:00:00Z',
    );

    test('이름이 비면 시도 이름을 쓴다', () {
      expect(sejong().displayName, '세종특별자치시');
    });

    test('시군구가 있으면 그것을 쓴다', () {
      final gangnam = RegionSummary(
        sggCd: '11680',
        name: '서울특별시 강남구',
        sidoName: '서울특별시',
        sggName: '강남구',
        records: 10,
        located: 10,
        refreshedAt: '2026-09-08T00:00:00Z',
      );

      expect(gangnam.displayName, '강남구');
    });
  });

  // 256개를 시도별로만 늘어놓으면 원하는 곳까지 열 번 넘게 쓸어 내려야 한다.
  // 실기기에서 울산 중구를 찾는 데 열세 번을 밀었다.
  group('지역 검색', () {
    RegionSummary at(String sggCd, String sido, String sgg) => RegionSummary(
      sggCd: sggCd,
      name: '$sido $sgg',
      sidoName: sido,
      sggName: sgg,
      records: 10,
      located: 10,
      refreshedAt: '2026-09-08T00:00:00Z',
    );

    final index = RegionIndex([
      at('11680', '서울특별시', '강남구'),
      at('26110', '부산광역시', '중구'),
      at('31110', '울산광역시', '중구'),
      at('31140', '울산광역시', '남구'),
    ]);

    test('빈 검색어는 전부 보여준다', () {
      expect(index.bySidoMatching('').values.expand((v) => v), hasLength(4));
      expect(index.bySidoMatching('   ').values.expand((v) => v), hasLength(4));
    });

    test('시군구 이름으로 찾는다', () {
      final hit = index.bySidoMatching('강남').values.expand((v) => v);

      expect(hit.map((r) => r.sggCd), ['11680']);
    });

    // "울산"만 쳐서 그 시도 전체를 보는 것은 자연스러운 기대다.
    test('시도 이름으로도 찾는다', () {
      final hit = index.bySidoMatching('울산').values.expand((v) => v);

      expect(hit.map((r) => r.sggCd), containsAll(['31110', '31140']));
      expect(hit, hasLength(2));
    });

    // 여기가 핵심이다. 중구는 여럿이고, 어느 중구인지는 시도 이름으로만 갈린다.
    test('같은 이름이 여럿이면 시도별로 나눠 보여준다', () {
      final groups = index.bySidoMatching('중구');

      expect(groups.keys, containsAll(['부산광역시', '울산광역시']));
      expect(groups['부산광역시']!.single.sggCd, '26110');
      expect(groups['울산광역시']!.single.sggCd, '31110');
    });

    test('걸리는 것이 없으면 빈 묶음', () {
      expect(index.bySidoMatching('없는동네'), isEmpty);
    });
  });
}
