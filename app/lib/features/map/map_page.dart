import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../config.dart';
import '../../data/db/database.dart';
import '../../data/location.dart';
import '../../data/sync/region_index.dart' as idx;
import '../../format.dart';
import '../../state/ads.dart';
import '../../state/app_state.dart';
import '../../state/filters.dart';
import '../../theme.dart';
import '../ads/ad_policy.dart';
import '../detail/detail_sheet.dart';
import 'cluster.dart';
import 'cluster_icons.dart';
import 'locate.dart';
import 'map_focus.dart';
import 'stack_sheet.dart';
import 'style_watchdog.dart';

/// 상세창에서 데려올 때의 확대 수준.
///
/// 클러스터가 풀리는 지점([kClusterMaxZoom])과 같게 둔다. 그보다 낮으면 데려간
/// 자리에 묶음 하나만 보이고, 사용자는 자기가 누른 거래를 못 찾는다.
const double kFocusZoom = kClusterMaxZoom;

/// 현재 위치 버튼으로 갈 때의 확대 수준.
///
/// [kFocusZoom]보다 **두 단계 더 들어간다**(화면 폭 대략 600m → 150m).
/// 상세창에서 데려올 때와 목적이 다르기 때문이다 — 그쪽은 "이 거래가 어디쯤인지"를
/// 보여주는 것이라 주변이 함께 보여야 하지만, 여기는 **지금 서 있는 자리**다.
/// 정밀 위치의 오차가 10~20m 남짓이라 이 배율에서도 점이 제자리에 선다.
///
/// 대략 위치일 때는 여기까지 오지 않는다 — 뭉갠 좌표를 이 배율로 열면
/// 서 있지도 않은 골목이 자기 자리가 된다.
const double kMyLocationZoom = 18;

/// 지도 화면 (T5.4 · T5.5).
///
/// 마커를 위젯으로 만들지 않는다. 좌표를 GeoJSON 소스로 한 번 넘기면 네이티브
/// 쪽이 전부 그린다 — T1.3 실측에서 위젯 마커 방식은 마커 3,000개에서 잔행률
/// 21~41%였고 이 방식은 0~1%였다.
///
/// 묶는 것은 [clusterPins]가 한다. 네이티브 클러스터링을 쓰지 않는 이유는
/// 거기 적어 두었다 — 요약하면 갱신되는 소스와 클러스터되는 소스를 동시에
/// 가질 수 없고, **근사 좌표는 줌과 무관하게 묶어야 한다**는 규칙도
/// 네이티브 옵션으로는 표현할 수 없다.
class MapPage extends ConsumerStatefulWidget {
  const MapPage({this.onShowList, super.key});

  /// 목록 탭으로 넘어가는 길. 지도에 찍을 것이 없을 때 안내한다.
  final VoidCallback? onShowList;

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

const _sourceId = 'deals';
const _pinLayer = 'deal-pins';
const _approxLayer = 'deal-approx';
const _clusterLayer = 'deal-clusters';
const _labelLayer = 'deal-labels';

/// 탭 판정에 쓰는 레이어. 개수 라벨은 뺀다 — 글자만 스치듯 눌려도 열려야 하는 게
/// 아니라 그 아래 원이 열려야 한다.
const _hitLayers = [_pinLayer, _clusterLayer, _approxLayer];

class _MapPageState extends ConsumerState<MapPage> with WidgetsBindingObserver {
  ml.MapLibreMapController? _controller;
  bool _styleReady = false;
  Timer? _regionDebounce;
  Timer? _viewportDebounce;

  /// 실제로 지도에 그린 건수. [_total]과 다르면 상한에 걸린 것이다.
  int _drawn = 0;

  /// 이미 스타일에 올린 아이콘 이름. 없으면 화면을 옮길 때마다 다시 그린다.
  final _icons = <String>{};

  /// 스타일을 세우는 중인가. 콜백이 겹쳐 들어오는 것을 막는다
  bool _styling = false;

  /// 뷰포트 갱신의 순번. 늦게 끝난 옛 요청이 새 결과를 덮어쓰지 못하게 한다
  int _viewportSeq = 0;

  /// 화면 안 거래가 상한에 걸려 잘렸는가. 참이면 화면에 그렇다고 밝힌다.
  bool _truncated = false;

  /// 화면 안에 실제로 있는 건수. 상한에 안 걸렸으면 [_drawn]과 같다.
  int _total = 0;

  /// 필터가 연속으로 바뀔 때(가격 슬라이더) 매번 다시 그리지 않는다
  Timer? _filterDebounce;

  /// 위치를 찾는 중인가. 버튼을 연타해도 한 번만 돈다 —
  /// 위치 조회는 최대 8초가 걸릴 수 있고, 그동안 아무 표시가 없으면
  /// 사용자는 눌리지 않은 줄 알고 다시 누른다.
  bool _locating = false;

  /// 위치를 찾는 동안 앱이 화면 맨 앞을 내줬는가.
  ///
  /// 권한 창이 뜨면 플랫폼 뷰가 올라앉은 가상 디스플레이가 무너지는 일이
  /// 있다 — 실기기에서 정밀 위치를 허용한 직후 **지도만 하얗게 비었다**
  /// (logcat: `dequeueBuffer failed for display [flutter-vd#0] error -19`).
  /// 스타일은 이미 준비된 뒤라 [StyleWatchdog]은 이것을 못 잡는다.
  /// 앱을 껐다 켜면 돌아오므로, 같은 일을 뷰에만 해 준다.
  bool _lostFocusWhileLocating = false;

  /// 뷰를 새로 만든 뒤 데려갈 자리. 새 컨트롤러가 준비되면 그때 옮긴다.
  ml.LatLng? _pendingTarget;
  double? _pendingZoom;

  /// 저장된 카메라가 없던 첫 진입인가. 있으면 사용자가 보던 자리를 지킨다 —
  /// 위치를 잡았다고 보던 화면을 빼앗지 않는다.
  /// 중심점이 없어 옮겨 가지 못한 지역. 화면에 그렇다고 적는다.
  String? _noCenterFor;

