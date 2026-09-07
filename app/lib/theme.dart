/// 화면의 색과 글자.
///
/// 방향은 **신문 지면**이다. 실거래가는 값이 주인공인 데이터라, 카드에 균등하게
/// 담아 늘어놓으면 무엇이 중요한지 사라진다. 금액을 크게 쓰고 나머지를 눌러
/// 위계를 만든다. 지도는 배경이고 숫자가 전경이다.
///
/// 색은 장식이 아니라 뜻이다 — 해제된 거래는 붉게, 근사 좌표는 호박색으로.
/// 그 둘 말고는 색을 쓰지 않는다.
library;

import 'package:flutter/material.dart';

class Palette {
  const Palette._();

  static const paper = Color(0xFFFAF8F4);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF16130F);
  static const ink2 = Color(0xFF4A443C);
  static const ink3 = Color(0xFF7C7367);
  static const rule = Color(0xFFDDD6CA);

  /// 매매·강조
  static const accent = Color(0xFFC2410C);
  static const accentSoft = Color(0xFFFDECE2);

  /// 전월세
  static const slate = Color(0xFF1F3A5F);
  static const slateSoft = Color(0xFFE6EDF5);

  /// 해제된 거래
  static const danger = Color(0xFF9F1239);

  /// 근사 좌표 — 위치를 믿으면 안 된다는 뜻
  static const warn = Color(0xFFA16207);
  static const warnSoft = Color(0xFFFEF3C7);
}

/// 매물 유형별 색. 지도에서 유형을 색으로 구분한다.
const Map<String, Color> kPropertyColors = {
  'apartment': Palette.accent,
  'officetel': Palette.slate,
  'rowhouse': Color(0xFF3F6212),
  'detached': Color(0xFF7C2D12),
  'land': Color(0xFF6B21A8),
};

Color colorOfDataset(String datasetKey) =>
    kPropertyColors[datasetKey.split('/').first] ?? Palette.ink2;

ThemeData buildTheme() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: Palette.paper,
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.accent,
      secondary: Palette.slate,
      surface: Palette.surface,
      error: Palette.danger,
    ),
    dividerColor: Palette.rule,
    textTheme: base.textTheme
        .apply(bodyColor: Palette.ink, displayColor: Palette.ink)
        .copyWith(
          // 금액이 이 자리에 온다. 화면에서 가장 큰 글자여야 한다.
          headlineMedium: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.1,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
          labelSmall: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Palette.ink3,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.paper,
      foregroundColor: Palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Palette.surface,
      side: const BorderSide(color: Palette.rule),
      labelStyle: const TextStyle(fontSize: 13, color: Palette.ink2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

/// 섹션 제목. 대문자 자간을 벌려 본문과 확실히 구분한다.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}

/// 뜻이 있는 배지. 해제·근사처럼 사용자가 놓치면 안 되는 사실에만 쓴다.
///
/// Material의 `Badge`와 이름이 겹치므로 `Tag`로 부른다.
class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    required this.color,
    required this.background,
    super.key,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}
