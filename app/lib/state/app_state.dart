import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/db/database.dart';
import '../data/sync/refresh_trigger.dart';
import '../data/sync/region_index.dart';
import '../data/sync/remote.dart';
import '../data/sync/sync_engine.dart';
import 'filters.dart';

/// 앱 전역 상태.
///
/// 만들어 넣는 것(`AppDatabase`·`SharedPreferences`)은 `main`에서 한 번 초기화해
/// override로 꽂는다. 프로바이더를 비동기로 만들면 모든 화면이 로딩 상태를
/// 다루게 되는데, 그 로딩은 앱 수명에 딱 한 번뿐이라 값어치가 없다.

final configProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('main에서 override한다'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('main에서 override한다'),
);

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main에서 override한다'),
);

final remoteProvider = Provider<RemoteSource>(
  (ref) => HttpRemote(ref.watch(configProvider).dataBaseUrl),
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(ref.watch(databaseProvider), ref.watch(remoteProvider)),
);

final refreshTriggerProvider = Provider<RefreshTrigger>(
  (ref) => RefreshTrigger(ref.watch(configProvider).workerBaseUrl),
);

// ---------------------------------------------------------------- 지역 색인

/// 색인은 **마지막으로 성공한 것을 계속 들고 있는다.**
///
/// 못 받았다고 비우면 오프라인에서 지역 이름조차 못 보여준다. 이미 받아 둔
/// 데이터는 그대로 있는데 화면만 빈 것은 사용자에게 "데이터가 사라졌다"로 읽힌다(FR-7).
class RegionIndexController extends AsyncNotifier<RegionIndex> {
  static const _cacheKey = 'regionIndex.cache';

  @override
  Future<RegionIndex> build() async {
    final cached = _readCache();
    final loaded = await RegionIndexLoader(ref.read(remoteProvider)).load();
    if (loaded == null) return cached ?? RegionIndex.empty;
    await _writeCache(loaded);
    return loaded;
  }

  Future<void> reload() async {
    final loaded = await RegionIndexLoader(ref.read(remoteProvider)).load();
    if (loaded == null) return; // 실패는 조용히 넘긴다. 들고 있던 것이 그대로 낫다
    await _writeCache(loaded);
    state = AsyncData(loaded);
  }

  RegionIndex? _readCache() {
    final raw = ref.read(prefsProvider).getString(_cacheKey);
    if (raw == null) return null;
    return RegionIndexLoader.decode(raw);
  }

  Future<void> _writeCache(RegionIndex index) => ref
      .read(prefsProvider)
      .setString(_cacheKey, RegionIndexLoader.encode(index));
}

final regionIndexProvider =
    AsyncNotifierProvider<RegionIndexController, RegionIndex>(
      RegionIndexController.new,
    );

// ---------------------------------------------------------------- 선택 지역

/// 마지막으로 보던 지역과 카메라를 기억한다 (FR-1 · T5.9).
class CameraState {
  const CameraState({required this.lat, required this.lng, required this.zoom});

  final double lat;
  final double lng;
  final double zoom;
}

class SelectedRegion extends Notifier<String?> {
  static const _key = 'region.selected';

  @override
  String? build() => ref.read(prefsProvider).getString(_key);

  /// 지역을 바꾼다. **같은 지역이면 아무것도 하지 않는다** —
  /// 지도를 조금 움직일 때마다 같은 값을 다시 넣으면 화면이 계속 다시 그려진다.
  void select(String? sggCd) {
    if (sggCd == state) return;
    state = sggCd;
    final prefs = ref.read(prefsProvider);
    if (sggCd == null) {
      prefs.remove(_key);
    } else {
      prefs.setString(_key, sggCd);
    }
  }
}

final selectedRegionProvider = NotifierProvider<SelectedRegion, String?>(
  SelectedRegion.new,
);

class LastCamera extends Notifier<CameraState?> {
  static const _key = 'camera.last';

  @override
  CameraState? build() {
    final raw = ref.read(prefsProvider).getStringList(_key);
    if (raw == null || raw.length != 3) return null;
    final values = raw.map(double.tryParse).toList();
    if (values.any((v) => v == null)) return null;
    return CameraState(lat: values[0]!, lng: values[1]!, zoom: values[2]!);
  }

  void remember(CameraState camera) {
    state = camera;
    ref.read(prefsProvider).setStringList(_key, [
      camera.lat.toString(),
      camera.lng.toString(),
      camera.zoom.toString(),
    ]);
  }
}

final lastCameraProvider = NotifierProvider<LastCamera, CameraState?>(
  LastCamera.new,
);

// ---------------------------------------------------------------- 필터

class FilterController extends Notifier<TxFilter> {
  @override
  TxFilter build() => const TxFilter();

  void set(TxFilter next) => state = next;
  void clear() => state = const TxFilter();
  void toggleDataset(String key) => state = state.toggleDataset(key);
  void toggleProperty(String property) =>
      state = state.toggleProperty(property);
  void setCancelled(bool include) =>
      state = state.copyWith(includeCancelled: include);
}

final filterProvider = NotifierProvider<FilterController, TxFilter>(
  FilterController.new,
);

// ---------------------------------------------------------------- 동기화

class SyncState {
  const SyncState({
    this.running = false,
    this.last,
    this.message,
    this.triggered,
    this.refreshedAt,
  });

  final bool running;
  final SyncStatus? last;
  final String? message;
  final TriggerResult? triggered;

  /// 서버가 데이터를 만든 시각. **상시 노출한다**(T5.8) —
  /// 실거래는 값이 시각에 매인 데이터라 "언제 것인지"를 감추면 안 된다
  final DateTime? refreshedAt;

  /// 화면에 띄울 만한 문제가 있는가. 조용한 실패를 만들지 않는다
  bool get hasProblem =>
      last == SyncStatus.offline || last == SyncStatus.rejected;

  SyncState copyWith({
    bool? running,
    SyncStatus? last,
    String? message,
    TriggerResult? triggered,
    DateTime? refreshedAt,
  }) => SyncState(
    running: running ?? this.running,
    last: last ?? this.last,
    message: message ?? this.message,
    triggered: triggered ?? this.triggered,
    refreshedAt: refreshedAt ?? this.refreshedAt,
  );
}

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  /// 지역을 동기화하고, 데이터가 낡았으면 서버에 갱신을 **던져만 둔다**.
  ///
  /// 트리거 응답을 기다려 화면을 막지 않는다. 지금 있는 데이터로 그리는 것이
  /// 먼저고, 새 데이터는 다음 진입에서 붙는다(FR-4 · FR-5).
  Future<void> syncRegion(String sggCd, {bool trigger = true}) async {
    if (state.running) return;
    state = state.copyWith(running: true);

    final outcome = await ref.read(syncEngineProvider).sync(sggCd);
    final manifest = outcome.manifest;

    state = SyncState(
      running: false,
      last: outcome.status,
      message: outcome.message,
      refreshedAt: manifest?.refreshedAt ?? state.refreshedAt,
      triggered: state.triggered,
    );

    if (!trigger || manifest == null) return;
    if (!manifest.isStale(DateTime.now().toUtc())) return;

    final result = await ref.read(refreshTriggerProvider).request(sggCd);
    state = state.copyWith(triggered: result);
  }
}

final syncProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);
