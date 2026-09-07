/// 갱신 트리거 — 서버에 "이 지역 좀 새로 만들어 줘"라고 던진다 (T5.5 · AD-5).
///
/// **던지고 기다리지 않는다.** 갱신은 국토부 호출부터 R2 업로드까지 수십 초가
/// 걸리므로 기다리면 화면이 그만큼 멈춘다. 사용자는 그 사이 이미 있는 데이터를
/// 그대로 보면 되고, 새 데이터는 다음 진입이나 당김 새로고침에서 붙는다.
///
/// 서버가 거절하는 것은 정상이다 — 방금 갱신했거나(fresh) 이미 돌고 있거나(running)
/// 하루 예산을 다 썼거나(quota). 셋 다 오류가 아니라 **답**이다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum TriggerResult {
  /// 접수됐다. 수십 초 뒤에 새 데이터가 생긴다
  accepted,

  /// 이미 그 지역을 갱신하는 중이다
  alreadyRunning,

  /// 방금 갱신했다. 최소 간격 안이다
  tooSoon,

  /// 하루 예산을 다 썼다
  budgetExhausted,

  /// 서버가 거절했거나 닿지 못했다. 화면은 아무것도 바꾸지 않는다
  failed,
}

class RefreshTrigger {
  RefreshTrigger(this.workerBaseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String workerBaseUrl;
  final http.Client _client;

  /// 갱신을 요청한다.
  ///
  /// [timeout]이 짧은 것은 의도다. 이 호출의 값어치는 **접수 여부를 아는 것**이지
  /// 갱신을 지켜보는 것이 아니다. 오래 붙잡고 있어 봐야 배터리만 쓴다.
  Future<TriggerResult> request(
    String sggCd, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (workerBaseUrl.isEmpty) return TriggerResult.failed;

    final url = Uri.parse(
      '${workerBaseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/refresh',
    );

    final http.Response response;
    try {
      response = await _client
          .post(
            url,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'sggCd': sggCd}),
          )
          .timeout(timeout);
    } on SocketException {
      return TriggerResult.failed;
    } on HttpException {
      return TriggerResult.failed;
    } on FormatException {
      return TriggerResult.failed;
    }

    if (response.statusCode == 429) return TriggerResult.budgetExhausted;
    if (response.statusCode >= 400) return TriggerResult.failed;

    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      return TriggerResult.failed;
    }
    if (body is! Map<String, dynamic>) return TriggerResult.failed;

    if (body['accepted'] == true) return TriggerResult.accepted;
    if (body['alreadyRunning'] == true) return TriggerResult.alreadyRunning;
    return TriggerResult.tooSoon;
  }

  void close() => _client.close();
}
