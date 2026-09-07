import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config.dart';
import 'data/db/database.dart';
import 'state/app_state.dart';

/// 어디서도 잡지 못한 예외를 남긴다.
///
/// 동기화·색인처럼 손으로 막아 둔 경로 **바깥**에서 터지는 예외는 지금까지
/// 아무 흔적도 남기지 않았다. 이 앱이 겪은 결함 셋이 전부 "오류 없이 화면만
/// 비는" 형태였다는 것을 생각하면, 관측 수단이 없는 편이 더 위험하다.
///
/// 여기서 앱을 죽이지 않는다. 지도 한 겹이 실패해도 저장된 데이터는 그대로
/// 쓸 수 있어야 한다(FR-7).
void _catchEverything() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[RDM] 위젯 오류: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[RDM] 처리되지 않은 오류: $error');
    return true;
  };
}

/// 프레임 시간을 재서 로그에 낸다 (T6.4).
///
/// `dumpsys gfxinfo`는 Flutter를 못 본다 — HWUI 파이프라인 밖에서 그리기 때문에
/// 프레임 수가 늘 0으로 나온다. 그래서 프레임워크가 직접 주는 값을 쓴다.
///
/// **프로파일 빌드에서만 돈다.** 출시본에서 매 프레임 콜백을 도는 것은
/// 재려는 대상을 재는 행위가 바꾸는 쪽이다.
void _measureFrames() {
  if (!kProfileMode) return;

  final samples = <int>[];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      // 만드는 시간과 그리는 시간을 합친다. 사용자가 겪는 것은 둘의 합이다.
      samples.add(
        t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds,
      );
    }
    if (samples.length < 120) return;

    final sorted = [...samples]..sort();
    int at(double q) =>
        sorted[(sorted.length * q).floor().clamp(0, sorted.length - 1)];
    // 60Hz 기준 한 프레임은 16,667µs다. 넘으면 사용자가 끊김으로 느낀다.
    final janky = sorted.where((v) => v > 16667).length;
    debugPrint(
      '[RDM-frame] n=${sorted.length} '
      'p50=${(at(0.5) / 1000).toStringAsFixed(1)}ms '
      'p90=${(at(0.9) / 1000).toStringAsFixed(1)}ms '
      'p99=${(at(0.99) / 1000).toStringAsFixed(1)}ms '
      'jank=$janky (${(janky * 100 / sorted.length).toStringAsFixed(1)}%)',
    );
    samples.clear();
  });
}

/// 앱 진입점.
///
/// DB와 설정을 여기서 한 번 만들어 override로 꽂는다. 프로바이더를 비동기로
/// 만들면 모든 화면이 로딩 상태를 다뤄야 하는데, 그 로딩은 앱 수명에 딱 한 번이라
/// 값어치가 없다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _catchEverything();
  _measureFrames();

  final prefs = await SharedPreferences.getInstance();
  final database = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [
        configProvider.overrideWithValue(AppConfig.fromEnvironment),
        databaseProvider.overrideWithValue(database),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const RealDealMapApp(),
    ),
  );
}
