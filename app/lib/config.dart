/// 실행 환경 설정.
///
/// 값을 소스에 박지 않고 `--dart-define`으로 넣는다. 여기 있는 것은 **비밀이 아니다** —
/// 공개 버킷 주소와 Worker 주소다. 비밀(국토부 인증키·카카오 키·R2 자격증명)은
/// 앱에 넣지 않는다. 배포된 앱에서 값을 빼내는 것은 막을 수 없기 때문이다.
library;

/// 설정에서 빠진 것. 각각이 **출시를 막아야 하는** 사유다.
enum ConfigIssue {
  /// 데이터 주소가 없다. 어떤 지역도 받을 수 없다
  noData('데이터 주소가 없는 빌드입니다 (DATA_BASE_URL)'),

  /// 자체 배경지도가 없어 OSM으로 그린다.
  /// OSM 타일 서버의 이용 정책은 앱 트래픽을 허용하지 않는다 — 기능 문제가 아니라
  /// 남의 서버를 규정 밖으로 쓰는 문제라서, 안 보이면 그대로 출시된다.
  fallbackTiles('배경지도가 OSM 폴백입니다 (MAP_STYLE)');

  const ConfigIssue(this.message);
  final String message;
}

class AppConfig {
  const AppConfig({
    required this.dataBaseUrl,
    required this.workerBaseUrl,
    required this.mapStyle,
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
  );

  bool get hasData => dataBaseUrl.isNotEmpty;

  /// 이 빌드에서 빠진 것.
  ///
  /// 값을 빠뜨린 빌드는 **멀쩡해 보인다** — 지도는 OSM 폴백으로 그려지고 데이터만
  /// 조용히 비어 있어서, 화면만 봐서는 "아직 안 받았나 보다"와 구별되지 않는다.
  /// 실제로 그렇게 만든 릴리스 APK를 손에 쥐고도 지역 목록을 열어 보고서야 알았다.
  /// 그래서 빠진 것에 이름을 붙여 밖으로 낸다. 조용한 실패를 시끄럽게 만드는 것이
  /// 여기서 하는 일의 전부다.
  List<ConfigIssue> get issues => [
    if (!hasData) ConfigIssue.noData,
    if (mapStyle.isEmpty) ConfigIssue.fallbackTiles,
  ];

  /// 스토어에 올려도 되는 빌드인가.
  bool get isReleasable => issues.isEmpty;

  /// 실제로 쓸 지도 스타일.
  ///
  /// MAP_STYLE을 준 경우가 가장 세고, 없으면 OSM 폴백이다.
  /// **OSM 폴백은 개발용이다** — `issues`가 이 상태를 출시 불가로 잡는다.
  String get resolvedMapStyle =>
      mapStyle.isNotEmpty ? mapStyle : kDefaultMapStyle;
}

/// 폴백 타일. **개발용이다.**
///
/// OSM 타일 서버의 이용 정책은 앱 트래픽을 허용하지 않는다. MAP_STYLE을 주면
/// 그쪽을 쓰고, 없을 때만 여기로 떨어진다. 설정 없이도 화면이 뜨게 하려는 것이지
/// 이 상태로 출시하려는 것이 아니다.
///
/// **출시용 배경지도는 이제 있다** — PMTiles 한 벌을 R2에 얹고 MAP_STYLE로
/// 가리킨다. 파일 하나를 범위 요청으로 읽으므로 서버가 없고 호출당 비용도 없다.
/// 그래서 이 폴백에 닿는 것은 곧 **설정이 빠진 빌드**라는 뜻이고,
/// `tool/build-release.sh`가 그런 빌드를 거부한다. 화면에도 경고가 뜬다 —
/// 스크립트는 우회할 수 있어도 첫 화면은 우회할 수 없다.
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
