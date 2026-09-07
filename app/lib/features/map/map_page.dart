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

/// 지도 화면 (T5.4 · T5.5).
///
/// 마커를 위젯으로 만들지 않는다. 좌표를 GeoJSON 소스로 한 번 넘기면 네이티브
/// 쪽이 전부 그린다 — T1.3 실측에서 위젯 마커 방식은 마커 3,000개에서 잔행률
/// 21~41%였고 이 방식은 0~1%였다.
///
/// **근사 좌표는 낱개로 그리지 않는다.** `partial`·`umd`는 법정동 중심점이라
/// 같은 동의 거래 수백 건이 한 점에 겹친다. 뭉쳐서 그리고, 색과 모양으로
/// "여기 어딘가"임을 알린다.
class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

const _sourceId = 'deals';
const _pinLayer = 'deal-pins';
const _approxLayer = 'deal-approx';
const _clusterLayer = 'deal-clusters';
const _clusterCountLayer = 'deal-cluster-count';

class _MapPageState extends ConsumerState<MapPage> {
  ml.MapLibreMapController? _controller;
  bool _styleReady = false;
  Timer? _regionDebounce;
  Timer? _viewportDebounce;
  int _drawn = 0;

  @override
  void dispose() {
    _regionDebounce?.cancel();
    _viewportDebounce?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ 카메라

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;

    await controller.addSource(
      _sourceId,
      ml.GeojsonSourceProperties(
        data: _emptyCollection,
        cluster: true,
        clusterRadius: 56,
        // 이 줌을 넘으면 뭉치지 않는다. 낱개를 봐야 하는 배율이다
        clusterMaxZoom: 15,
      ),
    );

    // 근사 좌표를 먼저 깐다. 정확한 핀이 그 위에 오도록 —
    // 같은 자리에 겹칠 때 사용자가 집는 것은 정확한 쪽이어야 한다.
    await controller.addCircleLayer(
      _sourceId,
      _approxLayer,
      const ml.CircleLayerProperties(
        circleRadius: 13,
        circleColor: '#A16207',
        circleOpacity: 0.16,
        circleStrokeWidth: 1,
        circleStrokeColor: '#A16207',
        circleStrokeOpacity: 0.5,
      ),
      filter: const [
        'all',
        [
          '!',
          ['has', 'point_count'],
        ],
        [
          '==',
          ['get', 'approx'],
          true,
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
          '!',
          ['has', 'point_count'],
        ],
        [
          '!=',
          ['get', 'approx'],
          true,
        ],
      ],
    );

    await controller.addCircleLayer(
      _sourceId,
      _clusterLayer,
      const ml.CircleLayerProperties(
        // 뭉친 개수에 따라 커진다. 크기가 곧 밀도라 한눈에 읽힌다
        circleRadius: [
          'step',
          ['get', 'point_count'],
          16.0,
          25,
          21.0,
          100,
          27.0,
        ],
        circleColor: '#16130F',
        circleOpacity: 0.85,
      ),
      filter: const ['has', 'point_count'],
    );

    await controller.addSymbolLayer(
      _sourceId,
      _clusterCountLayer,
      const ml.SymbolLayerProperties(
        textField: ['get', 'point_count_abbreviated'],
        textSize: 12,
        textColor: '#FFFFFF',
        textAllowOverlap: true,
      ),
      filter: const ['has', 'point_count'],
      enableInteraction: false,
    );

    _styleReady = true;
    await _syncViewport(immediate: true);
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

  /// 화면에 보이는 사각형 안의 거래를 다시 뽑아 소스에 넣는다.
  Future<void> _syncViewport({bool immediate = false}) async {
    final controller = _controller;
    if (controller == null || !_styleReady || !mounted) return;

    final bounds = await controller.getVisibleRegion();
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
        );

    if (!mounted) return;
    await controller.setGeoJsonSource(_sourceId, _toCollection(pins));
    if (mounted && pins.length != _drawn) setState(() => _drawn = pins.length);
  }

  // ------------------------------------------------------------------ 탭

  Future<void> _onMapClick(math.Point<double> point, ml.LatLng _) async {
    final controller = _controller;
    if (controller == null) return;

    final features = await controller.queryRenderedFeatures(point, const [
      _pinLayer,
      _approxLayer,
    ], null);
    if (features.isEmpty || !mounted) return;

    final properties =
        (features.first as Map?)?['properties'] as Map<Object?, Object?>?;
    final txId = properties?['txId'];
    if (txId is! String) return;

    final tx = await ref.read(databaseProvider).byTxId(txId);
    if (tx == null || !mounted) return;
    await DetailSheet.show(context, tx);
  }

  // ------------------------------------------------------------------ 그리기

  @override
  Widget build(BuildContext context) {
    // 필터가 바뀌면 지도를 다시 칠한다. 목록과 지도가 같은 필터를 봐야
    // "목록에는 있는데 지도에 없다"가 좌표 때문임이 분명해진다.
    ref.listen(filterProvider, (_, _) => unawaited(_syncViewport()));

    final camera = ref.read(lastCameraProvider);
    final style = ref.read(configProvider).resolvedMapStyle;

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
        Positioned(left: 12, bottom: 12, child: _Legend(drawn: _drawn)),
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

Map<String, dynamic> _toCollection(List<MapPin> pins) => {
  'type': 'FeatureCollection',
  'features': [
    for (final pin in pins)
      {
        'type': 'Feature',
        'properties': {
          'txId': pin.txId,
          'type': pin.datasetKey.split('/').first,
          'approx': pin.isApproximate,
          'cancelled': pin.cancelled,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [pin.lng, pin.lat],
        },
      },
  ],
};

/// 범례. 색이 뜻을 가지므로 뜻을 밝히지 않으면 장식이 된다.
class _Legend extends StatelessWidget {
  const _Legend({required this.drawn});
  final int drawn;

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
          '화면 안 $drawn건 · 옅은 원은 법정동 근사',
          style: const TextStyle(fontSize: 10.5, color: Palette.ink3),
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