  /// 옮기지 못했을 때 카메라가 남아 있던 자리.
  ///
  /// 여기서 움직이기 전까지 카메라는 **사용자의 뜻이 아니다.** 옮기지 못해
  /// 남아 있는 자리일 뿐이라, 그것으로 지역을 판정하면 사용자의 선택을 조용히
  /// 되돌린다. 실제로 좌표 없는 지역을 고른 뒤 앱을 다시 켜면 엉뚱한 지역이
  /// 열렸다 — 고를 때는 맞게 열렸으므로 한참 뒤에야 알게 된다.
  ml.LatLng? _noCenterAt;

  /// 처음 놓인 카메라 자리. 여기서 움직이기 전까지는 **지역을 추측하지 않는다**.
  ///
  /// 지역 판정은 카메라 중심이 어느 시군구에 드는지로 하는데, 첫 진입의 기본
  /// 좌표는 강남이다. 그대로 두면 부산에 있는 사용자에게도 강남구가 열린다 —
  /// 실거래가는 그 오해가 값비싼 데이터다.
  ml.LatLng? _initialTarget;

  /// 지도 위젯의 세대. 올리면 플랫폼 뷰가 통째로 새로 만들어진다.
  ///
  /// 규칙은 [StyleWatchdog]에 있다 — 왜 필요한지도 거기 적어 뒀다.
  int _mapGeneration = 0;

  late final _watchdog = StyleWatchdog(onStuck: _recreateMap);

  /// 지도가 멈췄다. 플랫폼 뷰를 통째로 새로 만든다.
  void _recreateMap() {
    if (!mounted || _styleReady) return;
    _remakeView();
  }

  /// 스타일이 준비됐든 아니든 뷰를 새로 만든다.
  ///
  /// 스타일은 멀쩡한데 **그리는 면이 죽는** 경우가 있어서 따로 둔다.
  /// [_recreateMap]의 `_styleReady` 가드는 그때 오히려 방해가 된다.
  void _remakeView() {
    if (!mounted) return;
    setState(() {
      _mapGeneration++;
      _controller = null;
      _styleReady = false;
      _icons.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 시군구 경계를 미리 읽어 둔다. 지도를 밀어 옆 구로 넘어가는 판정이
    // 카메라가 멈추는 **그 순간** 동기로 일어나서, 그때 가서 읽으면 늦는다.
    // 푸는 일은 다른 아이소레이트에서 하므로 여기서 화면이 멈추지 않는다.
    unawaited(ref.read(regionBoundariesProvider.future));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_locating && state != AppLifecycleState.resumed) {
      _lostFocusWhileLocating = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _regionDebounce?.cancel();
    _viewportDebounce?.cancel();
    _filterDebounce?.cancel();
    _watchdog.dispose();
    _controller?.onFeatureTapped.remove(_onFeatureTapped);
    super.dispose();
  }

  // ------------------------------------------------------------------ 카메라

  /// 스타일이 준비될 때마다 소스와 레이어를 **다시 세운다**.
  ///
  /// 이 콜백은 한 번만 오지 않는다. 스타일이 다시 로드되면(저메모리 복귀 등)
  /// 소스·레이어·이미지가 전부 사라진 채로 다시 불린다. 그래서 "이미 했으면
  /// 건너뛴다"는 가드는 틀렸다 — 그러면 다시 로드된 뒤 지도가 영영 비어 있다.
  /// 대신 남아 있을지 모르는 것을 지우고 새로 만든다. 두 경우 모두에서 맞는
  /// 유일한 길이고, 리스너 중복 등록(탭 한 번에 상세가 두 번 열림)도 막는다.
  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null || _styling) return;
    _styling = true;
    _styleReady = false;
    _watchdog.pause();
    try {
      await _rebuildStyle(controller);
    } finally {
      _styling = false;
      // 세우다 실패했으면 다시 지켜본다. 콜백은 이미 왔으므로 여기서 손을 놓으면
      // 다시 불러 줄 사람이 없다.
      if (!_styleReady) _watchdog.watch();
    }
  }

