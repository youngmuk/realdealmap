import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/features/map/map_focus.dart';

/// 상세창 → 지도 이동 요청.
///
/// 이 요청은 **두 곳이 각자 듣는다** — 앱 껍데기는 탭을 바꾸고, 지도 화면은
/// 카메라를 옮긴다. 그래서 같은 좌표를 다시 눌렀을 때도 새 값으로 보여야 한다.
/// 아니면 `ref.listen`이 깨어나지 않아 두 번째 누름이 조용히 먹지 않는다.
void main() {
  test('처음에는 요청이 없다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(mapFocusProvider), isNull);
  });

  test('요청하면 좌표가 담긴다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(mapFocusProvider.notifier).request(37.5, 127.0);

    final focus = container.read(mapFocusProvider);
    expect(focus?.lat, 37.5);
    expect(focus?.lng, 127.0);
  });

  test('같은 좌표를 다시 눌러도 새 요청이다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(mapFocusProvider.notifier);

    notifier.request(37.5, 127.0);
    final first = container.read(mapFocusProvider);
    notifier.request(37.5, 127.0);
    final second = container.read(mapFocusProvider);

    // 좌표가 같아도 값이 달라야 듣는 쪽이 깨어난다.
    expect(second, isNot(same(first)));
    expect(second!.seq, first!.seq + 1);
  });
}
