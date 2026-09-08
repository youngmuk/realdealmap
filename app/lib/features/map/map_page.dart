import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../config.dart';
import '../../data/db/database.dart';
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
import 'style_watchdog.dart';

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

/// 탭 판정에 쓰는 레이어. 개수 라벨은 뺀다 — 글자만 스치듯 눌려도 열려야 하는 게
/// 아니라 그 아래 원이 열려야 한다.
const _hitLayers = [_pinLayer, _clusterLayer, _approxLayer];

class _MapPageState extends ConsumerState<MapPage> {
  ml.MapLibreMapController? _controller;
  bool _styleReady = false;
  Timer? _regionDebounce;
  Timer? _viewportDebounce;
  int _drawn = 0;

  /// 이미 스타일에 올린 아이콘 이름. 없으면 화면을 옮길 때마다 다시 그린다.
  final _icons = <String>{};

  /// 스타일을 세우는 중인가. 콜백이 겹쳐 들어오는 것을 막는다
  bool _styling = false;

  /// 뷰포트 갱신의 순번. 늦게 끝난 옛 요청이 새 결과를 덮어쓰지 못하게 한다
  int _viewportSeq = 0;

  /// 화면 안 거래가 상한에 걸려 잘렸는가
  bool _truncated = false;

  /// 화면 안에 실제로 있는 건수. 상한에 안 걸렸으면 [_drawn]과 같다.
  int _total = 0;

  /// 필터가 연속으로 바뀔 때(가격 슬라이더) 매번 다시 그리지 않는다
  Timer? _filterDebounce;

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
    setState(() {
      _mapGeneration++;
      _controller = null;
      _icons.clear();
    });
  }

  @override
  void dispose() {
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
    for (final id in [_clusterLayer, _pinLayer, _approxLayer]) {
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
        circleRadius: 6.5,
        circleColor: _colorExpression,
        circleOpacity: 0.9,
        circleStrokeWidth: 1.5,
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

    // **묶음 개수를 글자로 찍지 않는다.** 심볼 레이어의 textField는 글리프를
    // 요구하는데 지금 스타일(OSM 래스터)에는 glyphs 항목이 없다. 글리프 요청이
    // 빈 URL로 나가 실패하면 **그 소스의 레이어가 통째로 사라진다** — 오류 하나 없이
    // 지도만 비어 보였다 (logcat: Mbgl-HttpRequest 'Unable to parse resourceUrl').
    // 개수는 원 크기로 읽히게 두고, 글자는 글리프를 우리 R2에 올린 뒤에 붙인다.
    controller.onFeatureTapped.remove(_onFeatureTapped);
    controller.onFeatureTapped.add(_onFeatureTapped);
    _styleReady = true;
    // 한 번 살아났으면 다음 사고에는 다시 세 번의 기회를 준다.
    _watchdog.recovered();
    await _syncViewport();
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

    final region = index.at(
      idx.LatLng(camera.target.latitude, camera.target.longitude),
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
    if (_noCenterFor == null || _noCenterFor != ref.read(selectedRegionProvider)) {
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
          .map((f) => (count: f.count, approximate: f.approximate)),
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

    // 묶음을 누르면 파고든다. 상세를 열 수 없으니 **아무 일도 안 일어나면
    // 고장으로 읽힌다** — 한 단계 확대해서 묶음이 풀리는 것을 보여준다.
    if (properties['cluster'] == 1) {
      await _zoomInto(properties);
      return;
    }

    final txId = properties['txId'];
    if (txId is! String) return;

    final tx = await ref.read(databaseProvider).byTxId(txId);
    if (tx == null || !mounted) return;
    await DetailSheet.show(context, tx);
    // 상세를 닫은 직후는 안전 전환 지점이다 (FR-6). 지도를 만지는 도중이
    // 아니라 손을 뗀 자리라서, 우발적 클릭을 유도하지 않는다.
    if (mounted) ref.adMoment(AdMoment.detailClosed);
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
          ),
        // 오른쪽 여백을 함께 잡아 글자 배율이 커져도 범례가 화면을 넘지 않는다.
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: _Legend(
              drawn: _drawn,
              total: _total,
              truncated: _truncated,
              // 고른 지역에 좌표가 없다는 고지가 떠 있을 때는 건수를 감춘다.
              // 그 숫자는 **지금 보이는 자리**의 것이라 맞는 말이지만,
              // 머리말의 지역과 나란히 놓이면 그 지역의 건수로 읽힌다.
              showCount: _noCenterFor == null,
            ),
          ),
        ),
      ],
    );
  }
}

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
          'count': f.count,
          if (f.isCluster) 'icon': clusterIconName(f.count, f.approximate),
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

/// 범례. 색이 뜻을 가지므로 뜻을 밝히지 않으면 장식이 된다.
/// 좌표가 아직 없는 지역이라고 말한다.
///
/// 적재 직후에는 흔한 상태다 — 거래는 다 받았는데 주소를 좌표로 바꾸는 일이
/// 아직 안 끝났다. 그 사정을 모르는 사용자에게는 "지도가 고장났다"로 보인다.
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
            '거래는 모두 받았습니다. 주소를 좌표로 바꾸는 일이 끝나면 지도에도 '
            '나옵니다. 그때까지는 목록에서 볼 수 있습니다.',
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

class _Legend extends StatelessWidget {
  const _Legend({
    required this.drawn,
    required this.total,
    required this.truncated,
    this.showCount = true,
  });

  final bool showCount;
  final int drawn;

  /// 화면 안에 실제로 있는 건수
  final int total;

  /// 상한에 걸려 일부만 그렸는가. **감추면 사용자는 그것이 전부인 줄 안다**
  final bool truncated;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Palette.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Palette.rule),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
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
        if (showCount) ...[
          const SizedBox(height: 5),
          Text(
            truncated
                ? '화면 안 ${formatCount(total)}건 중 ${formatCount(drawn)}건만 표시 '
                      '· 확대하면 전부 보입니다'
                : '화면 안 ${formatCount(drawn)}건 · 옅은 원은 법정동 근사',
            style: TextStyle(
              fontSize: 10.5,
              color: truncated ? Palette.warn : Palette.ink3,
            ),
          ),
        ],
      ],
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
      Text(label, style: const TextStyle(fontSize: 10.5, color: Palette.ink2)),
    ],
  );
}
