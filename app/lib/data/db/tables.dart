import 'package:drift/drift.dart';

/// 로컬 저장소의 표 정의 (T5.2).
///
/// 서버가 주는 청크를 그대로 담는다. 앱이 다시 계산하는 것은 없다 —
/// 좌표도 정밀도도 이미 구워져 온다(AD-1).

/// 거래 한 건.
///
/// **[rid]가 필요한 이유**: R*Tree 가상 테이블은 열쇠가 INTEGER rowid여야 한다.
/// 서버가 주는 [txId]는 콘텐츠 해시라 문자열이므로 정수 대리키를 하나 둔다.
/// `autoIncrement()`가 곧 `INTEGER PRIMARY KEY AUTOINCREMENT`, 즉 rowid다.
class TxRows extends Table {
  IntColumn get rid => integer().autoIncrement()();

  /// 서버가 정한 식별자. 같은 거래는 어느 기기에서도 같은 값이다
  TextColumn get txId => text().unique()();

  TextColumn get sggCd => text().withLength(min: 5, max: 5)();
  TextColumn get datasetKey => text()();

  /// 계약 연월 `YYYYMM`. 청크 단위로 지우고 다시 넣을 때 범위가 된다
  TextColumn get period => text()();

  TextColumn get umdNm => text()();

  /// 마스킹된 지번(`3**`)도 원문 그대로 담는다. 화면에 그대로 보여야 한다
  TextColumn get jibun => text().nullable()();
  TextColumn get name => text().nullable()();

  /// 계약일 `YYYY-MM-DD`
  TextColumn get contractedOn => text()();

  RealColumn get areaSqm => real().nullable()();
  IntColumn get floor => integer().nullable()();
  IntColumn get builtYear => integer().nullable()();

  /// 만원 단위. 원천이 그렇게 준다
  IntColumn get amount => integer().nullable()();
  IntColumn get deposit => integer().nullable()();
  IntColumn get monthlyRent => integer().nullable()();

  BoolColumn get cancelled => boolean()();
  TextColumn get cancelledOn => text().nullable()();

  /// 좌표. **`null`이 곧 "미확인"이다.** 등급은 좌표 유무와 무관하게 남는다
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();

  /// `exact` · `jibun` · `partial` · `umd`. 행 단위 등급이다.
  /// `partial`·`umd`는 법정동 중심점이라 개별 핀으로 그리면 한 점에 쌓인다
  TextColumn get precision => text()();

  /// 원문 전 필드(JSON). 상세화면이 유형별 고유 항목을 여기서 읽는다(FR-3)
  TextColumn get raw => text()();
}

/// 지역의 갱신 상태. TTL 판정(§5.2)과 "기준 시각" 표시에 쓴다.
class RegionRows extends Table {
  TextColumn get sggCd => text().withLength(min: 5, max: 5)();

  /// 서버가 데이터를 만든 시각. **앱의 시계가 아니라 이 값이 기준이다**
  TextColumn get refreshedAt => text()();
  IntColumn get ttlSeconds => integer()();

  /// 이 기기가 마지막으로 받아 간 시각
  TextColumn get syncedAt => text()();

  @override
  Set<Column> get primaryKey => {sggCd};
}

/// 이미 반영한 청크.
///
/// 경로에 콘텐츠 해시가 박혀 있으므로(§5.3) **경로가 있다는 것이 곧 내용이 같다는 뜻**이다.
/// 매니페스트의 경로가 여기 있으면 내려받지 않는다.
class ChunkRows extends Table {
  TextColumn get path => text()();
  TextColumn get sggCd => text().withLength(min: 5, max: 5)();
  TextColumn get datasetKey => text()();
  TextColumn get period => text()();
  TextColumn get sha256 => text()();
  IntColumn get records => integer()();
  TextColumn get appliedAt => text()();

  @override
  Set<Column> get primaryKey => {path};
}