  Future<void> _rebuildStyle(ml.MapLibreMapController controller) async {
    for (final id in [_labelLayer, _clusterLayer, _pinLayer, _approxLayer]) {
      // 없으면 없는 대로다. 있는지 묻고 지우는 것보다 지우고 넘어가는 편이 짧다
      try {
        await controller.removeLayer(id);
      } on Exception catch (_) {}
    }
    try {
      await controller.removeSource(_sourceId);
    } on Exception catch (_) {}
    // 이미지도 스타일과 함께 사라진다. 올렸다고 기억하고 있으면 다시 올리지 않아
    // 묶음 마커가 통째로 안 그려진다
    _icons.clear();

    // **`addGeoJsonSource`여야 한다.** `addSource`로 만든 소스는
    // `setGeoJsonSource`로 갱신해도 렌더러에 닿지 않는다 (실기기 확인:
    // 같은 1,782개를 두 소스에 넣었을 때 이쪽만 그려졌다).
    await controller.addGeoJsonSource(_sourceId, _emptyCollection);

    // 근사 좌표를 맨 아래 깐다. 정확한 핀이 그 위에 오도록 —
    // 같은 자리에 겹칠 때 사용자가 집는 것은 정확한 쪽이어야 한다.
    await controller.addCircleLayer(
      _sourceId,
      _approxLayer,
      const ml.CircleLayerProperties(
        circleRadius: [
          'step',
          ['get', 'count'],
          9.0,
          10,
          13.0,
          50,
          18.0,
        ],
        circleColor: '#A16207',
        circleOpacity: 0.16,
        circleStrokeWidth: 1,
        circleStrokeColor: '#A16207',
        circleStrokeOpacity: 0.55,
      ),
      filter: const [
        'all',
        [
          '==',
          ['get', 'approx'],
          1,
        ],
        [
          '==',
          ['get', 'cluster'],
          0,
        ],
      ],
    );

    await controller.addCircleLayer(
      _sourceId,
      _pinLayer,
      ml.CircleLayerProperties(
        // 6.5에서 1.5배. 실기기에서 너무 작아 눌러야 할 것으로 안 보였다.
        circleRadius: 9.75,
        circleColor: _colorExpression,
        circleOpacity: 0.9,
        circleStrokeWidth: 2,
        circleStrokeColor: '#FFFFFF',
      ),
      filter: const [
        'all',
        [
          '==',
          ['get', 'approx'],
          0,
        ],
        [
          '==',
          ['get', 'cluster'],
          0,
        ],
      ],
    );

    // 묶음은 원이 아니라 **이미지**로 그린다. 개수를 원 안에 새겨야 하는데 글자
    // 레이어는 글리프를 요구하고, 글리프가 없으면 이 소스의 레이어가 통째로
    // 사라진다 (cluster_icons.dart에 적어 두었다). 아이콘은 글리프를 타지 않는다.
    await controller.addSymbolLayer(
      _sourceId,
      _clusterLayer,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      filter: const [
        '==',
        ['get', 'cluster'],
        1,
      ],
    );

    // 점 아래에 건물 이름을 찍는다.
    //
    // **한때 글자를 못 썼다.** 래스터 스타일에는 `glyphs` 항목이 없어 글리프
    // 요청이 빈 URL로 나갔고, 실패하면 그 소스의 레이어가 통째로 사라졌다 —
    // 오류 하나 없이 지도만 비어 보였다. 지금 스타일은 PMTiles라 R2에 구워 올린
    // Noto Sans KR을 가리키고, 한글 구간이 실제로 내려오는 것을 확인했다.
    // 묶음 개수는 여전히 아이콘에 그려 넣는다 — 그쪽은 이미 되고 있고,
    // 이름과 숫자를 한 레이어에 얹으면 둘이 서로를 밀어낸다.
    //
    // 그래도 **실패가 나머지를 무너뜨리지는 않게 한다.** 이 레이어가 없으면
    // 이름만 없고, 이 레이어 때문에 세우기가 중단되면 지도가 통째로 빈다.
    try {
      await controller.addSymbolLayer(
        _sourceId,
        _labelLayer,
        const ml.SymbolLayerProperties(
          textField: ['get', 'label'],
          // 글꼴 이름은 R2에 올린 폴더 이름 그대로여야 한다. 표현식이 아니라
          // 문자열 목록이라야 네이티브가 읽는다.
          textFont: ['NotoSansKR-Medium'],
          textSize: 22,
          textAnchor: 'top',
          // 점 아래로 내린다. **묶음 크기를 따라간다.**
          //
          // 한 값으로 두면 안 된다. 아이콘 반지름이 건수에 따라 9~21px로
          // 변하는데(cluster_icons.dart), 작은 점에 맞추면 큰 묶음이 글자를
          // 깔고 앉고 큰 묶음에 맞추면 낱개 점이 글자와 동떨어진다.
          // 실기기에서 앞엣것을 봤다 — 글자가 마커 위에 겹쳐 둘 다 안 읽혔다.
          //
          // em 단위라 글자 크기 22를 곱한 값이 실제 간격이다: 16 · 19 · 23 · 27px.
          textOffset: [
            0,
            [
              'step',
              ['get', 'count'],
              0.72,
              10,
              0.85,
              40,
              1.05,
              120,
              1.25,
            ],
          ],
          textColor: '#2B2721',
          textHaloColor: '#FFFFFF',
          // 글자가 커진 만큼 테두리도 키운다. 얇으면 지도 선 위에서 글자가 갈린다.
          textHaloWidth: 2,
          // **겹치면 지운다.** 아파트 단지처럼 이름이 몰린 곳에서 전부 그리면
          // 글자끼리 포개져 어느 것도 못 읽는다. 큰 묶음을 먼저 놓아
          // 남는 자리를 거래가 많은 쪽이 갖게 한다.
          textAllowOverlap: false,
          textPadding: 4,
          symbolSortKey: [
            '-',
            0,
            ['get', 'count'],
          ],
        ),
        // 낱개가 드러나기 시작하는 배율부터다. 그보다 낮으면 격자 묶음뿐이라
        // 이름을 붙일 수 있는 점이 거의 없고, 있어도 서로 밀어낸다.
        minzoom: 15,
        filter: const ['has', 'label'],
        // 글자는 탭을 받지 않는다. 눌러야 하는 것은 그 위의 점이다.
        enableInteraction: false,
      );
    } on Exception catch (_) {}

    controller.onFeatureTapped.remove(_onFeatureTapped);
    controller.onFeatureTapped.add(_onFeatureTapped);
    _styleReady = true;
    // 한 번 살아났으면 다음 사고에는 다시 세 번의 기회를 준다.
    _watchdog.recovered();
    await _syncViewport();

    // 뷰를 새로 만드느라 미뤄 둔 자리가 있으면 이제 간다. 여기서 하지 않으면
    // 사용자는 버튼을 눌렀는데 지도가 처음 자리에 그대로 있는 것을 본다.
    final target = _pendingTarget;
    final zoom = _pendingZoom;
    if (target != null && zoom != null) {
      _pendingTarget = null;
      _pendingZoom = null;
      await controller.animateCamera(
        ml.CameraUpdate.newLatLngZoom(target, zoom),
      );
    }
  }

  void _onCameraIdle() {
    // 움직이는 동안 판정하면 한 번의 드래그가 수십 번의 지역 전환이 된다.
    _regionDebounce?.cancel();
    _regionDebounce = Timer(kRegionDebounce, _detectRegion);

    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(kViewportDebounce, () => _syncViewport());
  }

  Future<void> _detectRegion() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final camera = controller.cameraPosition;
    // 아직 아무도 지도를 건드리지 않았고 지역도 정해지지 않았다면, 기본 좌표가
    // 어디를 가리키든 그것은 사용자의 위치가 아니다. 위치나 직접 선택을 기다린다.
    if (ref.read(selectedRegionProvider) == null &&
        camera != null &&
        _isInitialTarget(camera.target)) {
      return;
    }
    if (camera != null) {
      ref
          .read(lastCameraProvider.notifier)
          .remember(
            CameraState(
              lat: camera.target.latitude,
              lng: camera.target.longitude,
              zoom: camera.zoom,
            ),
          );
    }

