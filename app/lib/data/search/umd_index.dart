/// 전국 법정동 색인 — "중곡동"을 쳤을 때 그 자리를 아는 근거.
///
/// **왜 따로 받나.** 앱이 이미 가진 것은 전국 **시군구** 목록과, 지금 열어 둔
/// 지역의 거래뿐이다. 그 사이가 비어 있다 — 사람이 치는 것은 "중곡동"이지
/// "광진구"가 아니고, 그 동이 어느 구인지는 대개 모른다.
///
/// **왜 에셋이 아니라 받아 오나.** 경계 폴리곤(400KB)은 첫 실행에서 "지금 있는
/// 곳"을 여는 데 쓰이므로 네트워크보다 먼저 있어야 했다. 검색은 사용자가
/// 돋보기를 누른 뒤에 필요하다 — 그때 받아도 늦지 않고, APK가 그만큼 가벼워진다.
///
/// 한 번 받으면 앱이 살아 있는 동안 들고 있는다(268KB). 행정 개편이 있을 때나
/// 바뀌는 자료라 다시 물어볼 이유가 없다.
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import '../sync/geo.dart';
import '../sync/remote.dart';
import 'text_match.dart';

/// 읽을 수 있는 판. 앞으로 나온 판은 무엇이 옛 규칙으로 들어왔는지 알 수 없어 버린다.
const int kSupportedUmdVersion = 1;

/// 색인이 놓인 자리. `packages/ingest/scripts/build-umd-index.mjs`가 굽는다.
const String kUmdIndexKey = 'v1/search/umd.json.gz';

/// 법정동 하나.
class UmdEntry {
  UmdEntry({required this.name, required this.sggCd, required this.center});

  final String name;
  final String sggCd;

  /// 맞춰 볼 글자와 초성. **처음 쓸 때 한 번만** 만든다.
  ///
  /// 18,696개를 글자마다 다시 다듬으면 한 번 검색에 10ms가 든다(실측). 반대로
  /// 색인을 읽을 때 전부 미리 만들면, 검색을 한 번도 안 쓰는 사람이 그 값을 문다.
  late final String normalized = normalizeQuery(name);
  late final String choseong = choseongOf(normalized);

  /// 그 동에 속한 건물 좌표의 **중앙값**이다. 평균과 달리 강 건너 한 점에
  /// 끌려가지 않는다.
  final LatLng center;
}

class UmdIndex {
  const UmdIndex({
    required this.entries,
    required this.source,
    required this.attribution,
  });

  final List<UmdEntry> entries;

  /// 자료 시점 `YYYYMMDD`
  final String source;
  final String attribution;

  bool get isEmpty => entries.isEmpty;

  /// 색인 바이트를 읽는다. 모양이 조금이라도 어긋나면 `null`이다 —
  /// 반쯤 읽으면 어느 줄이 옛 규칙으로 들어왔는지 알 수 없다.
  static UmdIndex? decode(Uint8List bytes) {
    final Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(gunzipIfNeeded(bytes)));
    } on FormatException {
      return null;
    } on Exception {
      // gzip.decode는 깨진 바이트에 FormatException이 아닌 것도 던진다.
      return null;
    }
    if (parsed is! Map<String, dynamic>) return null;
    if (parsed['schemaVersion'] != kSupportedUmdVersion) return null;

    final raw = parsed['umds'];
    if (raw is! List) return null;

    final entries = <UmdEntry>[];
    for (final row in raw) {
      // `[법정동명, 시군구코드, 위도, 경도]`. 열쇠 이름을 18,696번 반복하지
      // 않으려고 배열로 담았다.
      if (row is! List || row.length < 4) return null;
      final name = row[0];
      final sggCd = row[1];
      final lat = row[2];
      final lng = row[3];
      if (name is! String || sggCd is! String) return null;
      if (lat is! num || lng is! num) return null;
      if (name.isEmpty || sggCd.length != 5) return null;
      entries.add(
        UmdEntry(
          name: name,
          sggCd: sggCd,
          center: LatLng(lat.toDouble(), lng.toDouble()),
        ),
      );
    }
    return UmdIndex(
      entries: entries,
      source: parsed['source'] as String? ?? '',
      attribution: parsed['attribution'] as String? ?? '',
    );
  }
}

/// gzip으로 왔으면 풀고, 아니면 그대로 준다.
///
/// R2가 `content-encoding: gzip`을 붙여 두면 클라이언트가 이미 풀어서 준다.
/// 그 헤더가 빠진 채 올라간 적이 있어서(건물 외곽선에서 겪었다) 앞 두 바이트로
/// 한 번 더 본다.
Uint8List gunzipIfNeeded(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    return Uint8List.fromList(gzip.decode(bytes));
  }
  return bytes;
}

/// 색인을 한 번 받아 들고 있는다.
class UmdIndexStore {
  UmdIndexStore(this._remote);

  final RemoteSource _remote;
  Future<UmdIndex?>? _pending;

  /// 받는 중이면 그 미래를 그대로 준다 — 글자를 칠 때마다 요청이 나가면 안 된다.
  Future<UmdIndex?> load() {
    final pending = _pending;
    if (pending != null) return pending;
    final started = _fetch();
    _pending = started;
    return started;
  }

  Future<UmdIndex?> _fetch() async {
    try {
      final bytes = await _remote.get(kUmdIndexKey);
      if (bytes == null) return null;
      return UmdIndex.decode(bytes);
    } on RemoteException {
      // 끊긴 회선을 기억하면 앱을 다시 켤 때까지 검색이 영영 안 된다.
      _pending = null;
      return null;
    }
  }
}
