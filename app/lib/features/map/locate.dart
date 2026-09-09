/// 지금 있는 곳으로 지도를 옮긴다 (FR-1).
///
/// **위치 기능 자체는 처음부터 있었다.** 다만 첫 실행에서 열어 볼 지역을 고르는
/// 데에만 쓰였고, 한 번 지역이 정해지면 다시 부를 길이 없었다 — 앱은 늘 마지막에
/// 보던 자리에서 시작한다. 다른 동네에 와 있어도 사용자가 할 수 있는 것은
/// 지역을 직접 고르고 지도를 손으로 미는 것뿐이었다.
///
/// 여기서는 지역을 고르는 데서 그치지 않고 **실제 좌표로 간다.** 시군구 중심점은
/// 지금 서 있는 자리가 아니다. "현재 위치"라고 이름 붙인 것이 몇 킬로미터 떨어진
/// 곳을 열면 그것은 틀린 것이다.
///
/// 좌표는 기기 밖으로 나가지 않는다 — 근거는 [LocationSource]에 적어 두었다.
library;

import '../../data/location.dart';
import '../../data/sync/region_index.dart';

/// 위치 찾기의 결과. 화면은 이것만 보고 무엇을 할지 정한다.
sealed class LocateResult {
  const LocateResult();
}

/// 좌표를 얻었다.
///
/// [region]이 null이면 색인에 이 좌표를 담는 지역도, 가까운 지역도 없다.
/// 그래도 **좌표는 유효하므로 지도는 옮긴다** — 거래가 없을 뿐이지
/// 위치를 못 찾은 것이 아니다. 둘을 같은 실패로 뭉뚱그리면 사용자는
/// 위치 권한을 다시 뒤지게 된다.
final class Located extends LocateResult {
  const Located(this.lat, this.lng, this.region);

  final double lat;
  final double lng;
  final RegionSummary? region;
}

/// 좌표를 못 얻었다. 이유는 [outcome]이 들고 있다.
final class LocateFailed extends LocateResult {
  const LocateFailed(this.outcome);

  final LocationOutcome outcome;
}

/// 아직 지역 색인이 없다. 좌표를 시군구로 풀 근거가 없어 물어보지도 않는다.
///
/// 권한 창을 띄워 놓고 아무 일도 일어나지 않는 것보다, 잠시 뒤 다시 하라고
/// 말하는 편이 낫다.
final class LocateNoIndex extends LocateResult {
  const LocateNoIndex();
}

Future<LocateResult> locateHere(
  LocationSource source,
  RegionIndex? index,
) async {
  if (index == null || index.isEmpty) return const LocateNoIndex();

  final (outcome, fix) = await source.current();
  if (fix == null) return LocateFailed(outcome);

  final point = LatLng(fix.lat, fix.lng);
  return Located(fix.lat, fix.lng, index.at(point) ?? index.nearest(point));
}
