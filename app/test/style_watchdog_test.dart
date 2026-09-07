import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/features/map/style_watchdog.dart';

/// 지도가 멈췄는지 판단하는 규칙.
///
/// 이 파일이 있는 이유는 원래의 결함이 **실기기에서만** 드러났기 때문이다.
/// 첫 실행에서 권한 대화상자가 뜨는 순간 스타일 로딩이 멈추고, 그 뒤로는 탭을
/// 옮겨도 지도가 돌아오지 않았다. 앱을 껐다 켜야 살아났다. 그 판단을 여기로
/// 떼어 두지 않으면, 예산을 되돌리는 자리 하나만 옮겨도 같은 일이 다시 벌어지고
/// 그때도 실기기에서나 알게 된다.
void main() {
  test('시간 안에 살아나면 아무 일도 하지 않는다', () {
    fakeAsync((async) {
      var stuck = 0;
      final w = StyleWatchdog(onStuck: () => stuck++);

      w.watch();
      async.elapse(const Duration(seconds: 5));
      w.recovered();
      async.elapse(const Duration(minutes: 1));

      expect(stuck, 0);
      expect(w.isWatching, isFalse);
    });
  });

  test('시간을 넘기면 다시 만들라고 알린다', () {
    fakeAsync((async) {
      var stuck = 0;
      final w = StyleWatchdog(onStuck: () => stuck++);

      w.watch();
      async.elapse(const Duration(seconds: 11));

      expect(stuck, 1);
      expect(w.retries, 1);
    });
  });

  test('다시 걸면 처음부터 센다', () {
    fakeAsync((async) {
      var stuck = 0;
      final w = StyleWatchdog(onStuck: () => stuck++);

      w.watch();
      async.elapse(const Duration(seconds: 9));
      w.watch(); // 새 지도가 만들어졌다
      async.elapse(const Duration(seconds: 9));

      expect(stuck, 0, reason: '두 번째 감시는 아직 시간이 남았다');
      async.elapse(const Duration(seconds: 2));
      expect(stuck, 1);
    });
  });

  // 정말로 못 그리는 기기에서 끝없이 다시 만들면 깜빡임만 남는다.
  test('예산을 다 쓰면 더 만들지 않는다', () {
    fakeAsync((async) {
      var stuck = 0;
      final w = StyleWatchdog(onStuck: () => stuck++, maxRetries: 3);

      for (var i = 0; i < 6; i++) {
        w.watch();
        async.elapse(const Duration(seconds: 11));
      }

      expect(stuck, 3);
    });
  });

  // 예산이 없으면 타이머 자체를 걸지 않는다. 걸어 두고 만료 때 아무것도 안 하면
  // 배터리를 쓰면서 아무 일도 하지 않는 것이다.
  test('예산이 없으면 감시하지 않는다', () {
    fakeAsync((async) {
      final w = StyleWatchdog(onStuck: () {}, maxRetries: 1);

      w.watch();
      async.elapse(const Duration(seconds: 11));
      w.watch();

      expect(w.isWatching, isFalse);
    });
  });

  // 예산은 "한 사고를 몇 번까지 다시 시도하는가"이지 앱 생애 전체의 한도가 아니다.
  // 되돌리지 않으면 오래 켜 둔 앱은 세 번째 사고 이후로 영영 복구하지 않는다.
  test('한 번 살아나면 예산이 돌아온다', () {
    fakeAsync((async) {
      var stuck = 0;
      final w = StyleWatchdog(onStuck: () => stuck++, maxRetries: 2);

      for (var i = 0; i < 2; i++) {
        w.watch();
        async.elapse(const Duration(seconds: 11));
      }
      expect(stuck, 2);
      expect(w.retries, 2);

      w.recovered();
      expect(w.retries, 0);

      w.watch();
      async.elapse(const Duration(seconds: 11));
      expect(stuck, 3, reason: '살아난 뒤의 사고에는 다시 기회를 준다');
    });
  });

  // 스타일을 세우는 동안은 멈춘 것이 아니다. 그때 다시 만들면 세우던 것을 버린다.
  test('세우는 동안에는 감시를 쉬되 예산은 그대로 둔다', () {
    fakeAsync((async) {
      var stuck = 0;
      final w = StyleWatchdog(onStuck: () => stuck++);

      w.watch();
      async.elapse(const Duration(seconds: 11));
      expect(w.retries, 1);

      w.pause();
      async.elapse(const Duration(minutes: 5));

      expect(stuck, 1, reason: '쉬는 동안에는 알리지 않는다');
      expect(w.retries, 1, reason: '아직 살아난 것이 아니므로 예산은 그대로다');
    });
  });

  test('버린 뒤에는 알리지 않는다', () {
    fakeAsync((async) {
      var stuck = 0;
      final w = StyleWatchdog(onStuck: () => stuck++);

      w.watch();
      w.dispose();
      async.elapse(const Duration(minutes: 1));

      expect(stuck, 0);
    });
  });
}
