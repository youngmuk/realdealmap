import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 지도를 어느 좌표로 보내 달라는 요청.
///
/// **왜 있나.** 상세창은 지도 탭과 목록 탭 양쪽에서 열린다. 거기서 "지도에서
/// 보기"를 누르면 두 가지가 같이 일어나야 한다 — 탭을 지도로 바꾸는 것(앱 껍데기의
/// 일)과 카메라를 옮기는 것(지도 화면의 일)이다. 콜백을 두 단계 아래로 내려보내면
/// 목록 → 상세 경로에도 같은 콜백을 또 꿰어야 하고, 그때부터 두 경로가 어긋나기
/// 시작한다. 요청을 한 자리에 두고 둘이 각자 듣는다.
///
/// 예전에는 상세창이 지도 그림을 직접 붙였다. 그 그림은 OSM 타일을 앱에서 바로
/// 받는 것이었는데, **OSM 이용정책은 배포 앱의 트래픽을 허용하지 않는다.**
/// 우리 배경지도는 벡터(PMTiles)라 이미지로 붙일 수 없고, 렌더러를 하나 더 띄우면
/// 그래픽 메모리가 두 배가 된다(지도 하나가 139 MB · 실측). 그래서 그림을 만드는
/// 대신 **이미 떠 있는 지도로 데려간다** — 주변 맥락은 큰 지도에서 더 잘 보인다.
class MapFocus {
  const MapFocus({required this.lat, required this.lng, required this.seq});

  final double lat;
  final double lng;

  /// 같은 좌표를 두 번 눌러도 새 요청으로 보이게 하는 일련번호.
  /// 값이 같으면 `ref.listen`이 깨어나지 않아 두 번째 누름이 먹지 않는다.
  final int seq;
}

class MapFocusController extends Notifier<MapFocus?> {
  @override
  MapFocus? build() => null;

  /// 일련번호는 여기서만 올린다.
  void request(double lat, double lng) {
    state = MapFocus(lat: lat, lng: lng, seq: (state?.seq ?? 0) + 1);
  }
}

/// 마지막 요청. 아직 아무도 부르지 않았으면 `null`.
final mapFocusProvider = NotifierProvider<MapFocusController, MapFocus?>(
  MapFocusController.new,
);
