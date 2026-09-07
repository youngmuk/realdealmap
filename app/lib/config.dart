/// 실행 환경 설정.
///
/// 값을 소스에 박지 않고 `--dart-define`으로 넣는다. 여기 있는 것은 **비밀이 아니다** —
/// 공개 버킷 주소와 Worker 주소다. 비밀(국토부 인증키·카카오 키·R2 자격증명)은
/// 앱에 넣지 않는다. 배포된 앱에서 값을 빼내는 것은 막을 수 없기 때문이다.
library;

class AppConfig {
  const AppConfig({
    required this.dataBaseUrl,
    required this.workerBaseUrl,
    required this.mapStyle,
    required this.vworldKey,
  });

  /// R2 공개 버킷. 개발은 `r2.dev`, 출시 때 사용자 지정 도메인으로 바꾼다.
  ///
  /// `r2.dev`는 Cloudflare가 비프로덕션 용도로 명시했고 캐시·WAF가 없다.
  /// 스토어 출시 시점에 도메인을 붙이는 것이 유일한 실비다(연 $1~15).
  final String dataBaseUrl;

  /// 갱신 트리거를 받는 Worker. 데이터는 여기서 받지 않는다 —
  /// 서버를 한 겹 두면 무료 요청 한도가 곧 동시 사용자 수 상한이 된다(AD-1).
  final String workerBaseUrl;

  final String mapStyle;

  static const AppConfig fromEnvironment = AppConfig(
    dataBaseUrl: String.fromEnvironment('DATA_BASE_URL', defaultValue: ''),
    workerBaseUrl: String.fromEnvironment(
      'WORKER_BASE_URL',
      defaultValue: 'https://realdealmap-trigger.jsmgames.workers.dev',
    ),
    mapStyle: String.fromEnvironment('MAP_STYLE', defaultValue: ''),
    vworldKey: String.fromEnvironment('VWORLD_KEY', defaultValue: ''),
  );

  bool get hasData => dataBaseUrl.isNotEmpty;

  /// VWorld 배경지도 키.
  ///
  /// **이 키는 앱에 들어간다.** 타일 요청 URL에 실려 나가므로 숨길 방법이 없고,
  /// 어떤 타일 제공자를 쓰든 마찬가지다(카카오 JS 키도 같다). 그래서 서버 비밀과는
  /// 다르게 다룬다 — VWorld 쪽에서 앱/도메인을 등록해 사용처를 제한하는 것이
  /// 유일한 방어다. 국토부 인증키·R2 자격증명은 여전히 앱에 넣지 않는다.
  final String vworldKey;

  /// 실제로 쓸 지도 스타일.
  ///
  /// MAP_STYLE을 직접 준 경우가 가장 세고, 그다음이 VWorld, 마지막이 OSM이다.
  String get resolvedMapStyle {
    if (mapStyle.isNotEmpty) return mapStyle;
    if (vworldKey.isNotEmpty) return vworldStyle(vworldKey);
    return kDefaultMapStyle;
  }
}

/// VWorld 배경지도 스타일 (G1 이월 과제의 답).
///
/// WMTS 경로가 `{z}/{y}/{x}`다 — 흔한 `{z}/{x}/{y}`가 아니다. 순서를 바꾸면
/// 타일이 조용히 엉뚱한 자리에 붙어서, 지도가 나오긴 하는데 위치가 틀린다.
/// 그런 오류는 "안 나온다"보다 알아채기 어렵다.
///
/// 좌표계는 웹 메르카토르에 좌상단 원점(XYZ)이라 maplibre 기본값과 같다.
String vworldStyle(String apiKey) =>
    '''
{
  "version": 8,
  "sources": {
    "vworld": {
      "type": "raster",
      "tiles": ["https://api.vworld.kr/req/wmts/1.0.0/$apiKey/Base/{z}/{y}/{x}.png"],
      "tileSize": 256,
      "attribution": "© 국토교통부 공간정보 오픈플랫폼(VWorld)",
      "maxzoom": 18
    }
  },
  "layers": [
    { "id": "vworld", "type": "raster", "source": "vworld" }
  ]
}
''';

/// 폴백 타일. **개발용이다.**
///
/// OSM 타일 서버의 이용 정책은 앱 트래픽을 허용하지 않는다. VWorld 키가 있으면
/// 그쪽을 쓰고, 없을 때만 여기로 떨어진다. 키 없이도 화면이 뜨게 하려는 것이지
/// 이 상태로 출시하려는 것이 아니다.
const String kDefaultMapStyle = '''
{
  "version": 8,
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "© OpenStreetMap contributors",
      "maxzoom": 19
    }
  },
  "layers": [
    { "id": "osm", "type": "raster", "source": "osm" }
  ]
}
''';

/// 지도를 움직인 뒤 이만큼 조용해야 지역 판정을 다시 한다 (T5.5).
///
/// 움직이는 동안 판정하면 한 번의 드래그가 수십 번의 지역 전환이 된다.
/// 그때마다 동기화를 걸면 네트워크와 배터리를 태우고, 화면은 계속 깜빡인다.
const Duration kRegionDebounce = Duration(milliseconds: 400);

/// 지도가 멈춘 뒤 이만큼 지나면 화면 안의 마커를 다시 뽑는다.
///
/// 지역 판정보다 짧다. 같은 지역 안에서 움직이는 것은 DB 조회 한 번이라
/// 값이 싸고, 늦으면 빈 화면이 오래 남는다.
const Duration kViewportDebounce = Duration(milliseconds: 120);
