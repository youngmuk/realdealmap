import 'dart:ui';

import 'package:flutter/material.dart';
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

/// 앱 진입점.
///
/// DB와 설정을 여기서 한 번 만들어 override로 꽂는다. 프로바이더를 비동기로
/// 만들면 모든 화면이 로딩 상태를 다뤄야 하는데, 그 로딩은 앱 수명에 딱 한 번이라
/// 값어치가 없다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _catchEverything();

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