    final index = ref.read(regionIndexProvider).value;
    if (index == null || camera == null) return;
    if (!_cameraSpeaksForUser(camera)) return;

    // 아직 안 읽혔으면 null이고, 그때는 경계상자로 떨어진다. 카메라가 멈출
    // 때마다 불리는 자리라 여기서 기다릴 수는 없다 &mdash; 첫 몇 초 동안만
    // 예전만큼 맞고, 그 뒤로는 진짜 경계로 판정한다.
    final region = index.at(
      idx.LatLng(camera.target.latitude, camera.target.longitude),
      ref.read(regionBoundariesProvider).value,
    );
    // 담는 지역이 없으면 선택을 지우지 않는다. 배포되지 않은 지역 위를 잠깐
    // 지나갔다고 보던 데이터를 버리면 화면이 깜빡이기만 한다.
    if (region == null) return;
    if (region.sggCd == ref.read(selectedRegionProvider)) return;

    ref
        .read(selectedRegionProvider.notifier)
        .select(region.sggCd, name: region.displayName);
    unawaited(ref.read(syncProvider.notifier).syncRegion(region.sggCd));
  }

  /// 지금 카메라 자리를 사용자의 뜻으로 읽어도 되는가.
  ///
  /// 고른 지역에 좌표가 없어 옮기지 못했다면, 카메라는 남의 동네에 그대로 있다.
  /// 그 자리로 지역을 판정하면 **사용자가 고른 지역을 조용히 되돌린다.**
  /// 사용자가 직접 밀어 움직였다면 그때부터는 다시 그의 뜻이다.
  bool _cameraSpeaksForUser(ml.CameraPosition camera) {
    if (_noCenterFor == null ||
        _noCenterFor != ref.read(selectedRegionProvider)) {
      return true;
    }
    final anchor = _noCenterAt;
    if (anchor == null) return false;

    final moved =
        (camera.target.latitude - anchor.latitude).abs() >= 0.0005 ||
        (camera.target.longitude - anchor.longitude).abs() >= 0.0005;
    if (!moved) return false;

    // 스스로 밀었다. 고지는 더 이상 지금 화면을 설명하지 않는다.
    if (mounted) {
      setState(() {
        _noCenterFor = null;
        _noCenterAt = null;
      });
    }
    return true;
  }

  /// 카메라가 처음 놓인 자리에서 사실상 그대로인가.
  ///
  /// 지도는 미세하게 흔들리므로 정확히 같기를 요구하면 안 된다. 사람이 밀면
  /// 이보다 훨씬 크게 움직인다.
  bool _isInitialTarget(ml.LatLng target) {
    final start = _initialTarget;
    if (start == null) return false;
    return (target.latitude - start.latitude).abs() < 0.0005 &&
        (target.longitude - start.longitude).abs() < 0.0005;
  }

  /// 화면에 보이는 사각형 안의 거래를 다시 뽑아 묶고 소스에 넣는다.
  Future<void> _syncViewport() async {
    final controller = _controller;
    if (controller == null || !_styleReady || !mounted) return;

    // 카메라 정지·필터 변경·동기화 완료가 각각 이 함수를 부른다. 겹쳤을 때
    // **늦게 끝난 옛 요청이 새 결과를 덮어쓰면** 사용자는 방금 바꾼 필터가
    // 적용되지 않은 화면을 본다. 순번을 들고 가서 뒤처진 것은 버린다.
    final seq = ++_viewportSeq;

    final bounds = await controller.getVisibleRegion();
    final zoom = controller.cameraPosition?.zoom ?? 13.5;
    final filter = ref.read(filterProvider);
    final sggCd = ref.read(selectedRegionProvider);

    // 가장자리를 조금 넓게 잡는다. 화면 밖에서 들어오는 마커가 딱 맞춰 나타나면
    // 스크롤할 때마다 가장자리가 비어 보인다.
    final padLat =
        (bounds.northeast.latitude - bounds.southwest.latitude) * 0.15;
    final padLng =
        (bounds.northeast.longitude - bounds.southwest.longitude) * 0.15;

    final pins = await ref
        .read(databaseProvider)
        .pinsInBounds(
          // 고른 지역으로 묶는다. 좌표가 없는 지역은 카메라가 안 움직여
          // 이전 지역 위에 머무는데, 묶지 않으면 그 지역 마커가 그대로 찍힌다.
          sggCd: sggCd,
          south: bounds.southwest.latitude - padLat,
          north: bounds.northeast.latitude + padLat,
          west: bounds.southwest.longitude - padLng,
          east: bounds.northeast.longitude + padLng,
          datasetKeys: filter.datasetKeysOrNull,
          includeCancelled: filter.includeCancelled,
          minAmount: filter.minAmount,
          maxAmount: filter.maxAmount,
          months: filter.months,
        );

    if (!mounted) return;
    final clustered = clusterPins(pins, zoom);
    // 아이콘을 먼저 올린다. 소스가 참조하는 이미지가 아직 없으면 그 피처는 안 그려진다.
    await ensureClusterIcons(
      controller,
      clustered
          .where((f) => f.isCluster)
          .map(
            (f) => (
              count: f.count,
              approximate: f.approximate,
              sameSpot: f.sameSpot,
            ),
          ),
      _icons,
    );
    if (!mounted || seq != _viewportSeq) return;
    await controller.setGeoJsonSource(_sourceId, _toCollection(clustered));

    final truncated = pins.length >= kPinLimit;
    // 상한에 걸렸을 때만 진짜 총계를 센다.
    //
    // 군집에 찍히는 숫자는 **불러온 것만** 센 값이다. 총계를 같이 말하지 않으면
    // 사용자는 그 숫자를 화면 안 전부로 읽는다. 안 걸렸을 때는 불러온 것이
    // 곧 전부라 셀 이유가 없다.
    final total = truncated
        ? await ref
              .read(databaseProvider)
              .countPinsInBounds(
                // 마커 조회와 **같은 조건**이라야 "N건 중 M건만 표시"가 참이 된다.
                sggCd: sggCd,
                south: bounds.southwest.latitude - padLat,
                north: bounds.northeast.latitude + padLat,
                west: bounds.southwest.longitude - padLng,
                east: bounds.northeast.longitude + padLng,
                datasetKeys: filter.datasetKeysOrNull,
                includeCancelled: filter.includeCancelled,
                minAmount: filter.minAmount,
                maxAmount: filter.maxAmount,
                months: filter.months,
              )
        : pins.length;

    if (mounted &&
        seq == _viewportSeq &&
        (pins.length != _drawn || truncated != _truncated || total != _total)) {
      setState(() {
        _drawn = pins.length;
        _truncated = truncated;
        _total = total;
      });
    }
  }

