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

/// 글자 배율.
///
/// 실기기에서 너무 작아 2배로 올렸다. **크기를 위젯마다 손보지 않고 여기 한 곳에
/// 둔다** — 스무 군데에 흩어진 숫자는 다음에 조정할 때 반드시 몇 개가 빠진다.
/// 사용자의 시스템 글자 크기 설정에 곱해지므로 접근성 설정도 그대로 살아 있다.
const double kTextScale = 2.0;

/// 우리 배율과 시스템 설정을 곱한 값의 **상한**.
///
/// [kTextScale]은 시스템 설정에 곱해진다. 안드로이드의 가장 큰 글자 설정이
/// 2.0이므로 그대로 두면 4.0까지 간다. 그 배율에서는 금액 한 줄이 화면 폭을
/// 넘고 상태바의 고지가 잘린다 — **잘린 고지는 고지가 아니다.**
///
/// 3.0으로 끊는 것은 접근성을 깎는 것이 아니다. 우리 기본이 이미 2배라
/// 여기서의 3.0은 보통 앱의 3배 글자다. 시스템 설정 1.5배까지는 그대로
/// 살아 있고, 그 위는 읽히는 대신 잘리기 시작하는 구간이다.
const double kMaxTextScale = 3.0;

/// 시스템 글자 크기 위에 우리 배율을 얹되 [kMaxTextScale]에서 끊는다.
///
/// **앱 껍데기에서 한 번만 부른다.** 상세창은 이렇게 나온 값에 다시
/// [kDetailTextScale]을 곱한다 — 이미 끊긴 값에 1보다 작은 수를 곱하는 것이라
/// 상한을 넘길 수 없다. 그래서 그쪽에서 이 함수를 다시 부르면 안 된다.
/// 우리 배율이 두 번 곱해진다.
TextScaler appTextScaler(TextScaler system) =>
    TextScaler.linear((system.scale(1) * kTextScale).clamp(0.0, kMaxTextScale));

/// 상세 정보창만 [kTextScale]의 이 비율로 줄인다.
///
/// 상세는 항목이 스무 개 가까이 되는 표라, 지도·목록과 같은 배율이면 한 화면에
/// 서너 줄밖에 안 들어와 **비교가 안 된다**. 지도는 크게, 표는 조금 작게가 맞다.
/// 표의 값이 한 줄에 들어가는 지점이다. 실기기에서 0.8까지는 계약일·면적이
/// 두 줄로 접혔고, 0.72에서 접히지 않았다.
const double kDetailTextScale = 0.72;

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
          // 색을 명시한다. copyWith는 위의 apply(bodyColor:)를 덮어쓰기 때문에
          // 색을 빼면 기본값으로 떨어져 **제목이 본문보다 흐려진다** — 실기기에서
          // 건물 이름이 주소보다 옅게 나왔다.
          headlineMedium: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.1,
            color: Palette.ink,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: Palette.ink,
          ),
          // 색을 여기서도 빼먹으면 안 된다. 위 주석과 같은 함정이고, 실제로
          // 목록의 단지 이름이 배경과 구별되지 않을 만큼 옅게 나왔다.
          // 본문 기본값이라 색을 지정하지 않은 글자가 전부 여기로 떨어진다.
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Palette.ink,
          ),
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
