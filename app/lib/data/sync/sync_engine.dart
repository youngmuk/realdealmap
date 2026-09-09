import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import 'manifest.dart';
import 'remote.dart';

/// 동기화 엔진 — 매니페스트 비교 · 내려받기 · 해시 검증 · 트랜잭션 반영 (T5.3).
///
/// 규칙 하나가 전부다: **전부 받아서 전부 검증한 뒤에야 한 번에 반영한다.**
/// 받는 대로 반영하면 27개 중 5번째가 깨졌을 때 앞의 넷은 새 데이터,
/// 나머지는 옛 데이터인 상태로 남는다. 그 상태는 매니페스트 어느 판과도 맞지 않는다.
/// 서버가 청크를 전부 올린 뒤에야 매니페스트를 바꾸는 것과 같은 이유다(§5.3).

enum SyncStatus {
  /// 새 데이터를 반영했다
  updated,

  /// 매니페스트가 그대로라 할 일이 없었다
  unchanged,

  /// 아직 배포된 적 없는 지역
  absent,

  /// 네트워크에 닿지 못했다. **기존 데이터는 그대로다**
  offline,

  /// 받았지만 믿을 수 없었다(해시 불일치 · 형식 오류). **기존 데이터는 그대로다**
  rejected,
}

class SyncOutcome {
  const SyncOutcome({
    required this.sggCd,
    required this.status,
    this.manifest,
    this.downloaded = 0,
    this.reused = 0,
    this.applied = 0,
    this.message,
  });

  final String sggCd;
  final SyncStatus status;
  final Manifest? manifest;

  /// 실제로 받은 청크 수
  final int downloaded;

  /// 경로가 그대로라 받지 않은 청크 수. 콘텐츠 해시 경로 덕분에 생긴다
  final int reused;

  /// 반영한 거래 건수
  final int applied;
  final String? message;

  bool get changed => status == SyncStatus.updated;

  /// 데이터를 건드리지 않고 끝났는가. 화면은 이때 옛 데이터를 그대로 보여준다(FR-7)
  bool get keptExisting =>
      status == SyncStatus.offline || status == SyncStatus.rejected;
}

/// 내려받아 검증까지 마친 청크. 반영 직전까지 메모리에 들고 있는다.
///
/// 여기 담기는 것은 **이미 DB 행으로 바뀐 것**이다. 트랜잭션 안에서 바꾸면
/// 모양이 어긋난 한 줄이 `TypeError`로 터지는데, 그 예외는 [SyncEngine.sync]의
/// 어느 `catch`에도 걸리지 않아 화면까지 올라간다. 받는 자리에서 바꿔 두면
/// 해시가 어긋났을 때와 같은 길(거부)로 보낼 수 있다.
class _VerifiedChunk {
  _VerifiedChunk(this.file, this.rows);
  final ManifestFile file;
  final List<TxRowsCompanion> rows;
}

/// 청크를 한 번에 몇 개까지 동시에 받을지.
///
/// 하나씩 받으면 12개월 지역(9종 × 12달 = 108개)의 첫 동기화에서 왕복 지연이
/// 108번 그대로 쌓인다. 지도가 20~30초 비어 있고, 사용자에게 그것은 고장이다.
///
/// 그렇다고 108개를 한꺼번에 열면 모바일 회선에서 서로를 밀어내고 타임아웃이
/// 늘어난다. 여섯 개는 왕복 지연을 거의 다 숨기면서 그 지점에 닿지 않는다.
const int kChunkConcurrency = 6;

class _ChunkRejected implements Exception {
  _ChunkRejected(this.message);
  final String message;
}

