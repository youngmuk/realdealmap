import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 원격 저장소에서 바이트를 가져오는 통로.
///
/// 인터페이스로 둔 것은 테스트 때문만이 아니다. 개발 중에는 `r2.dev`,
/// 출시에는 사용자 지정 도메인을 쓰므로 주소가 바뀐다(기술검토서 §비용).
abstract class RemoteSource {
  /// 없으면 `null`. 404는 오류가 아니다 — 아직 배포되지 않은 지역일 수 있다.
  Future<Uint8List?> get(String key);
}

/// 한 요청을 기다리는 한도.
///
/// **없으면 영원히 기다린다.** `http`에는 기본 읽기 제한이 없어서, 연결은
/// 받아 주고 응답은 안 주는 상대(캡티브 포털, 죽은 프록시)를 만나면 그대로
/// 매달린다. 화면에서는 "갱신 확인 중" 표시가 끝나지 않고, 첫 실행이라면
/// 지역 목록을 받는 단계에서 멈춘 채로 남는다 — 사용자에게는 앱이 죽은 것과
/// 구별되지 않는다.
///
/// 20초는 청크 하나(수십~수백 KB)를 느린 회선에서 받기에 넉넉하면서,
/// 사람이 "안 되는구나" 하고 판단하기 전에 끝난다.
const Duration kRemoteTimeout = Duration(seconds: 20);

class RemoteException implements Exception {
  RemoteException(this.key, this.message);
  final String key;
  final String message;
  @override
  String toString() => '$key: $message';
}

/// R2 공개 버킷에서 직접 받는다.
///
/// 앱이 R2를 그대로 읽는 것이 설계다(AD-1). 서버를 한 겹 두면 Worker의
/// 무료 요청 한도가 곧 동시 사용자 수 상한이 된다.
class HttpRemote implements RemoteSource {
  HttpRemote(this.baseUrl, {http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? kRemoteTimeout;

  /// 끝의 `/`는 있어도 없어도 된다
  final String baseUrl;
  final http.Client _client;
  final Duration _timeout;

  @override
  Future<Uint8List?> get(String key) async {
    final url = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/$key');
    final http.Response response;
    try {
      response = await _client.get(url).timeout(_timeout);
    } on SocketException catch (e) {
      // 기내모드·지하철에서 늘 일어난다. 오류로 올리되 "없음"과는 구분한다(FR-7).
      throw RemoteException(key, '네트워크에 닿지 않는다: ${e.message}');
    } on TimeoutException {
      throw RemoteException(key, '응답이 없다');
    } on HttpException catch (e) {
      throw RemoteException(key, e.message);
    } on http.ClientException catch (e) {
      // TLS 실패·중간에 끊긴 연결이 여기로 온다. `dart:io` 예외가 아니라
      // 위의 둘로는 안 잡히고, 그대로 두면 화면에는 아무 말도 안 나온다.
      throw RemoteException(key, e.message);
    }

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw RemoteException(key, 'HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  void close() => _client.close();
}
