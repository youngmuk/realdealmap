/// 지역 매니페스트 — 서버가 "지금 살아 있는 청크"를 알려주는 유일한 입구 (§5.2).
///
/// 필드 이름은 서버(`packages/ingest/src/publish.ts`)의 `Manifest`와 1:1이다.
/// 한쪽만 바꾸면 조용히 어긋나므로 [schemaVersion]으로 판을 확인한다.
library;

/// 앱이 이해하는 매니페스트 판. 서버가 이보다 높은 판을 주면 읽지 않는다.
const int kSupportedSchemaVersion = 1;

class ManifestFormatException implements Exception {
  ManifestFormatException(this.message);
  final String message;
  @override
  String toString() => '매니페스트를 읽을 수 없다: $message';
}

class ManifestFile {
  const ManifestFile({
    required this.propertyType,
    required this.tradeType,
    required this.month,
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.records,
  });

  final String propertyType;
  final String tradeType;

  /// 계약 연월 `YYYYMM`
  final String month;

  /// R2 오브젝트 키. **콘텐츠 해시가 박혀 있어 경로가 같으면 내용도 같다**
  final String path;
  final String sha256;
  final int bytes;
  final int records;

  String get datasetKey => '$propertyType/$tradeType';

  factory ManifestFile.fromJson(Map<String, dynamic> json) {
    Object? need(String key) {
      final value = json[key];
      if (value == null) throw ManifestFormatException('files[].$key 없음');
      return value;
    }

    return ManifestFile(
      propertyType: need('propertyType')! as String,
      tradeType: need('tradeType')! as String,
      month: need('month')! as String,
      path: need('path')! as String,
      sha256: need('sha256')! as String,
      bytes: (need('bytes')! as num).toInt(),
      records: (need('records')! as num).toInt(),
    );
  }
}

/// 첫 설치용 묶음이 어디 있는지 (`packages/ingest/src/bundle.ts`).
///
/// **뒤처져 있을 수 있다.** 청크 경로에 내용 해시가 박혀 있어, 묶음 안의 옛
/// 청크는 지금 매니페스트의 어느 경로와도 맞지 않아 그냥 버려진다. 그래서
/// 묶음이 최신인지 확인할 필요가 없다 — 맞는 것만 쓰면 된다.
class BundleRef {
  const BundleRef({
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.chunks,
  });

  final String path;

  /// **압축 전** 정규 JSON의 해시. 청크와 같은 규칙이다
  final String sha256;

  /// 압축 후 바이트. 낱개로 받는 것보다 싼지를 이 값으로 잰다
  final int bytes;
  final int chunks;

  factory BundleRef.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    final sha256 = json['sha256'];
    final bytes = json['bytes'];
    final chunks = json['chunks'];
    if (path is! String ||
        sha256 is! String ||
        bytes is! num ||
        chunks is! num) {
      throw ManifestFormatException('bundle의 모양이 다르다');
    }
    return BundleRef(
      path: path,
      sha256: sha256,
      bytes: bytes.toInt(),
      chunks: chunks.toInt(),
    );
  }
}

class Manifest {
  const Manifest({
    required this.schemaVersion,
    required this.sggCd,
    required this.refreshedAt,
    required this.ttlSeconds,
    required this.files,
    this.bundle,
  });

  final int schemaVersion;
  final String sggCd;

  /// 서버가 데이터를 만든 시각. **화면의 "기준 시각"이 이 값이다**
  final DateTime refreshedAt;
  final int ttlSeconds;
  final List<ManifestFile> files;

  /// 첫 설치용 묶음. 옛 서버가 만든 매니페스트에는 없다
  final BundleRef? bundle;

  int get totalRecords => files.fold(0, (sum, f) => sum + f.records);

  factory Manifest.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! int) throw ManifestFormatException('schemaVersion 없음');
    // 앞으로 나온 판을 반쯤 읽어 쓰면 무엇이 옛 규칙으로 들어왔는지 알 수 없다.
    // 낡은 앱은 낡은 데이터를 그대로 보여주는 편이 낫다.
    if (version > kSupportedSchemaVersion) {
      throw ManifestFormatException(
        '앱이 모르는 판 $version (앱은 $kSupportedSchemaVersion까지)',
      );
    }

    final refreshedAt = DateTime.tryParse(json['refreshedAt'] as String? ?? '');
    if (refreshedAt == null) {
      throw ManifestFormatException('refreshedAt이 시각이 아님');
    }

    final rawFiles = json['files'];
    if (rawFiles is! List) {
      throw ManifestFormatException('files가 목록이 아님');
    }

    return Manifest(
      schemaVersion: version,
      sggCd: json['sggCd'] as String? ?? '',
      refreshedAt: refreshedAt.toUtc(),
      ttlSeconds: (json['ttlSeconds'] as num?)?.toInt() ?? 3600,
      files: rawFiles
          .map((f) => ManifestFile.fromJson(f as Map<String, dynamic>))
          .toList(growable: false),
      // 없으면 없는 대로 간다 — 옛 서버가 만든 매니페스트에는 이 자리가 없다.
      bundle: switch (json['bundle']) {
        final Map<String, dynamic> b => BundleRef.fromJson(b),
        _ => null,
      },
    );
  }

  /// 데이터가 낡았는가 (§5.2).
  ///
  /// 기준은 **서버가 새로 만든 시각**이지 앱이 받아 간 시각이 아니다. 받은 시각을
  /// 기준으로 삼으면 오래 꺼 뒀던 앱이 켜자마자 "신선함"으로 판정한다.
  bool isStale(DateTime now) =>
      now.toUtc().difference(refreshedAt) > Duration(seconds: ttlSeconds);
}
