import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 머리말에 **시군구 코드가 보이면 안 된다.**
///
/// 실기기에서 앱을 껐다 켜면 머리말이 잠깐 `11230`으로 떴다. 지역 색인은
/// 네트워크로 오는데 머리말은 그보다 먼저 그려지기 때문이다. 5자리 숫자는
/// 내부 값이라 사용자에게 아무 뜻이 없고, 그 순간 앱이 고장난 것처럼 보인다.
///
/// 색인을 기다리게 만들 수는 없다(그러면 머리말이 비어 있다). 대신 마지막으로
/// 알던 **이름을 같이 남겨** 두었다가 그것을 쓴다.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('지역을 고르면 이름도 함께 남는다', () async {
    final c = await container();
    c.read(selectedRegionProvider.notifier).select('11230', name: '동대문구');

    expect(c.read(selectedRegionProvider), '11230');
    expect(c.read(lastRegionNameProvider), '동대문구');
  });

  test('앱을 다시 켜도 이름이 남아 있다', () async {
    SharedPreferences.setMockInitialValues({
      'region.selected': '11230',
      'region.selected.name': '동대문구',
    });
    final c = await container();

    expect(c.read(selectedRegionProvider), '11230');
    expect(c.read(lastRegionNameProvider), '동대문구');
  });

  // 지도를 움직여 지역이 바뀌었는데 그 지역의 이름을 아직 모를 수 있다.
  // 그때 옛 이름을 그대로 두면 **다른 지역 이름이 붙은 채로 남는다** —
  // 코드를 보여주는 것보다 나쁘다. 모르면 지운다.
  test('이름 없이 지역만 바뀌면 옛 이름을 지운다', () async {
    final c = await container();
    c.read(selectedRegionProvider.notifier).select('11230', name: '동대문구');
    c.read(selectedRegionProvider.notifier).select('11680');

    expect(c.read(selectedRegionProvider), '11680');
    expect(c.read(lastRegionNameProvider), isNull);
  });

  test('지역을 비우면 이름도 비운다', () async {
    final c = await container();
    c.read(selectedRegionProvider.notifier).select('11230', name: '동대문구');
    c.read(selectedRegionProvider.notifier).select(null);

    expect(c.read(selectedRegionProvider), isNull);
    expect(c.read(lastRegionNameProvider), isNull);
  });

  test('같은 지역을 다시 고르면 이름만 채워 넣을 수 있다', () async {
    final c = await container();
    // 색인이 늦게 도착해 이름을 뒤늦게 알게 되는 경우다.
    c.read(selectedRegionProvider.notifier).select('11230');
    expect(c.read(lastRegionNameProvider), isNull);

    c.read(selectedRegionProvider.notifier).select('11230', name: '동대문구');
    expect(c.read(lastRegionNameProvider), '동대문구');
  });
}
