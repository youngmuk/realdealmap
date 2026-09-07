import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/config.dart';

AppConfig config({String style = '', String vworld = ''}) => AppConfig(
  dataBaseUrl: '',
  workerBaseUrl: '',
  mapStyle: style,
  vworldKey: vworld,
);

void main() {
  group('지도 스타일 선택', () {
    test('직접 준 스타일이 가장 세다', () {
      expect(config(style: '{}', vworld: 'K').resolvedMapStyle, '{}');
    });

    test('VWorld 키가 있으면 VWorld를 쓴다', () {
      expect(config(vworld: 'K').resolvedMapStyle, contains('api.vworld.kr'));
    });

    // OSM 타일 서버의 이용 정책은 앱 트래픽을 허용하지 않는다. 개발용 폴백이다.
    test('둘 다 없으면 OSM으로 떨어진다', () {
      expect(config().resolvedMapStyle, contains('tile.openstreetmap.org'));
    });
  });

  group('VWorld 스타일', () {
    final style = jsonDecode(vworldStyle('TESTKEY')) as Map<String, dynamic>;
    final tiles = ((style['sources'] as Map)['vworld'] as Map)['tiles'] as List;

    test('스타일이 올바른 JSON이다', () {
      expect(style['version'], 8);
      expect(style['layers'], hasLength(1));
    });

    // 순서를 바꾸면 지도가 나오긴 하는데 위치가 틀린다. "안 나온다"보다 알아채기 어렵다.
    test('WMTS 경로가 z/y/x 순서다', () {
      expect(tiles.single, endsWith('/{z}/{y}/{x}.png'));
    });

    test('키가 경로에 들어간다', () {
      expect(tiles.single, contains('/1.0.0/TESTKEY/Base/'));
    });

    test('출처를 밝힌다', () {
      expect(
        ((style['sources'] as Map)['vworld'] as Map)['attribution'],
        contains('VWorld'),
      );
    });
  });
}
