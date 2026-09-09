import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/theme.dart';

/// 테마가 글자를 보이게 하는가.
///
/// `TextTheme.apply(bodyColor:)`로 색을 깐 뒤 `copyWith`로 스타일을 갈아 끼우면
/// **색이 함께 지워진다.** 갈아 끼운 스타일에 색을 다시 적지 않으면 그 자리의
/// 글자가 배경과 거의 같은 색으로 나온다. 이 앱에서 두 번 일어났다 —
/// 상세창의 건물 이름, 그다음 목록의 단지 이름.
///
/// 색이 빠진 것은 화면을 세워 봐도 "글자가 있다"로 통과한다. 그래서 여기서 잰다.
void main() {
  test('모든 글자 스타일에 색이 있다', () {
    final t = buildTheme().textTheme;

    final styles = <String, TextStyle?>{
      'displayLarge': t.displayLarge,
      'displayMedium': t.displayMedium,
      'displaySmall': t.displaySmall,
      'headlineLarge': t.headlineLarge,
      'headlineMedium': t.headlineMedium,
      'headlineSmall': t.headlineSmall,
      'titleLarge': t.titleLarge,
      'titleMedium': t.titleMedium,
      'titleSmall': t.titleSmall,
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'bodySmall': t.bodySmall,
      'labelLarge': t.labelLarge,
      'labelMedium': t.labelMedium,
      'labelSmall': t.labelSmall,
    };

    for (final entry in styles.entries) {
      expect(
        entry.value?.color,
        isNotNull,
        reason: '${entry.key}에 색이 없다. copyWith로 갈아 끼울 때 color를 다시 적어야 한다',
      );
    }
  });

  // 배경과 구별되지 않으면 색이 있어도 없는 것과 같다.
  test('본문 색이 배경과 뚜렷이 다르다', () {
    final body = buildTheme().textTheme.bodyMedium!.color!;

    expect(body, Palette.ink);
    expect(
      (body.r - Palette.paper.r).abs() +
          (body.g - Palette.paper.g).abs() +
          (body.b - Palette.paper.b).abs(),
      greaterThan(1.0),
      reason: '본문이 배경에 묻힌다',
    );
  });

  // 우리 배율 2배 위에 시스템 설정이 그대로 곱해지면 4배까지 간다.
  // 그 배율에서는 금액 줄이 폭을 넘고 상태바 고지가 잘린다.
  group('글자 배율 상한', () {
    test('시스템 기본에서는 우리 배율 그대로다', () {
      expect(appTextScaler(TextScaler.noScaling).scale(10), 10 * kTextScale);
    });

    test('시스템 설정을 그대로 태운다 — 상한 아래에서는', () {
      expect(appTextScaler(const TextScaler.linear(1.4)).scale(10), 10 * 2.8);
    });

    test('가장 큰 시스템 설정에서도 상한에서 끊는다', () {
      // 안드로이드의 가장 큰 설정(2.0). 끊지 않으면 4.0이다.
      expect(
        appTextScaler(const TextScaler.linear(2.0)).scale(10),
        10 * kMaxTextScale,
      );
    });

    test('작게 쓰는 설정은 줄여 준다 — 상한만 걸었다', () {
      expect(appTextScaler(const TextScaler.linear(0.85)).scale(10), 10 * 1.7);
    });

    test('상세창은 상한을 건 뒤의 값에 비율을 곱한다', () {
      expect(
        appTextScaler(
          const TextScaler.linear(2.0),
          of: kDetailTextScale,
        ).scale(10),
        closeTo(10 * kMaxTextScale * kDetailTextScale, 1e-9),
      );
    });
  });
}