  /// 고른 지역으로 카메라를 옮긴다.
  ///
  /// 중심점은 그 지역 거래 좌표의 중앙값이라, 좌표가 하나도 안 붙은 지역에는
  /// 없다. 그럴 때 옮기지 않는 것까지는 맞지만 **가만히 있으면 안 된다** —
  /// 머리말은 담양군인데 화면에는 강남구가 그대로 남아, 사용자가 남의 동네
  /// 거래를 자기가 고른 지역으로 읽는다. 그 경우는 화면에 말로 밝힌다.
  Future<void> _focusSelectedRegion() async {
    final sggCd = ref.read(selectedRegionProvider);
    final controller = _controller;
    if (sggCd == null || controller == null) return;

    final center = ref.read(regionIndexProvider).value?.byCode(sggCd)?.center;
    if (center == null) {
      if (mounted) {
        setState(() {
          _noCenterFor = sggCd;
          _noCenterAt = controller.cameraPosition?.target;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _noCenterFor = null;
        _noCenterAt = null;
      });
    }
    await controller.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(center.lat, center.lng), 13.5),
    );
  }

  // ------------------------------------------------------------------ 탭

  /// 레이어 위의 탭은 [ml.MapLibreMapController.onFeatureTapped]로 온다.
  ///
  /// **`onMapClick`으로는 오지 않는다.** 상호작용이 켜진 레이어의 피처를 누르면
  /// 플랫폼이 그쪽으로 보내고 지도 클릭은 부르지 않는다 — 그래서 핀을 눌러도
  /// 상세가 열리지 않았다. 두 경로를 모두 같은 처리로 모은다.
  void _onFeatureTapped(
    math.Point<double> point,
    ml.LatLng _,
    String _,
    String _,
    ml.Annotation? _,
  ) => unawaited(_handleTapAt(point));

  Future<void> _onMapClick(math.Point<double> point, ml.LatLng _) =>
      _handleTapAt(point);

  Future<void> _handleTapAt(math.Point<double> point) async {
    final controller = _controller;
    if (controller == null) return;

    final features = await controller.queryRenderedFeatures(
      point,
      _hitLayers,
      null,
    );
    if (features.isEmpty || !mounted) return;

    final properties =
        (features.first as Map?)?['properties'] as Map<Object?, Object?>?;
    if (properties == null) return;

    if (properties['cluster'] == 1) {
      // 확대해도 갈라지지 않는 묶음은 **확대하면 안 된다.** 한 아파트 단지의
      // 거래는 좌표가 하나라, 파고들기를 반복해도 같은 묶음만 다시 나온다 —
      // 사용자에게는 앱이 눌러도 반응하지 않는 것으로 보인다. 목록을 연다.
      if (properties['stack'] == 1) {
        await _openStack(properties);
      } else {
        await _zoomInto(properties);
      }
      return;
    }

    final txId = properties['txId'];
    if (txId is! String) return;

    final tx = await ref.read(databaseProvider).byTxId(txId);
    if (tx == null || !mounted) return;
    await DetailSheet.show(context, tx, fromMap: true);
    // 상세를 닫은 직후는 안전 전환 지점이다 (FR-6). 지도를 만지는 도중이
    // 아니라 손을 뗀 자리라서, 우발적 클릭을 유도하지 않는다.
    if (mounted) ref.adMoment(AdMoment.detailClosed);
  }

  /// 한 자리에 겹친 거래를 목록으로 연다.
  ///
  /// 좌표로 되묻는다 — 묶을 때 쥐고 있던 것을 실어 나르지 않는다. 한 점에
  /// 130건이 넘는 곳이 있어서 피처 속성에 담으면 소스 전체가 무거워진다.
  Future<void> _openStack(Map<Object?, Object?> properties) async {
    final lat = (properties['lat'] as num?)?.toDouble();
    final lng = (properties['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final filter = ref.read(filterProvider);
    final pins = await ref
        .read(databaseProvider)
        .pinsInBounds(
          sggCd: ref.read(selectedRegionProvider),
          // 같은 점만 잡는 상자. R-트리 비교가 부동소수라 딱 맞추지 않고
          // 1e-7(약 1cm)만 벌린다 — 옆 건물이 딸려 올 거리가 아니다.
          south: lat - _kSpotEpsilon,
          north: lat + _kSpotEpsilon,
          west: lng - _kSpotEpsilon,
          east: lng + _kSpotEpsilon,
          // 지도에 그린 것과 **같은 조건**이라야 묶음의 숫자와 목록의 길이가 맞는다.
          datasetKeys: filter.datasetKeysOrNull,
          includeCancelled: filter.includeCancelled,
          minAmount: filter.minAmount,
          maxAmount: filter.maxAmount,
          months: filter.months,
        );
    if (!mounted || pins.isEmpty) return;

    final db = ref.read(databaseProvider);
    final rows = <TxRow>[];
    for (final pin in pins) {
      final tx = await db.byTxId(pin.txId);
      if (tx != null) rows.add(tx);
    }
    if (!mounted || rows.isEmpty) return;

    await StackSheet.show(context, rows);
    if (mounted) ref.adMoment(AdMoment.detailClosed);
  }

  /// 지금 있는 곳으로 데려간다.
  ///
  /// **시군구 중심점이 아니라 실제 좌표로 간다.** 지역만 맞추고 중심점을 열면
  /// 사용자는 몇 킬로미터 떨어진 곳을 "현재 위치"로 보게 된다.
  ///
  /// 다른 시군구에 와 있으면 지역도 함께 바꾼다. 지역을 안 바꾸면 카메라만
  /// 옮겨 가고 그 자리에 찍을 거래가 없다 — 마커 조회가 고른 지역으로
  /// 묶여 있기 때문이다(`_syncViewport`).
  Future<void> _goToMyLocation() async {
    if (_locating) return;
    _lostFocusWhileLocating = false;
    setState(() => _locating = true);
    try {
      final result = await locateHere(
        ref.read(locationProvider),
        ref.read(regionIndexProvider).value,
        await ref.read(regionBoundariesProvider.future),
      );
      if (!mounted) return;

      switch (result) {
        case LocateNoIndex():
          _say('지역 목록을 아직 받지 못했습니다. 잠시 뒤 다시 눌러 주세요.');
        case LocateFailed(:final outcome):
          final message = locationProblem(outcome);
          if (message != null) _say(message);
        case Located(:final lat, :final lng, :final region, :final precise):
          if (region != null &&
              region.sggCd != ref.read(selectedRegionProvider)) {
            ref
                .read(selectedRegionProvider.notifier)
                .select(region.sggCd, name: region.displayName);
            unawaited(ref.read(syncProvider.notifier).syncRegion(region.sggCd));
          }
          // **지역 이동 신호(regionFocusProvider)를 쓰지 않는다.** 그쪽은
          // 시군구 중심점으로 가는 길이라, 여기서 부르면 방금 맞춘 좌표를
          // 곧바로 덮어쓴다.
          // **정밀 위치가 아니면 깊이 들어가지 않는다.** 대략 위치는 1~2km
          // 격자로 뭉갠 값이라, 줌 16(화면 폭 수백 m)으로 열면 사용자는 자기가
          // 서 있지도 않은 골목을 자기 자리로 읽는다. 동 단위로만 보여준다.
          final target = ml.LatLng(lat, lng);
          final zoom = precise ? kMyLocationZoom : 13.5;

          // **할 말은 먼저 한다.** 아래에서 뷰를 새로 만드는 갈래는 그대로
          // 빠져나가므로, 뒤에 두면 그 경우에만 안내가 사라진다.
          if (region == null) {
            _say('현재 위치 근처에는 아직 배포된 지역이 없습니다.');
          } else if (!precise) {
            // 조용히 넘어가면 어긋난 자리를 정확한 자리로 읽는다.
            _say('대략적인 위치입니다. 정확한 위치를 허용하면 더 가깝게 갑니다.');
          }

          // 권한 창이 떴다 사라졌으면 그리는 면이 죽어 있을 수 있다.
          // 뷰를 새로 만들고, 옮기는 것은 새 스타일이 설 때까지 미룬다.
          if (_lostFocusWhileLocating) {
            _pendingTarget = target;
            _pendingZoom = zoom;
            _remakeView();
            return;
          }
          await _controller?.animateCamera(
            ml.CameraUpdate.newLatLngZoom(target, zoom),
          );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// 상세창이 지목한 좌표로 데려간다.
  ///
  /// 확대 수준을 [kFocusZoom]으로 **고정한다.** 지금 축척을 유지하면, 시·군 전체를
  /// 보고 있다가 누른 사람은 화면이 조금 움직이고 마는 것을 본다 — 데려갔다는
  /// 사실 자체가 전달되지 않는다.
  Future<void> _focusOn(MapFocus focus) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.animateCamera(
      ml.CameraUpdate.newLatLngZoom(
        ml.LatLng(focus.lat, focus.lng),
        kFocusZoom,
      ),
    );
  }

  Future<void> _zoomInto(Map<Object?, Object?> properties) async {
    final controller = _controller;
    final lat = properties['lat'];
    final lng = properties['lng'];
    if (controller == null || lat is! num || lng is! num) return;

    final zoom = controller.cameraPosition?.zoom ?? 13.5;
    await controller.animateCamera(
      ml.CameraUpdate.newLatLngZoom(
        ml.LatLng(lat.toDouble(), lng.toDouble()),
        // 근사 좌표는 아무리 확대해도 풀리지 않는다. 더 들어가 봐야 같은 점이라
        // 헛걸음을 시키지 않고 그 자리에 둔다.
        properties['approx'] == 1 ? zoom : math.min(zoom + 2, kClusterMaxZoom),
      ),
    );
  }

  // ------------------------------------------------------------------ 그리기

  @override
  Widget build(BuildContext context) {
    // 필터가 바뀌면 지도를 다시 칠한다. 목록과 지도가 같은 필터를 봐야
    // "목록에는 있는데 지도에 없다"가 좌표 때문임이 분명해진다.
    // 가격 슬라이더를 끌면 구간마다 새 필터가 나온다. 그때마다 DB를 다시 읽고
    // 소스를 갈아 끼우면 손가락보다 화면이 늦는다.
    // 상세창의 "지도에서 보기". 탭 전환은 앱 껍데기가 하고, 여기서는 카메라만
    // 옮긴다. 둘이 같은 요청을 각자 듣는다 — 콜백을 목록 → 상세로 꿰지 않는 이유는
    // `map_focus.dart`에 적어 두었다.
    ref.listen(mapFocusProvider, (_, next) {
      if (next != null) unawaited(_focusOn(next));
    });

    ref.listen(filterProvider, (_, _) {
      _filterDebounce?.cancel();
      _filterDebounce = Timer(kViewportDebounce, () => _syncViewport());
    });

    // 색인이 도착하면 그때 한 번 더 판정한다.
    //
    // 실기기에서 드러난 결함이다. 지역 판정은 카메라가 멈출 때만 도는데, 첫 실행에는
    // 지도가 먼저 자리를 잡고 색인이 나중에 온다. 그러면 판정 기회가 이미 지나가
    // 사용자는 **빈 지도를 보고 직접 지역을 골라야** 한다. 색인이 없어서 못 한 판정을
    // 색인이 생겼을 때 다시 하면 된다.
    ref.listen(regionIndexProvider, (_, next) {
      if (next.value != null) unawaited(_detectRegion());
    });

    // 동기화가 새 데이터를 넣으면 다시 칠한다.
    //
    // 이것도 실기기에서 드러났다. 지도는 카메라가 멈출 때만 다시 그리는데,
    // 첫 진입에서는 카메라가 이미 멈춘 뒤에 데이터가 들어온다. 그러면 동기화가
    // 성공하고 기준 시각까지 뜨는데 **마커만 0건**이다 — 사용자는 데이터가
    // 없다고 읽지, 화면이 안 갱신됐다고 읽지 않는다.
    // 사용자가 지역을 직접 고르면 그쪽으로 옮긴다.
    //
    // **지역이 바뀌었다는 것만으로는 옮기지 않는다.** 지도는 카메라가 멈출 때마다
    // 지금 보는 자리를 판정해 선택 지역을 바꾸는데, 그때도 옮기면 사용자가 지도를
    // 끌 수 없게 된다 — 미는 족족 되돌아온다. 그래서 "누가 바꿨는가"를 본다.
    ref.listen(regionFocusProvider, (_, _) => _focusSelectedRegion());

    ref.listen(syncProvider, (before, after) {
      if (before?.running == true && !after.running) unawaited(_syncViewport());
    });

    final camera = ref.read(lastCameraProvider);
    final style = ref.read(configProvider).resolvedMapStyle;
    _initialTarget ??= ml.LatLng(
      camera?.lat ?? 37.4979,
      camera?.lng ?? 127.0276,
    );

    return Stack(
      children: [
        ml.MapLibreMap(
          key: ValueKey(_mapGeneration),
          styleString: style,
          initialCameraPosition: ml.CameraPosition(
            target: ml.LatLng(camera?.lat ?? 37.4979, camera?.lng ?? 127.0276),
            zoom: camera?.zoom ?? 13.5,
          ),
          onMapCreated: (c) {
            _controller = c;
            _watchdog.watch();
          },
          onStyleLoadedCallback: _onStyleLoaded,
          onCameraIdle: _onCameraIdle,
          onMapClick: _onMapClick,
          myLocationEnabled: false,
          trackCameraPosition: true,
        ),
        // 고른 지역에 좌표가 하나도 없으면 그렇다고 말한다.
        //
        // 말하지 않으면 머리말은 담양군인데 화면에는 강남구가 그대로 남는다.
        // 사용자는 그 마커들을 자기가 고른 지역의 거래로 읽는다.
        if (_noCenterFor != null &&
            _noCenterFor == ref.watch(selectedRegionProvider))
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _NoCenterNotice(
              name:
                  ref
                      .watch(regionIndexProvider)
                      .value
                      ?.byCode(_noCenterFor!)
                      ?.displayName ??
                  _noCenterFor!,
              onList: widget.onShowList,
            ),
          )
        // 상한에 걸려 일부만 그렸으면 그렇다고 말한다.
        //
        // 군집에 찍히는 숫자는 **불러온 것만** 센 값이다. 강남구를 넓게 보면
        // 화면 안에 4만 건이 있어도 5,000건에서 끊긴다. 밝히지 않으면 사용자는
        // 그 숫자를 화면 안 전부로 읽는다 &mdash; 실거래가에서는 그 오해가 비싸다.
        //
        // 좌표가 없는 지역과 동시에 뜰 수는 없다(그때는 그릴 것이 0건이다).
        else if (_truncated)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _TruncatedNotice(drawn: _drawn, total: _total),
          ),
        // **화면 폭을 꽉 채워 바닥에 붙인다.**
        //
        // 떠 있는 상자였을 때는 그 아래로 지도가 비쳐, 범례와 아래 메뉴 사이에
        // 쓰이지도 않는 지도 띠가 남았다. 붙여 두면 그 띠가 지도로 돌아간다.
        // 참고용 고지는 설정 화면으로 옮겼으므로 더 이상 아래를 비워 둘 이유도 없다.
        //
        // 현재 위치 버튼은 범례 **바로 위**에 얹는다. 범례 높이는 글자 배율에
        // 따라 변해서 숫자로 띄울 수 없다 — 한 세로줄에 담아 서로를 밀게 한다.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _LocateButton(
                    busy: _locating,
                    onTap: () => unawaited(_goToMyLocation()),
                  ),
                ),
              ),
              const _Legend(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 같은 점을 되찾을 때 벌리는 여유. 약 1cm라 옆 건물이 딸려 오지 않는다.
const double _kSpotEpsilon = 1e-7;

/// 유형을 색으로 가른다. 표현식으로 넘기면 레이어 하나로 다섯 유형을 그린다.
const List<Object> _colorExpression = [
  'match',
  ['get', 'type'],
  'apartment',
  '#C2410C',
  'officetel',
  '#1F3A5F',
  'rowhouse',
  '#3F6212',
  'detached',
  '#7C2D12',
  'land',
  '#6B21A8',
  '#4A443C',
];

const Map<String, dynamic> _emptyCollection = {
  'type': 'FeatureCollection',
  'features': <dynamic>[],
};

/// 불리언 대신 0·1을 쓴다. 필터 표현식의 불리언 비교는 구현마다 편차가 있는데,
/// **틀리면 조용히 아무것도 안 그려진다** — 이미 한 번 그렇게 잃었다.
Map<String, dynamic> _toCollection(List<MapFeature> features) => {
  'type': 'FeatureCollection',
  'features': [
    for (final f in features)
      {
        'type': 'Feature',
        'properties': {
          if (f.txId != null) 'txId': f.txId,
          'type': f.propertyType,
          'approx': f.approximate ? 1 : 0,
          'cluster': f.isCluster ? 1 : 0,
          // 확대해도 갈라지지 않는 묶음인가. 파고들지 목록을 열지가 갈린다
          'stack': f.sameSpot ? 1 : 0,
          'count': f.count,
          // 없으면 아예 넣지 않는다. 라벨 레이어가 `has`로 거르므로
          // 빈 문자열을 넣으면 빈 글자를 그리려 든다.
          if (f.label != null) 'label': f.label,
          if (f.isCluster)
            'icon': clusterIconName(f.count, f.approximate, f.sameSpot),
          // 묶음을 눌렀을 때 파고들 자리. 렌더링된 피처에서 좌표를 되읽는 것보다
          // 여기 실어 두는 편이 확실하다
          'lat': f.lat,
          'lng': f.lng,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [f.lng, f.lat],
        },
      },
  ],
};

/// 좌표가 하나도 없는 지역이라고 말한다.
///
/// **드문 상태다.** 좌표는 도로명주소 파일에서 만들고 전국 99.5%에 붙는다.
/// 그래도 이 고지를 남겨 두는 이유는, 좌표가 비는 일이 **조용히** 일어나기
/// 때문이다 — 사전이 아직 안 올라갔거나, 새로 생긴 시군구라 색인이 없거나,
/// 다시 굽기가 그 지역에 아직 안 닿았거나. 어느 쪽이든 사용자에게는
/// "지도가 고장났다"로 보인다. 거래 자체는 다 있고 목록에서 볼 수 있다.
/// 화면 안 거래가 상한에 걸려 일부만 그려졌다.
///
/// **작고 얇게 둔다.** 넓게 보면 늘 떠 있는 알림이라 큰 상자로 만들면 지도를
/// 가리고, 그러면 사용자는 알림이 아니라 방해로 읽는다. 실기기에서 처음 만든
/// 것(12.5)은 두 줄로 접히며 지도의 한 뼘을 덮었다.
///
/// 두 숫자를 다 적는 이유: 잘렸다는 사실만으로는 얼마나 잘렸는지 모른다.
/// 군집에 찍힌 숫자를 얼마나 깎아서 읽어야 하는지는 그 비율이 정한다.
class _TruncatedNotice extends StatelessWidget {
  const _TruncatedNotice({required this.drawn, required this.total});

  final int drawn;
  final int total;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Material(
      color: Palette.warnSoft,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '${_thousands(total)}건 중 ${_thousands(drawn)}건만 표시 · 확대하세요',
          style: const TextStyle(
            fontSize: 10,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: Palette.warn,
          ),
        ),
      ),
    ),
  );
}

