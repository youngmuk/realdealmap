import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config.dart';
import 'data/db/database.dart';
import 'state/app_state.dart';

/// 앱 진입점.
///
/// DB와 설정을 여기서 한 번 만들어 override로 꽂는다. 프로바이더를 비동기로
/// 만들면 모든 화면이 로딩 상태를 다뤄야 하는데, 그 로딩은 앱 수명에 딱 한 번이라
/// 값어치가 없다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
