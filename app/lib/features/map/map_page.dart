import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../config.dart';
import '../../data/db/database.dart';
import '../../data/sync/region_index.dart' as idx;
import '../../state/app_state.dart';
import '../../state/filters.dart';
import '../../theme.dart';
import '../detail/detail_sheet.dart';
import 'cluster.dart';
import 'cluster_icons.dart';

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
  const MapPage({super.key});

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

  /// 필터가 연속으로 바뀔 때(가격 슬라이더) 매번 다시 그리지 않는다
  Timer? _filterDebounce;

  /// 저장된 카메라가 없던 첫 진입인가. 있으면 사용자가 보던 자리를 지킨다 —
  /// 위치를 잡았다고 보던 화면을 빼앗지 않는다.
  bool _placeOnFirstRegion = false;

  /// 처음 놓인 카메라 자리. 여기서 움직이기 전까지는 **지역을 추측하지 않는다**.
  ///
  /// 지역 판정은 카메라 중심이 어느 시군구에 드는지로 하는데, 첫 진입의 기본
  /// 좌표는 강남이다. 그대로 두면 부산에 있는 사용자에게도 강남구가 열린다 —
  /// 실거래가는 그 오해가 값비싼 데이터다.
  ml.LatLng? _initialTarget;

  @override
  void initState() {
    super.initState();
    _placeOnFirstRegion = ref.read(lastCameraProvider) == null;
  }

  @override
  void dispose() {
    _regionDebounce?.cancel();
    _viewportDebounce?.cancel();
    _filterDebounce?.cancel();
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
    try {
      await _rebuildStyle(controller);
    } finally {
      _styling = false;
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

    final region = index.at(
      idx.LatLng(camera.target.latitude, camera.target.longitude),
    );
    // 담는 지역이 없으면 선택을 지우지 않는다. 배포되지 않은 지역 위를 잠깐
    // 지나갔다고 보던 데이터를 버리면 화면이 깜빡이기만 한다.
    if (region == null) return;
    if (region.sggCd == ref.read(selectedRegionProvider)) return;

    ref.read(selectedRegionProvider.notifier).select(region.sggCd);
    unawaited(ref.read(syncProvider.notifier).syncRegion(region.sggCd));
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

    // 가장자리를 조금 넓게 잡는다. 화면 밖에서 들어오는 마커가 딱 맞춰 나타나면
    // 스크롤할 때마다 가장자리가 비어 보인다.
    final padLat =
        (bounds.northeast.latitude - bounds.southwest.latitude) * 0.15;
    final padLng =
        (bounds.northeast.longitude - bounds.southwest.longitude) * 0.15;

    final pins = await ref
        .read(databaseProvider)
        .pinsInBounds(
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
    if (mounted &&
        seq == _viewportSeq &&
        (pins.length != _drawn || truncated != _truncated)) {
      setState(() {
        _drawn = pins.length;
        _truncated = truncated;
      });
    }
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
    // 첫 진입에서 위치로 지역이 정해지면 그쪽으로 옮긴다.
    //
    // 딱 한 번만 한다. 지도를 움직이면 지역 판정이 다시 돌고, 그때마다 카메라를
    // 옮기면 **사용자가 지도를 끌 수 없게 된다** — 미는 족족 되돌아온다.
    ref.listen(selectedRegionProvider, (previous, next) {
      if (!_placeOnFirstRegion || previous != null || next == null) return;
      _placeOnFirstRegion = false;
      final center = ref.read(regionIndexProvider).value?.byCode(next)?.center;
      final controller = _controller;
      // 좌표가 하나도 안 붙은 지역은 중심점이 없다. 그런 곳으로 옮기면 바다
      // 한가운데를 보여주게 되므로 그냥 있던 자리에 둔다.
      if (center == null || controller == null) return;
      unawaited(
        controller.animateCamera(
          ml.CameraUpdate.newLatLngZoom(
            ml.LatLng(center.lat, center.lng),
            13.5,
          ),
        ),
      );
    });

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
          styleString: style,
          initialCameraPosition: ml.CameraPosition(
            target: ml.LatLng(camera?.lat ?? 37.4979, camera?.lng ?? 127.0276),
            zoom: camera?.zoom ?? 13.5,
          ),
          onMapCreated: (c) => _controller = c,
          onStyleLoadedCallback: _onStyleLoaded,
          onCameraIdle: _onCameraIdle,
          onMapClick: _onMapClick,
          myLocationEnabled: false,
          trackCameraPosition: true,
        ),
        // 오른쪽 여백을 함께 잡아 글자 배율이 커져도 범례가 화면을 넘지 않는다.
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: _Legend(drawn: _drawn, truncated: _truncated),
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
class _Legend extends StatelessWidget {
  const _Legend({required this.drawn, required this.truncated});
  final int drawn;

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
        const SizedBox(height: 5),
        Text(
          truncated
              ? '화면 안 $drawn건까지만 표시 · 확대하면 전부 보입니다'
              : '화면 안 $drawn건 · 옅은 원은 법정동 근사',
          style: TextStyle(
            fontSize: 10.5,
            color: truncated ? Palette.warn : Palette.ink3,
          ),
        ),
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