/// 천 단위로 끊는다. 다섯 자리가 넘는 건수는 끊지 않으면 한눈에 안 읽힌다.
String _thousands(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class _NoCenterNotice extends StatelessWidget {
  const _NoCenterNotice({required this.name, required this.onList});
  final String name;
  final VoidCallback? onList;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.warnSoft,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${topic(name)} 아직 지도에 찍을 좌표가 없습니다',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Palette.warn,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            '거래는 모두 받았습니다. 이 지역만 위치를 만들지 못했습니다. '
            '목록에서는 전부 볼 수 있습니다.',
            style: TextStyle(fontSize: 12, height: 1.45, color: Palette.ink2),
          ),
          if (onList != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onList, child: const Text('목록으로')),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 색깔이 무엇을 뜻하는지만 말한다.
///
/// 건수 줄("화면 안 N건 중 M건만 표시")은 **일부러 뺐다.** 지도를 조금만 움직여도
/// 숫자가 바뀌어 눈에 계속 걸리는데, 사용자가 그것으로 하는 일이 없다.
///
/// **상한(5,000건)에 걸린 사실도 함께 사라졌다.** 그것은 대가다 — 화면 안에
/// 30,000건이 있어도 5,000개만 그려지고, 사용자는 그것이 전부인 줄 안다.
/// 다만 그 배율은 이미 점이 뭉개져 개별 거래를 읽을 수 없는 상태이고,
/// 확대하면 상한에서 벗어난다.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
    decoration: const BoxDecoration(
      color: Palette.surface,
      // 위쪽 선 하나만 남긴다. 화면 폭을 꽉 채우고 바닥에 붙었으므로
      // 나머지 세 변은 그릴 자리가 없다.
      border: Border(top: BorderSide(color: Palette.rule)),
    ),
    child: Column(
      // **stretch여야 한다.** start면 Wrap이 제 내용만큼만 넓어져
      // spaceBetween이 나눌 여백 자체가 없다 — 조용히 왼쪽에 몰린다.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 폭이 넓어졌으니 다섯 유형을 한 줄에 고루 편다. 글자 배율이 커져
        // 한 줄에 못 담기면 알아서 다음 줄로 넘어간다.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 10,
          runSpacing: 4,
          children: [
            for (final entry in kPropertyColors.entries)
              _Swatch(
                color: entry.value,
                label: kPropertyLabels[entry.key] ?? entry.key,
              ),
          ],
        ),
        // **갈색 표시가 무엇인지 말한다.**
        //
        // 건수 줄을 걷으면서 이 설명까지 함께 사라졌고, 그 뒤 "갈색 둥근
        // 사각형이 뭐냐"는 물음이 나왔다. 지도에만 있고 어디에도 설명이
        // 없는 기호는 사용자에게 그냥 얼룩이다.
        //
        // 건수와 달리 이 줄은 **지도를 움직여도 바뀌지 않는다.** 눈에 계속
        // 걸리던 것은 숫자가 시시각각 변하는 쪽이었지 설명이 아니었다.
        const SizedBox(height: 5),
        const Text(
          '옅은 갈색은 지번을 몰라 법정동 중심에 모은 것',
          // 7.35의 80%. 설명이지 읽히는 것이 목적이 아니라, 기호를 처음 본
          // 사람이 한 번 찾아 읽으면 되는 줄이다.
          style: TextStyle(fontSize: 5.88, color: Palette.warn),
        ),
      ],
    ),
  );
}

/// 지금 있는 곳으로 가는 버튼.
///
/// 찾는 동안 아이콘 대신 동그라미를 돌린다. 위치 조회는 실내에서 8초까지
/// 걸리는데, 그동안 아무 변화가 없으면 사용자는 눌리지 않은 줄 안다.
class _LocateButton extends StatelessWidget {
  const _LocateButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.surface,
    shape: const CircleBorder(side: BorderSide(color: Palette.rule)),
    elevation: 2,
    child: InkWell(
      onTap: busy ? null : onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location, size: 22, color: Palette.slate),
        ),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      // 10.5의 80%
      Text(label, style: const TextStyle(fontSize: 8.4, color: Palette.ink2)),
    ],
  );
}