class SyncEngine {
  SyncEngine(this._db, this._remote, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final RemoteSource _remote;
  final DateTime Function() _now;

  static String manifestKey(String sggCd) => 'v1/regions/$sggCd/manifest.json';

  Future<SyncOutcome> sync(String sggCd) async {
    final Manifest manifest;
    try {
      final bytes = await _remote.get(manifestKey(sggCd));
      if (bytes == null) {
        return SyncOutcome(sggCd: sggCd, status: SyncStatus.absent);
      }
      manifest = Manifest.fromJson(
        jsonDecode(utf8.decode(maybeGunzip(bytes))) as Map<String, dynamic>,
      );
    } on RemoteException catch (e) {
      return SyncOutcome(
        sggCd: sggCd,
        status: SyncStatus.offline,
        message: e.message,
      );
    } on ManifestFormatException catch (e) {
      return SyncOutcome(
        sggCd: sggCd,
        status: SyncStatus.rejected,
        message: e.message,
      );
    } on FormatException catch (e) {
      return SyncOutcome(
        sggCd: sggCd,
        status: SyncStatus.rejected,
        message: '매니페스트 JSON이 깨졌다: ${e.message}',
      );
    }

    final applied = await _db.appliedChunkPaths(sggCd);
    final wanted = manifest.files.map((f) => f.path).toSet();
    final missing = manifest.files
        .where((f) => !applied.contains(f.path))
        .toList();
    final obsolete = applied.difference(wanted);

    if (missing.isEmpty && obsolete.isEmpty) {
      // 내용은 그대로여도 서버가 다시 만든 시각은 갱신됐을 수 있다.
      // 화면의 "기준 시각"이 뒤처지지 않게 지역 행만 손본다.
      await _upsertRegion(manifest);
      return SyncOutcome(
        sggCd: sggCd,
        status: SyncStatus.unchanged,
        manifest: manifest,
        reused: applied.length,
      );
    }

    final verified = <_VerifiedChunk>[];
    for (var i = 0; i < missing.length; i += kChunkConcurrency) {
      final slice = missing.skip(i).take(kChunkConcurrency).toList();
      final results = await Future.wait(slice.map((f) => _tryFetch(sggCd, f)));

      // **매니페스트 순서대로** 본다. 병렬로 받으면 실패가 도착하는 순서가
      // 매번 달라지는데, 그때그때 다른 것을 보고하면 같은 고장이 실행할
      // 때마다 다른 메시지로 보인다.
      for (var j = 0; j < results.length; j += 1) {
        final (chunk, error) = results[j];

        if (error is RemoteException) {
          return SyncOutcome(
            sggCd: sggCd,
            status: SyncStatus.offline,
            manifest: manifest,
            message: error.message,
          );
        }
        if (error is _ChunkRejected) {
          return SyncOutcome(
            sggCd: sggCd,
            status: SyncStatus.rejected,
            manifest: manifest,
            message: error.message,
          );
        }
        if (chunk == null) {
          // 매니페스트가 가리키는데 없다. 서버가 순서를 어겼거나 정리가 앞질렀다.
          return SyncOutcome(
            sggCd: sggCd,
            status: SyncStatus.rejected,
            manifest: manifest,
            message: '매니페스트가 가리키는 청크가 없다: ${slice[j].path}',
          );
        }
        verified.add(chunk);
      }
    }

    final count = await _apply(manifest, verified, obsolete);
    return SyncOutcome(
      sggCd: sggCd,
      status: SyncStatus.updated,
      manifest: manifest,
      downloaded: verified.length,
      reused: applied.length - obsolete.length,
      applied: count,
    );
  }

  /// [_fetchAndVerify]를 부르되 예외를 **값으로** 돌려준다.
  ///
  /// `Future.wait`은 하나가 던지면 나머지 결과를 버린다. 그러면 어느 것이
  /// 먼저 던졌느냐에 따라 보고가 달라진다 — 예외를 값으로 받아 두고
  /// 순서대로 판정한다.
  Future<(_VerifiedChunk?, Object?)> _tryFetch(
    String sggCd,
    ManifestFile file,
  ) async {
    try {
      return (await _fetchAndVerify(sggCd, file), null);
    } on RemoteException catch (e) {
      return (null, e);
    } on _ChunkRejected catch (e) {
      return (null, e);
    }
  }

  /// 청크 하나를 받아 **해시를 확인한 뒤에만** 돌려준다.
  ///
  /// 서버는 **압축 전 정규 JSON**을 해시한다(§5.3). gzip 바이트는 zlib 버전과
  /// 플랫폼에 따라 달라지므로 그것을 해시하면 같은 데이터가 다른 값이 된다.
  /// 그래서 여기서도 풀어서 해시한다.
  Future<_VerifiedChunk?> _fetchAndVerify(
    String sggCd,
    ManifestFile file,
  ) async {
    final raw = await _remote.get(file.path);
    if (raw == null) return null;

    final json = maybeGunzip(raw);
    final digest = sha256.convert(json).toString();
    if (digest != file.sha256) {
      throw _ChunkRejected(
        '${file.path}의 해시가 다르다 '
        '(기대 ${_short(file.sha256)}, 실제 ${_short(digest)})',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(json)) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw _ChunkRejected('${file.path}의 JSON이 깨졌다: ${e.message}');
    }

    final records = body['records'];
    if (records is! List) throw _ChunkRejected('${file.path}에 records가 없다');

    return _VerifiedChunk(file, [
      for (final record in records) _toCompanion(sggCd, file, record),
    ]);
  }

  /// 한 트랜잭션 안에서 갈아 끼운다. 중간에 끊기면 통째로 되돌아간다.
  Future<int> _apply(
    Manifest manifest,
    List<_VerifiedChunk> chunks,
    Set<String> obsolete,
  ) async {
    var applied = 0;

    await _db.transaction(() async {
      for (final path in obsolete) {
        final row = await (_db.select(
          _db.chunkRows,
        )..where((c) => c.path.equals(path))).getSingleOrNull();
        if (row == null) continue;
        await _deleteRows(row.sggCd, row.datasetKey, row.period);
        await (_db.delete(
          _db.chunkRows,
        )..where((c) => c.path.equals(path))).go();
      }

      for (final chunk in chunks) {
        final f = chunk.file;
        // 같은 (지역 · 유형 · 월)의 옛 행을 먼저 지운다. 갱신이 아니라 교체다 —
        // 원천에서 정정으로 사라진 거래를 남겨 두면 영원히 지워지지 않는다.
        await _deleteRows(manifest.sggCd, f.datasetKey, f.month);

        await _db.batch((b) {
          b.insertAll(_db.txRows, chunk.rows);
        });
        applied += chunk.rows.length;

        await _db
            .into(_db.chunkRows)
            .insertOnConflictUpdate(
              ChunkRowsCompanion.insert(
                path: f.path,
                sggCd: manifest.sggCd,
                datasetKey: f.datasetKey,
                period: f.month,
                sha256: f.sha256,
                records: f.records,
                appliedAt: _nowIso(),
              ),
            );
      }

      await _upsertRegion(manifest);
    });

    return applied;
  }

  Future<void> _deleteRows(String sggCd, String datasetKey, String period) =>
      (_db.delete(_db.txRows)..where(
            (t) =>
                t.sggCd.equals(sggCd) &
                t.datasetKey.equals(datasetKey) &
                t.period.equals(period),
          ))
          .go();

  Future<void> _upsertRegion(Manifest manifest) => _db
      .into(_db.regionRows)
      .insertOnConflictUpdate(
        RegionRowsCompanion.insert(
          sggCd: manifest.sggCd,
          refreshedAt: manifest.refreshedAt.toIso8601String(),
          ttlSeconds: manifest.ttlSeconds,
          syncedAt: _nowIso(),
        ),
      );

  String _nowIso() => _now().toUtc().toIso8601String();

  /// 청크 한 줄을 DB 행으로 바꾼다. **모양이 다르면 [_ChunkRejected]를 던진다.**
  ///
  /// `as`로 바로 형변환하면 던지는 것이 `TypeError`인데, 그것은 [sync]의 어느
  /// `catch`에도 걸리지 않는다. 우리가 만든 자료라 그럴 일이 없어야 하지만,
  /// "그럴 일이 없다"와 "그때 앱이 어떻게 되는가"는 다른 이야기다. 거부로
  /// 보내면 옛 자료를 그대로 둔 채 이유를 말할 수 있다(FR-7).
  TxRowsCompanion _toCompanion(
    String sggCd,
    ManifestFile file,
    Object? record,
  ) {
    Never bad(String what, Object? value) =>
        throw _ChunkRejected('${file.path}의 $what 모양이 다르다: $value');

    if (record is! Map<String, dynamic>) bad('records 원소', record);
    final r = record;

    String? asString(String key) {
      final v = r[key];
      if (v is String) return v;
      if (v == null) return null;
      bad(key, v);
    }

    int? asInt(String key) {
      final v = r[key];
      if (v is num) return v.toInt();
      if (v == null) return null;
      bad(key, v);
    }

    double? asDouble(String key) {
      final v = r[key];
      if (v is num) return v.toDouble();
      if (v == null) return null;
      bad(key, v);
    }

    // 실거래 한 건을 가리키는 열쇠다. 없으면 그 줄이 무엇인지 알 수 없다.
    final txId = asString('id');
    if (txId == null) bad('id', r['id']);

    return TxRowsCompanion.insert(
      txId: txId,
      sggCd: sggCd,
      datasetKey: file.datasetKey,
      period: file.month,
      umdNm: asString('umdNm') ?? '',
      contractedOn: asString('contractedOn') ?? '',
      cancelled: r['cancelled'] == true,
      precision: asString('precision') ?? 'umd',
      // 상세화면이 유형별 고유 항목을 여기서 읽는다(FR-3). 통째로 보존한다.
      raw: jsonEncode(r['raw'] ?? const <String, String>{}),
      jibun: Value(asString('jibun')),
      name: Value(asString('name')),
      areaSqm: Value(asDouble('areaSqm')),
      floor: Value(asInt('floor')),
      builtYear: Value(asInt('builtYear')),
      amount: Value(asInt('amount')),
      deposit: Value(asInt('deposit')),
      monthlyRent: Value(asInt('monthlyRent')),
      cancelledOn: Value(asString('cancelledOn')),
      lat: Value(asDouble('lat')),
      lng: Value(asDouble('lng')),
    );
  }
}

String _short(String digest) =>
    digest.length <= 12 ? digest : '${digest.substring(0, 12)}...';

/// gzip이면 푼다.
///
/// R2에 `content-encoding: gzip`으로 올렸으므로 **대개** HTTP 클라이언트가 알아서
/// 푼다. 다만 그건 보장이 아니라 관측이라(수집 스크립트에서도 같은 문제를 겪었다)
/// 매직 바이트로 직접 확인한다. 양쪽 다 처리하면 클라이언트가 무엇을 하든 옳다.
Uint8List maybeGunzip(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    return Uint8List.fromList(gzip.decode(bytes));
  }
  return bytes;
}
