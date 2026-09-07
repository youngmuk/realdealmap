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
  HttpRemote(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  /// 끝의 `/`는 있어도 없어도 된다
  final String baseUrl;
  final http.Client _client;

  @override
  Future<Uint8List?> get(String key) async {
    final url = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/$key');
    final http.Response response;
    try {
      response = await _client.get(url);
    } on SocketException catch (e) {
      // 기내모드·지하철에서 늘 일어난다. 오류로 올리되 "없음"과는 구분한다(FR-7).
      throw RemoteException(key, '네트워크에 닿지 않는다: ${e.message}');
    } on HttpException catch (e) {
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
