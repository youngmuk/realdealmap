import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:realdealmap/data/sync/remote.dart';

/// `HttpRemote`가 네트워크 사고를 어떻게 다루는가.
///
/// 여기서 지키는 것은 **멈추지 않는 것**이다. 연결은 받아 주고 응답은 안 주는
/// 상대를 만나면 `http`는 영원히 기다린다. 그 상태는 화면에서 "갱신 확인 중"이
/// 끝나지 않는 모습으로 나타나고, 사용자에게는 앱이 죽은 것과 구별되지 않는다.
void main() {
  test('응답이 오지 않으면 기다리다 포기한다', () async {
    // 영원히 완결되지 않는 요청. 제한이 없으면 이 테스트가 시간 초과로 죽는다.
    final client = MockClient((_) => Completer<http.Response>().future);
    final remote = HttpRemote(
      'https://example.test',
      client: client,
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      remote.get('v1/index.json'),
      throwsA(isA<RemoteException>()),
    );
  });

  // TLS 실패와 중간에 끊긴 연결이 이 모양으로 온다. `dart:io` 예외가 아니라
  // SocketException/HttpException으로는 안 잡히고, 그대로 두면 화면에
  // 아무 말도 안 나온 채 동기화만 실패한다.
  test('http 패키지의 예외도 오류로 올린다', () async {
    final client = MockClient(
      (_) => Future.error(http.ClientException('연결이 끊겼다')),
    );
    final remote = HttpRemote('https://example.test', client: client);

    await expectLater(
      remote.get('v1/index.json'),
      throwsA(isA<RemoteException>()),
    );
  });

  test('404는 오류가 아니라 없음이다', () async {
    final client = MockClient((_) async => http.Response('', 404));
    final remote = HttpRemote('https://example.test', client: client);

    expect(await remote.get('v1/geo/99999.json'), isNull);
  });

  test('200이면 바이트를 그대로 준다', () async {
    final client = MockClient((_) async => http.Response('hi', 200));
    final remote = HttpRemote('https://example.test', client: client);

    expect(
      await remote.get('v1/index.json'),
      Uint8List.fromList('hi'.codeUnits),
    );
  });
}

/// 요청을 가로채는 최소 클라이언트. 테스트에 http 패키지의 testing 의존을
/// 더하지 않으려고 여기서 만든다.
class MockClient extends http.BaseClient {
  MockClient(this.handler);
  final Future<http.Response> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
    );
  }
}
