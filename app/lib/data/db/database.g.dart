// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TxRowsTable extends TxRows with TableInfo<$TxRowsTable, TxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TxRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ridMeta = const VerificationMeta('rid');
  @override
  late final GeneratedColumn<int> rid = GeneratedColumn<int>(
    'rid',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _txIdMeta = const VerificationMeta('txId');
  @override
  late final GeneratedColumn<String> txId = GeneratedColumn<String>(
    'tx_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _sggCdMeta = const VerificationMeta('sggCd');
  @override
  late final GeneratedColumn<String> sggCd = GeneratedColumn<String>(
    'sgg_cd',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 5,
      maxTextLength: 5,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _datasetKeyMeta = const VerificationMeta(
    'datasetKey',
  );
  @override
  late final GeneratedColumn<String> datasetKey = GeneratedColumn<String>(
    'dataset_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
    'period',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _umdNmMeta = const VerificationMeta('umdNm');
  @override
  late final GeneratedColumn<String> umdNm = GeneratedColumn<String>(
    'umd_nm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jibunMeta = const VerificationMeta('jibun');
  @override
  late final GeneratedColumn<String> jibun = GeneratedColumn<String>(
    'jibun',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contractedOnMeta = const VerificationMeta(
    'contractedOn',
  );
  @override
  late final GeneratedColumn<String> contractedOn = GeneratedColumn<String>(
    'contracted_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaSqmMeta = const VerificationMeta(
    'areaSqm',
  );
  @override
  late final GeneratedColumn<double> areaSqm = GeneratedColumn<double>(
    'area_sqm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _floorMeta = const VerificationMeta('floor');
  @override
  late final GeneratedColumn<int> floor = GeneratedColumn<int>(
    'floor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _builtYearMeta = const VerificationMeta(
    'builtYear',
  );
  @override
  late final GeneratedColumn<int> builtYear = GeneratedColumn<int>(
    'built_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _depositMeta = const VerificationMeta(
    'deposit',
  );
  @override
  late final GeneratedColumn<int> deposit = GeneratedColumn<int>(
    'deposit',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _monthlyRentMeta = const VerificationMeta(
    'monthlyRent',
  );
  @override
  late final GeneratedColumn<int> monthlyRent = GeneratedColumn<int>(
    'monthly_rent',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cancelledMeta = const VerificationMeta(
    'cancelled',
  );
  @override
  late final GeneratedColumn<bool> cancelled = GeneratedColumn<bool>(
    'cancelled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cancelled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _cancelledOnMeta = const VerificationMeta(
    'cancelledOn',
  );
  @override
  late final GeneratedColumn<String> cancelledOn = GeneratedColumn<String>(
    'cancelled_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _precisionMeta = const VerificationMeta(
    'precision',
  );
  @override
  late final GeneratedColumn<String> precision = GeneratedColumn<String>(
    'precision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawMeta = const VerificationMeta('raw');
  @override
  late final GeneratedColumn<String> raw = GeneratedColumn<String>(
    'raw',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    rid,
    txId,
    sggCd,
    datasetKey,
    period,
    umdNm,
    jibun,
    name,
    contractedOn,
    areaSqm,
    floor,
    builtYear,
    amount,
    deposit,
    monthlyRent,
    cancelled,
    cancelledOn,
    lat,
    lng,
    precision,
    raw,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tx_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<TxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rid')) {
      context.handle(
        _ridMeta,
        rid.isAcceptableOrUnknown(data['rid']!, _ridMeta),
      );
    }
    if (data.containsKey('tx_id')) {
      context.handle(
        _txIdMeta,
        txId.isAcceptableOrUnknown(data['tx_id']!, _txIdMeta),
      );
    } else if (isInserting) {
      context.missing(_txIdMeta);
    }
    if (data.containsKey('sgg_cd')) {
      context.handle(
        _sggCdMeta,
        sggCd.isAcceptableOrUnknown(data['sgg_cd']!, _sggCdMeta),
      );
    } else if (isInserting) {
      context.missing(_sggCdMeta);
    }
    if (data.containsKey('dataset_key')) {
      context.handle(
        _datasetKeyMeta,
        datasetKey.isAcceptableOrUnknown(data['dataset_key']!, _datasetKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetKeyMeta);
    }
    if (data.containsKey('period')) {
      context.handle(
        _periodMeta,
        period.isAcceptableOrUnknown(data['period']!, _periodMeta),
      );
    } else if (isInserting) {
      context.missing(_periodMeta);
    }
    if (data.containsKey('umd_nm')) {
      context.handle(
        _umdNmMeta,
        umdNm.isAcceptableOrUnknown(data['umd_nm']!, _umdNmMeta),
      );
    } else if (isInserting) {
      context.missing(_umdNmMeta);
    }
    if (data.containsKey('jibun')) {
      context.handle(
        _jibunMeta,
        jibun.isAcceptableOrUnknown(data['jibun']!, _jibunMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('contracted_on')) {
      context.handle(
        _contractedOnMeta,
        contractedOn.isAcceptableOrUnknown(
          data['contracted_on']!,
          _contractedOnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contractedOnMeta);
    }
    if (data.containsKey('area_sqm')) {
      context.handle(
        _areaSqmMeta,
        areaSqm.isAcceptableOrUnknown(data['area_sqm']!, _areaSqmMeta),
      );
    }
    if (data.containsKey('floor')) {
      context.handle(
        _floorMeta,
        floor.isAcceptableOrUnknown(data['floor']!, _floorMeta),
      );
    }
    if (data.containsKey('built_year')) {
      context.handle(
        _builtYearMeta,
        builtYear.isAcceptableOrUnknown(data['built_year']!, _builtYearMeta),
      );
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    }
    if (data.containsKey('deposit')) {
      context.handle(
        _depositMeta,
        deposit.isAcceptableOrUnknown(data['deposit']!, _depositMeta),
      );
    }
    if (data.containsKey('monthly_rent')) {
      context.handle(
        _monthlyRentMeta,
        monthlyRent.isAcceptableOrUnknown(
          data['monthly_rent']!,
          _monthlyRentMeta,
        ),
      );
    }
    if (data.containsKey('cancelled')) {
      context.handle(
        _cancelledMeta,
        cancelled.isAcceptableOrUnknown(data['cancelled']!, _cancelledMeta),
      );
    } else if (isInserting) {
      context.missing(_cancelledMeta);
    }
    if (data.containsKey('cancelled_on')) {
      context.handle(
        _cancelledOnMeta,
        cancelledOn.isAcceptableOrUnknown(
          data['cancelled_on']!,
          _cancelledOnMeta,
        ),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    }
    if (data.containsKey('precision')) {
      context.handle(
        _precisionMeta,
        precision.isAcceptableOrUnknown(data['precision']!, _precisionMeta),
      );
    } else if (isInserting) {
      context.missing(_precisionMeta);
    }
    if (data.containsKey('raw')) {
      context.handle(
        _rawMeta,
        raw.isAcceptableOrUnknown(data['raw']!, _rawMeta),
      );
    } else if (isInserting) {
      context.missing(_rawMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rid};
  @override
  TxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TxRow(
      rid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rid'],
      )!,
      txId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tx_id'],
      )!,
      sggCd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sgg_cd'],
      )!,
      datasetKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset_key'],
      )!,
      period: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period'],
      )!,
      umdNm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}umd_nm'],
      )!,
      jibun: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jibun'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      contractedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contracted_on'],
      )!,
      areaSqm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}area_sqm'],
      ),
      floor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}floor'],
      ),
      builtYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}built_year'],
      ),
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      ),
      deposit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deposit'],
      ),
      monthlyRent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}monthly_rent'],
      ),
      cancelled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cancelled'],
      )!,
      cancelledOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cancelled_on'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      precision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}precision'],
      )!,
      raw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw'],
      )!,
    );
  }

  @override
  $TxRowsTable createAlias(String alias) {
    return $TxRowsTable(attachedDatabase, alias);
  }
}

class TxRow extends DataClass implements Insertable<TxRow> {
  final int rid;

  /// 서버가 정한 식별자. 같은 거래는 어느 기기에서도 같은 값이다
  final String txId;
  final String sggCd;
  final String datasetKey;

  /// 계약 연월 `YYYYMM`. 청크 단위로 지우고 다시 넣을 때 범위가 된다
  final String period;
  final String umdNm;

  /// 마스킹된 지번(`3**`)도 원문 그대로 담는다. 화면에 그대로 보여야 한다
  final String? jibun;
  final String? name;

  /// 계약일 `YYYY-MM-DD`
  final String contractedOn;
  final double? areaSqm;
  final int? floor;
  final int? builtYear;

  /// 만원 단위. 원천이 그렇게 준다
  final int? amount;
  final int? deposit;
  final int? monthlyRent;
  final bool cancelled;
  final String? cancelledOn;

  /// 좌표. **`null`이 곧 "미확인"이다.** 등급은 좌표 유무와 무관하게 남는다
  final double? lat;
  final double? lng;

  /// `exact` · `jibun` · `partial` · `umd`. 행 단위 등급이다.
  /// `partial`·`umd`는 법정동 중심점이라 개별 핀으로 그리면 한 점에 쌓인다
  final String precision;

  /// 원문 전 필드(JSON). 상세화면이 유형별 고유 항목을 여기서 읽는다(FR-3)
  final String raw;
  const TxRow({
    required this.rid,
    required this.txId,
    required this.sggCd,
    required this.datasetKey,
    required this.period,
    required this.umdNm,
    this.jibun,
    this.name,
    required this.contractedOn,
    this.areaSqm,
    this.floor,
    this.builtYear,
    this.amount,
    this.deposit,
    this.monthlyRent,
    required this.cancelled,
    this.cancelledOn,
    this.lat,
    this.lng,
    required this.precision,
    required this.raw,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rid'] = Variable<int>(rid);
    map['tx_id'] = Variable<String>(txId);
    map['sgg_cd'] = Variable<String>(sggCd);
    map['dataset_key'] = Variable<String>(datasetKey);
    map['period'] = Variable<String>(period);
    map['umd_nm'] = Variable<String>(umdNm);
    if (!nullToAbsent || jibun != null) {
      map['jibun'] = Variable<String>(jibun);
    }
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['contracted_on'] = Variable<String>(contractedOn);
    if (!nullToAbsent || areaSqm != null) {
      map['area_sqm'] = Variable<double>(areaSqm);
    }
    if (!nullToAbsent || floor != null) {
      map['floor'] = Variable<int>(floor);
    }
    if (!nullToAbsent || builtYear != null) {
      map['built_year'] = Variable<int>(builtYear);
    }
    if (!nullToAbsent || amount != null) {
      map['amount'] = Variable<int>(amount);
    }
    if (!nullToAbsent || deposit != null) {
      map['deposit'] = Variable<int>(deposit);
    }
    if (!nullToAbsent || monthlyRent != null) {
      map['monthly_rent'] = Variable<int>(monthlyRent);
    }
    map['cancelled'] = Variable<bool>(cancelled);
    if (!nullToAbsent || cancelledOn != null) {
      map['cancelled_on'] = Variable<String>(cancelledOn);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    map['precision'] = Variable<String>(precision);
    map['raw'] = Variable<String>(raw);
    return map;
  }

  TxRowsCompanion toCompanion(bool nullToAbsent) {
    return TxRowsCompanion(
      rid: Value(rid),
      txId: Value(txId),
      sggCd: Value(sggCd),
      datasetKey: Value(datasetKey),
      period: Value(period),
      umdNm: Value(umdNm),
      jibun: jibun == null && nullToAbsent
          ? const Value.absent()
          : Value(jibun),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      contractedOn: Value(contractedOn),
      areaSqm: areaSqm == null && nullToAbsent
          ? const Value.absent()
          : Value(areaSqm),
      floor: floor == null && nullToAbsent
          ? const Value.absent()
          : Value(floor),
      builtYear: builtYear == null && nullToAbsent
          ? const Value.absent()
          : Value(builtYear),
      amount: amount == null && nullToAbsent
          ? const Value.absent()
          : Value(amount),
      deposit: deposit == null && nullToAbsent
          ? const Value.absent()
          : Value(deposit),
      monthlyRent: monthlyRent == null && nullToAbsent
          ? const Value.absent()
          : Value(monthlyRent),
      cancelled: Value(cancelled),
      cancelledOn: cancelledOn == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelledOn),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      precision: Value(precision),
      raw: Value(raw),
    );
  }

  factory TxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TxRow(
      rid: serializer.fromJson<int>(json['rid']),
      txId: serializer.fromJson<String>(json['txId']),
      sggCd: serializer.fromJson<String>(json['sggCd']),
      datasetKey: serializer.fromJson<String>(json['datasetKey']),
      period: serializer.fromJson<String>(json['period']),
      umdNm: serializer.fromJson<String>(json['umdNm']),
      jibun: serializer.fromJson<String?>(json['jibun']),
      name: serializer.fromJson<String?>(json['name']),
      contractedOn: serializer.fromJson<String>(json['contractedOn']),
      areaSqm: serializer.fromJson<double?>(json['areaSqm']),
      floor: serializer.fromJson<int?>(json['floor']),
      builtYear: serializer.fromJson<int?>(json['builtYear']),
      amount: serializer.fromJson<int?>(json['amount']),
      deposit: serializer.fromJson<int?>(json['deposit']),
      monthlyRent: serializer.fromJson<int?>(json['monthlyRent']),
      cancelled: serializer.fromJson<bool>(json['cancelled']),
      cancelledOn: serializer.fromJson<String?>(json['cancelledOn']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      precision: serializer.fromJson<String>(json['precision']),
      raw: serializer.fromJson<String>(json['raw']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rid': serializer.toJson<int>(rid),
      'txId': serializer.toJson<String>(txId),
      'sggCd': serializer.toJson<String>(sggCd),
      'datasetKey': serializer.toJson<String>(datasetKey),
      'period': serializer.toJson<String>(period),
      'umdNm': serializer.toJson<String>(umdNm),
      'jibun': serializer.toJson<String?>(jibun),
      'name': serializer.toJson<String?>(name),
      'contractedOn': serializer.toJson<String>(contractedOn),
      'areaSqm': serializer.toJson<double?>(areaSqm),
      'floor': serializer.toJson<int?>(floor),
      'builtYear': serializer.toJson<int?>(builtYear),
      'amount': serializer.toJson<int?>(amount),
      'deposit': serializer.toJson<int?>(deposit),
      'monthlyRent': serializer.toJson<int?>(monthlyRent),
      'cancelled': serializer.toJson<bool>(cancelled),
      'cancelledOn': serializer.toJson<String?>(cancelledOn),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'precision': serializer.toJson<String>(precision),
      'raw': serializer.toJson<String>(raw),
    };
  }

  TxRow copyWith({
    int? rid,
    String? txId,
    String? sggCd,
    String? datasetKey,
    String? period,
    String? umdNm,
    Value<String?> jibun = const Value.absent(),
    Value<String?> name = const Value.absent(),
    String? contractedOn,
    Value<double?> areaSqm = const Value.absent(),
    Value<int?> floor = const Value.absent(),
    Value<int?> builtYear = const Value.absent(),
    Value<int?> amount = const Value.absent(),
    Value<int?> deposit = const Value.absent(),
    Value<int?> monthlyRent = const Value.absent(),
    bool? cancelled,
    Value<String?> cancelledOn = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    String? precision,
    String? raw,
  }) => TxRow(
    rid: rid ?? this.rid,
    txId: txId ?? this.txId,
    sggCd: sggCd ?? this.sggCd,
    datasetKey: datasetKey ?? this.datasetKey,
    period: period ?? this.period,
    umdNm: umdNm ?? this.umdNm,
    jibun: jibun.present ? jibun.value : this.jibun,
    name: name.present ? name.value : this.name,
    contractedOn: contractedOn ?? this.contractedOn,
    areaSqm: areaSqm.present ? areaSqm.value : this.areaSqm,
    floor: floor.present ? floor.value : this.floor,
    builtYear: builtYear.present ? builtYear.value : this.builtYear,
    amount: amount.present ? amount.value : this.amount,
    deposit: deposit.present ? deposit.value : this.deposit,
    monthlyRent: monthlyRent.present ? monthlyRent.value : this.monthlyRent,
    cancelled: cancelled ?? this.cancelled,
    cancelledOn: cancelledOn.present ? cancelledOn.value : this.cancelledOn,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    precision: precision ?? this.precision,
    raw: raw ?? this.raw,
  );
  TxRow copyWithCompanion(TxRowsCompanion data) {
    return TxRow(
      rid: data.rid.present ? data.rid.value : this.rid,
      txId: data.txId.present ? data.txId.value : this.txId,
      sggCd: data.sggCd.present ? data.sggCd.value : this.sggCd,
      datasetKey: data.datasetKey.present
          ? data.datasetKey.value
          : this.datasetKey,
      period: data.period.present ? data.period.value : this.period,
      umdNm: data.umdNm.present ? data.umdNm.value : this.umdNm,
      jibun: data.jibun.present ? data.jibun.value : this.jibun,
      name: data.name.present ? data.name.value : this.name,
      contractedOn: data.contractedOn.present
          ? data.contractedOn.value
          : this.contractedOn,
      areaSqm: data.areaSqm.present ? data.areaSqm.value : this.areaSqm,
      floor: data.floor.present ? data.floor.value : this.floor,
      builtYear: data.builtYear.present ? data.builtYear.value : this.builtYear,
      amount: data.amount.present ? data.amount.value : this.amount,
      deposit: data.deposit.present ? data.deposit.value : this.deposit,
      monthlyRent: data.monthlyRent.present
          ? data.monthlyRent.value
          : this.monthlyRent,
      cancelled: data.cancelled.present ? data.cancelled.value : this.cancelled,
      cancelledOn: data.cancelledOn.present
          ? data.cancelledOn.value
          : this.cancelledOn,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      precision: data.precision.present ? data.precision.value : this.precision,
      raw: data.raw.present ? data.raw.value : this.raw,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TxRow(')
          ..write('rid: $rid, ')
          ..write('txId: $txId, ')
          ..write('sggCd: $sggCd, ')
          ..write('datasetKey: $datasetKey, ')
          ..write('period: $period, ')
          ..write('umdNm: $umdNm, ')
          ..write('jibun: $jibun, ')
          ..write('name: $name, ')
          ..write('contractedOn: $contractedOn, ')
          ..write('areaSqm: $areaSqm, ')
          ..write('floor: $floor, ')
          ..write('builtYear: $builtYear, ')
          ..write('amount: $amount, ')
          ..write('deposit: $deposit, ')
          ..write('monthlyRent: $monthlyRent, ')
          ..write('cancelled: $cancelled, ')
          ..write('cancelledOn: $cancelledOn, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('precision: $precision, ')
          ..write('raw: $raw')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    rid,
    txId,
    sggCd,
    datasetKey,
    period,
    umdNm,
    jibun,
    name,
    contractedOn,
    areaSqm,
    floor,
    builtYear,
    amount,
    deposit,
    monthlyRent,
    cancelled,
    cancelledOn,
    lat,
    lng,
    precision,
    raw,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TxRow &&
          other.rid == this.rid &&
          other.txId == this.txId &&
          other.sggCd == this.sggCd &&
          other.datasetKey == this.datasetKey &&
          other.period == this.period &&
          other.umdNm == this.umdNm &&
          other.jibun == this.jibun &&
          other.name == this.name &&
          other.contractedOn == this.contractedOn &&
          other.areaSqm == this.areaSqm &&
          other.floor == this.floor &&
          other.builtYear == this.builtYear &&
          other.amount == this.amount &&
          other.deposit == this.deposit &&
          other.monthlyRent == this.monthlyRent &&
          other.cancelled == this.cancelled &&
          other.cancelledOn == this.cancelledOn &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.precision == this.precision &&
          other.raw == this.raw);
}

class TxRowsCompanion extends UpdateCompanion<TxRow> {
  final Value<int> rid;
  final Value<String> txId;
  final Value<String> sggCd;
  final Value<String> datasetKey;
  final Value<String> period;
  final Value<String> umdNm;
  final Value<String?> jibun;
  final Value<String?> name;
  final Value<String> contractedOn;
  final Value<double?> areaSqm;
  final Value<int?> floor;
  final Value<int?> builtYear;
  final Value<int?> amount;
  final Value<int?> deposit;
  final Value<int?> monthlyRent;
  final Value<bool> cancelled;
  final Value<String?> cancelledOn;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<String> precision;
  final Value<String> raw;
  const TxRowsCompanion({
    this.rid = const Value.absent(),
    this.txId = const Value.absent(),
    this.sggCd = const Value.absent(),
    this.datasetKey = const Value.absent(),
    this.period = const Value.absent(),
    this.umdNm = const Value.absent(),
    this.jibun = const Value.absent(),
    this.name = const Value.absent(),
    this.contractedOn = const Value.absent(),
    this.areaSqm = const Value.absent(),
    this.floor = const Value.absent(),
    this.builtYear = const Value.absent(),
    this.amount = const Value.absent(),
    this.deposit = const Value.absent(),
    this.monthlyRent = const Value.absent(),
    this.cancelled = const Value.absent(),
    this.cancelledOn = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.precision = const Value.absent(),
    this.raw = const Value.absent(),
  });
  TxRowsCompanion.insert({
    this.rid = const Value.absent(),
    required String txId,
    required String sggCd,
    required String datasetKey,
    required String period,
    required String umdNm,
    this.jibun = const Value.absent(),
    this.name = const Value.absent(),
    required String contractedOn,
    this.areaSqm = const Value.absent(),
    this.floor = const Value.absent(),
    this.builtYear = const Value.absent(),
    this.amount = const Value.absent(),
    this.deposit = const Value.absent(),
    this.monthlyRent = const Value.absent(),
    required bool cancelled,
    this.cancelledOn = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    required String precision,
    required String raw,
  }) : txId = Value(txId),
       sggCd = Value(sggCd),
       datasetKey = Value(datasetKey),
       period = Value(period),
       umdNm = Value(umdNm),
       contractedOn = Value(contractedOn),
       cancelled = Value(cancelled),
       precision = Value(precision),
       raw = Value(raw);
  static Insertable<TxRow> custom({
    Expression<int>? rid,
    Expression<String>? txId,
    Expression<String>? sggCd,
    Expression<String>? datasetKey,
    Expression<String>? period,
    Expression<String>? umdNm,
    Expression<String>? jibun,
    Expression<String>? name,
    Expression<String>? contractedOn,
    Expression<double>? areaSqm,
    Expression<int>? floor,
    Expression<int>? builtYear,
    Expression<int>? amount,
    Expression<int>? deposit,
    Expression<int>? monthlyRent,
    Expression<bool>? cancelled,
    Expression<String>? cancelledOn,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? precision,
    Expression<String>? raw,
  }) {
    return RawValuesInsertable({
      if (rid != null) 'rid': rid,
      if (txId != null) 'tx_id': txId,
      if (sggCd != null) 'sgg_cd': sggCd,
      if (datasetKey != null) 'dataset_key': datasetKey,
      if (period != null) 'period': period,
      if (umdNm != null) 'umd_nm': umdNm,
      if (jibun != null) 'jibun': jibun,
      if (name != null) 'name': name,
      if (contractedOn != null) 'contracted_on': contractedOn,
      if (areaSqm != null) 'area_sqm': areaSqm,
      if (floor != null) 'floor': floor,
      if (builtYear != null) 'built_year': builtYear,
      if (amount != null) 'amount': amount,
      if (deposit != null) 'deposit': deposit,
      if (monthlyRent != null) 'monthly_rent': monthlyRent,
      if (cancelled != null) 'cancelled': cancelled,
      if (cancelledOn != null) 'cancelled_on': cancelledOn,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (precision != null) 'precision': precision,
      if (raw != null) 'raw': raw,
    });
  }

  TxRowsCompanion copyWith({
    Value<int>? rid,
    Value<String>? txId,
    Value<String>? sggCd,
    Value<String>? datasetKey,
    Value<String>? period,
    Value<String>? umdNm,
    Value<String?>? jibun,
    Value<String?>? name,
    Value<String>? contractedOn,
    Value<double?>? areaSqm,
    Value<int?>? floor,
    Value<int?>? builtYear,
    Value<int?>? amount,
    Value<int?>? deposit,
    Value<int?>? monthlyRent,
    Value<bool>? cancelled,
    Value<String?>? cancelledOn,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<String>? precision,
    Value<String>? raw,
  }) {
    return TxRowsCompanion(
      rid: rid ?? this.rid,
      txId: txId ?? this.txId,
      sggCd: sggCd ?? this.sggCd,
      datasetKey: datasetKey ?? this.datasetKey,
      period: period ?? this.period,
      umdNm: umdNm ?? this.umdNm,
      jibun: jibun ?? this.jibun,
      name: name ?? this.name,
      contractedOn: contractedOn ?? this.contractedOn,
      areaSqm: areaSqm ?? this.areaSqm,
      floor: floor ?? this.floor,
      builtYear: builtYear ?? this.builtYear,
      amount: amount ?? this.amount,
      deposit: deposit ?? this.deposit,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      cancelled: cancelled ?? this.cancelled,
      cancelledOn: cancelledOn ?? this.cancelledOn,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      precision: precision ?? this.precision,
      raw: raw ?? this.raw,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rid.present) {
      map['rid'] = Variable<int>(rid.value);
    }
    if (txId.present) {
      map['tx_id'] = Variable<String>(txId.value);
    }
    if (sggCd.present) {
      map['sgg_cd'] = Variable<String>(sggCd.value);
    }
    if (datasetKey.present) {
      map['dataset_key'] = Variable<String>(datasetKey.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (umdNm.present) {
      map['umd_nm'] = Variable<String>(umdNm.value);
    }
    if (jibun.present) {
      map['jibun'] = Variable<String>(jibun.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (contractedOn.present) {
      map['contracted_on'] = Variable<String>(contractedOn.value);
    }
    if (areaSqm.present) {
      map['area_sqm'] = Variable<double>(areaSqm.value);
    }
    if (floor.present) {
      map['floor'] = Variable<int>(floor.value);
    }
    if (builtYear.present) {
      map['built_year'] = Variable<int>(builtYear.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (deposit.present) {
      map['deposit'] = Variable<int>(deposit.value);
    }
    if (monthlyRent.present) {
      map['monthly_rent'] = Variable<int>(monthlyRent.value);
    }
    if (cancelled.present) {
      map['cancelled'] = Variable<bool>(cancelled.value);
    }
    if (cancelledOn.present) {
      map['cancelled_on'] = Variable<String>(cancelledOn.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (precision.present) {
      map['precision'] = Variable<String>(precision.value);
    }
    if (raw.present) {
      map['raw'] = Variable<String>(raw.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TxRowsCompanion(')
          ..write('rid: $rid, ')
          ..write('txId: $txId, ')
          ..write('sggCd: $sggCd, ')
          ..write('datasetKey: $datasetKey, ')
          ..write('period: $period, ')
          ..write('umdNm: $umdNm, ')
          ..write('jibun: $jibun, ')
          ..write('name: $name, ')
          ..write('contractedOn: $contractedOn, ')
          ..write('areaSqm: $areaSqm, ')
          ..write('floor: $floor, ')
          ..write('builtYear: $builtYear, ')
          ..write('amount: $amount, ')
          ..write('deposit: $deposit, ')
          ..write('monthlyRent: $monthlyRent, ')
          ..write('cancelled: $cancelled, ')
          ..write('cancelledOn: $cancelledOn, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('precision: $precision, ')
          ..write('raw: $raw')
          ..write(')'))
        .toString();
  }
}

class $RegionRowsTable extends RegionRows
    with TableInfo<$RegionRowsTable, RegionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RegionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sggCdMeta = const VerificationMeta('sggCd');
  @override
  late final GeneratedColumn<String> sggCd = GeneratedColumn<String>(
    'sgg_cd',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 5,
      maxTextLength: 5,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<String> refreshedAt = GeneratedColumn<String>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ttlSecondsMeta = const VerificationMeta(
    'ttlSeconds',
  );
  @override
  late final GeneratedColumn<int> ttlSeconds = GeneratedColumn<int>(
    'ttl_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<String> syncedAt = GeneratedColumn<String>(
    'synced_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sggCd,
    refreshedAt,
    ttlSeconds,
    syncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'region_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<RegionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sgg_cd')) {
      context.handle(
        _sggCdMeta,
        sggCd.isAcceptableOrUnknown(data['sgg_cd']!, _sggCdMeta),
      );
    } else if (isInserting) {
      context.missing(_sggCdMeta);
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    if (data.containsKey('ttl_seconds')) {
      context.handle(
        _ttlSecondsMeta,
        ttlSeconds.isAcceptableOrUnknown(data['ttl_seconds']!, _ttlSecondsMeta),
      );
    } else if (isInserting) {
      context.missing(_ttlSecondsMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sggCd};
  @override
  RegionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RegionRow(
      sggCd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sgg_cd'],
      )!,
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refreshed_at'],
      )!,
      ttlSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ttl_seconds'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}synced_at'],
      )!,
    );
  }

  @override
  $RegionRowsTable createAlias(String alias) {
    return $RegionRowsTable(attachedDatabase, alias);
  }
}

class RegionRow extends DataClass implements Insertable<RegionRow> {
  final String sggCd;

  /// 서버가 데이터를 만든 시각. **앱의 시계가 아니라 이 값이 기준이다**
  final String refreshedAt;
  final int ttlSeconds;

  /// 이 기기가 마지막으로 받아 간 시각
  final String syncedAt;
  const RegionRow({
    required this.sggCd,
    required this.refreshedAt,
    required this.ttlSeconds,
    required this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sgg_cd'] = Variable<String>(sggCd);
    map['refreshed_at'] = Variable<String>(refreshedAt);
    map['ttl_seconds'] = Variable<int>(ttlSeconds);
    map['synced_at'] = Variable<String>(syncedAt);
    return map;
  }

  RegionRowsCompanion toCompanion(bool nullToAbsent) {
    return RegionRowsCompanion(
      sggCd: Value(sggCd),
      refreshedAt: Value(refreshedAt),
      ttlSeconds: Value(ttlSeconds),
      syncedAt: Value(syncedAt),
    );
  }

  factory RegionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RegionRow(
      sggCd: serializer.fromJson<String>(json['sggCd']),
      refreshedAt: serializer.fromJson<String>(json['refreshedAt']),
      ttlSeconds: serializer.fromJson<int>(json['ttlSeconds']),
      syncedAt: serializer.fromJson<String>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sggCd': serializer.toJson<String>(sggCd),
      'refreshedAt': serializer.toJson<String>(refreshedAt),
      'ttlSeconds': serializer.toJson<int>(ttlSeconds),
      'syncedAt': serializer.toJson<String>(syncedAt),
    };
  }

  RegionRow copyWith({
    String? sggCd,
    String? refreshedAt,
    int? ttlSeconds,
    String? syncedAt,
  }) => RegionRow(
    sggCd: sggCd ?? this.sggCd,
    refreshedAt: refreshedAt ?? this.refreshedAt,
    ttlSeconds: ttlSeconds ?? this.ttlSeconds,
    syncedAt: syncedAt ?? this.syncedAt,
  );
  RegionRow copyWithCompanion(RegionRowsCompanion data) {
    return RegionRow(
      sggCd: data.sggCd.present ? data.sggCd.value : this.sggCd,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
      ttlSeconds: data.ttlSeconds.present
          ? data.ttlSeconds.value
          : this.ttlSeconds,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RegionRow(')
          ..write('sggCd: $sggCd, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('ttlSeconds: $ttlSeconds, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sggCd, refreshedAt, ttlSeconds, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RegionRow &&
          other.sggCd == this.sggCd &&
          other.refreshedAt == this.refreshedAt &&
          other.ttlSeconds == this.ttlSeconds &&
          other.syncedAt == this.syncedAt);
}

class RegionRowsCompanion extends UpdateCompanion<RegionRow> {
  final Value<String> sggCd;
  final Value<String> refreshedAt;
  final Value<int> ttlSeconds;
  final Value<String> syncedAt;
  final Value<int> rowid;
  const RegionRowsCompanion({
    this.sggCd = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.ttlSeconds = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RegionRowsCompanion.insert({
    required String sggCd,
    required String refreshedAt,
    required int ttlSeconds,
    required String syncedAt,
    this.rowid = const Value.absent(),
  }) : sggCd = Value(sggCd),
       refreshedAt = Value(refreshedAt),
       ttlSeconds = Value(ttlSeconds),
       syncedAt = Value(syncedAt);
  static Insertable<RegionRow> custom({
    Expression<String>? sggCd,
    Expression<String>? refreshedAt,
    Expression<int>? ttlSeconds,
    Expression<String>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sggCd != null) 'sgg_cd': sggCd,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
      if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RegionRowsCompanion copyWith({
    Value<String>? sggCd,
    Value<String>? refreshedAt,
    Value<int>? ttlSeconds,
    Value<String>? syncedAt,
    Value<int>? rowid,
  }) {
    return RegionRowsCompanion(
      sggCd: sggCd ?? this.sggCd,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sggCd.present) {
      map['sgg_cd'] = Variable<String>(sggCd.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<String>(refreshedAt.value);
    }
    if (ttlSeconds.present) {
      map['ttl_seconds'] = Variable<int>(ttlSeconds.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<String>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RegionRowsCompanion(')
          ..write('sggCd: $sggCd, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('ttlSeconds: $ttlSeconds, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChunkRowsTable extends ChunkRows
    with TableInfo<$ChunkRowsTable, ChunkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChunkRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sggCdMeta = const VerificationMeta('sggCd');
  @override
  late final GeneratedColumn<String> sggCd = GeneratedColumn<String>(
    'sgg_cd',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 5,
      maxTextLength: 5,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _datasetKeyMeta = const VerificationMeta(
    'datasetKey',
  );
  @override
  late final GeneratedColumn<String> datasetKey = GeneratedColumn<String>(
    'dataset_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<String> period = GeneratedColumn<String>(
    'period',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordsMeta = const VerificationMeta(
    'records',
  );
  @override
  late final GeneratedColumn<int> records = GeneratedColumn<int>(
    'records',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appliedAtMeta = const VerificationMeta(
    'appliedAt',
  );
  @override
  late final GeneratedColumn<String> appliedAt = GeneratedColumn<String>(
    'applied_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    sggCd,
    datasetKey,
    period,
    sha256,
    records,
    appliedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chunk_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChunkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('sgg_cd')) {
      context.handle(
        _sggCdMeta,
        sggCd.isAcceptableOrUnknown(data['sgg_cd']!, _sggCdMeta),
      );
    } else if (isInserting) {
      context.missing(_sggCdMeta);
    }
    if (data.containsKey('dataset_key')) {
      context.handle(
        _datasetKeyMeta,
        datasetKey.isAcceptableOrUnknown(data['dataset_key']!, _datasetKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetKeyMeta);
    }
    if (data.containsKey('period')) {
      context.handle(
        _periodMeta,
        period.isAcceptableOrUnknown(data['period']!, _periodMeta),
      );
    } else if (isInserting) {
      context.missing(_periodMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('records')) {
      context.handle(
        _recordsMeta,
        records.isAcceptableOrUnknown(data['records']!, _recordsMeta),
      );
    } else if (isInserting) {
      context.missing(_recordsMeta);
    }
    if (data.containsKey('applied_at')) {
      context.handle(
        _appliedAtMeta,
        appliedAt.isAcceptableOrUnknown(data['applied_at']!, _appliedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_appliedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  ChunkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChunkRow(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      sggCd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sgg_cd'],
      )!,
      datasetKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset_key'],
      )!,
      period: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      records: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}records'],
      )!,
      appliedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}applied_at'],
      )!,
    );
  }

  @override
  $ChunkRowsTable createAlias(String alias) {
    return $ChunkRowsTable(attachedDatabase, alias);
  }
}

class ChunkRow extends DataClass implements Insertable<ChunkRow> {
  final String path;
  final String sggCd;
  final String datasetKey;
  final String period;
  final String sha256;
  final int records;
  final String appliedAt;
  const ChunkRow({
    required this.path,
    required this.sggCd,
    required this.datasetKey,
    required this.period,
    required this.sha256,
    required this.records,
    required this.appliedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['sgg_cd'] = Variable<String>(sggCd);
    map['dataset_key'] = Variable<String>(datasetKey);
    map['period'] = Variable<String>(period);
    map['sha256'] = Variable<String>(sha256);
    map['records'] = Variable<int>(records);
    map['applied_at'] = Variable<String>(appliedAt);
    return map;
  }

  ChunkRowsCompanion toCompanion(bool nullToAbsent) {
    return ChunkRowsCompanion(
      path: Value(path),
      sggCd: Value(sggCd),
      datasetKey: Value(datasetKey),
      period: Value(period),
      sha256: Value(sha256),
      records: Value(records),
      appliedAt: Value(appliedAt),
    );
  }

  factory ChunkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChunkRow(
      path: serializer.fromJson<String>(json['path']),
      sggCd: serializer.fromJson<String>(json['sggCd']),
      datasetKey: serializer.fromJson<String>(json['datasetKey']),
      period: serializer.fromJson<String>(json['period']),
      sha256: serializer.fromJson<String>(json['sha256']),
      records: serializer.fromJson<int>(json['records']),
      appliedAt: serializer.fromJson<String>(json['appliedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'sggCd': serializer.toJson<String>(sggCd),
      'datasetKey': serializer.toJson<String>(datasetKey),
      'period': serializer.toJson<String>(period),
      'sha256': serializer.toJson<String>(sha256),
      'records': serializer.toJson<int>(records),
      'appliedAt': serializer.toJson<String>(appliedAt),
    };
  }

  ChunkRow copyWith({
    String? path,
    String? sggCd,
    String? datasetKey,
    String? period,
    String? sha256,
    int? records,
    String? appliedAt,
  }) => ChunkRow(
    path: path ?? this.path,
    sggCd: sggCd ?? this.sggCd,
    datasetKey: datasetKey ?? this.datasetKey,
    period: period ?? this.period,
    sha256: sha256 ?? this.sha256,
    records: records ?? this.records,
    appliedAt: appliedAt ?? this.appliedAt,
  );
  ChunkRow copyWithCompanion(ChunkRowsCompanion data) {
    return ChunkRow(
      path: data.path.present ? data.path.value : this.path,
      sggCd: data.sggCd.present ? data.sggCd.value : this.sggCd,
      datasetKey: data.datasetKey.present
          ? data.datasetKey.value
          : this.datasetKey,
      period: data.period.present ? data.period.value : this.period,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      records: data.records.present ? data.records.value : this.records,
      appliedAt: data.appliedAt.present ? data.appliedAt.value : this.appliedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChunkRow(')
          ..write('path: $path, ')
          ..write('sggCd: $sggCd, ')
          ..write('datasetKey: $datasetKey, ')
          ..write('period: $period, ')
          ..write('sha256: $sha256, ')
          ..write('records: $records, ')
          ..write('appliedAt: $appliedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(path, sggCd, datasetKey, period, sha256, records, appliedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChunkRow &&
          other.path == this.path &&
          other.sggCd == this.sggCd &&
          other.datasetKey == this.datasetKey &&
          other.period == this.period &&
          other.sha256 == this.sha256 &&
          other.records == this.records &&
          other.appliedAt == this.appliedAt);
}

class ChunkRowsCompanion extends UpdateCompanion<ChunkRow> {
  final Value<String> path;
  final Value<String> sggCd;
  final Value<String> datasetKey;
  final Value<String> period;
  final Value<String> sha256;
  final Value<int> records;
  final Value<String> appliedAt;
  final Value<int> rowid;
  const ChunkRowsCompanion({
    this.path = const Value.absent(),
    this.sggCd = const Value.absent(),
    this.datasetKey = const Value.absent(),
    this.period = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.records = const Value.absent(),
    this.appliedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChunkRowsCompanion.insert({
    required String path,
    required String sggCd,
    required String datasetKey,
    required String period,
    required String sha256,
    required int records,
    required String appliedAt,
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       sggCd = Value(sggCd),
       datasetKey = Value(datasetKey),
       period = Value(period),
       sha256 = Value(sha256),
       records = Value(records),
       appliedAt = Value(appliedAt);
  static Insertable<ChunkRow> custom({
    Expression<String>? path,
    Expression<String>? sggCd,
    Expression<String>? datasetKey,
    Expression<String>? period,
    Expression<String>? sha256,
    Expression<int>? records,
    Expression<String>? appliedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (sggCd != null) 'sgg_cd': sggCd,
      if (datasetKey != null) 'dataset_key': datasetKey,
      if (period != null) 'period': period,
      if (sha256 != null) 'sha256': sha256,
      if (records != null) 'records': records,
      if (appliedAt != null) 'applied_at': appliedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChunkRowsCompanion copyWith({
    Value<String>? path,
    Value<String>? sggCd,
    Value<String>? datasetKey,
    Value<String>? period,
    Value<String>? sha256,
    Value<int>? records,
    Value<String>? appliedAt,
    Value<int>? rowid,
  }) {
    return ChunkRowsCompanion(
      path: path ?? this.path,
      sggCd: sggCd ?? this.sggCd,
      datasetKey: datasetKey ?? this.datasetKey,
      period: period ?? this.period,
      sha256: sha256 ?? this.sha256,
      records: records ?? this.records,
      appliedAt: appliedAt ?? this.appliedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (sggCd.present) {
      map['sgg_cd'] = Variable<String>(sggCd.value);
    }
    if (datasetKey.present) {
      map['dataset_key'] = Variable<String>(datasetKey.value);
    }
    if (period.present) {
      map['period'] = Variable<String>(period.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (records.present) {
      map['records'] = Variable<int>(records.value);
    }
    if (appliedAt.present) {
      map['applied_at'] = Variable<String>(appliedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChunkRowsCompanion(')
          ..write('path: $path, ')
          ..write('sggCd: $sggCd, ')
          ..write('datasetKey: $datasetKey, ')
          ..write('period: $period, ')
          ..write('sha256: $sha256, ')
          ..write('records: $records, ')
          ..write('appliedAt: $appliedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TxRowsTable txRows = $TxRowsTable(this);
  late final $RegionRowsTable regionRows = $RegionRowsTable(this);
  late final $ChunkRowsTable chunkRows = $ChunkRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    txRows,
    regionRows,
    chunkRows,
  ];
}

typedef $$TxRowsTableCreateCompanionBuilder =
    TxRowsCompanion Function({
      Value<int> rid,
      required String txId,
      required String sggCd,
      required String datasetKey,
      required String period,
      required String umdNm,
      Value<String?> jibun,
      Value<String?> name,
      required String contractedOn,
      Value<double?> areaSqm,
      Value<int?> floor,
      Value<int?> builtYear,
      Value<int?> amount,
      Value<int?> deposit,
      Value<int?> monthlyRent,
      required bool cancelled,
      Value<String?> cancelledOn,
      Value<double?> lat,
      Value<double?> lng,
      required String precision,
      required String raw,
    });
typedef $$TxRowsTableUpdateCompanionBuilder =
    TxRowsCompanion Function({
      Value<int> rid,
      Value<String> txId,
      Value<String> sggCd,
      Value<String> datasetKey,
      Value<String> period,
      Value<String> umdNm,
      Value<String?> jibun,
      Value<String?> name,
      Value<String> contractedOn,
      Value<double?> areaSqm,
      Value<int?> floor,
      Value<int?> builtYear,
      Value<int?> amount,
      Value<int?> deposit,
      Value<int?> monthlyRent,
      Value<bool> cancelled,
      Value<String?> cancelledOn,
      Value<double?> lat,
      Value<double?> lng,
      Value<String> precision,
      Value<String> raw,
    });

class $$TxRowsTableFilterComposer
    extends Composer<_$AppDatabase, $TxRowsTable> {
  $$TxRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rid => $composableBuilder(
    column: $table.rid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txId => $composableBuilder(
    column: $table.txId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sggCd => $composableBuilder(
    column: $table.sggCd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get umdNm => $composableBuilder(
    column: $table.umdNm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jibun => $composableBuilder(
    column: $table.jibun,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contractedOn => $composableBuilder(
    column: $table.contractedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get areaSqm => $composableBuilder(
    column: $table.areaSqm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get floor => $composableBuilder(
    column: $table.floor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get builtYear => $composableBuilder(
    column: $table.builtYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deposit => $composableBuilder(
    column: $table.deposit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get monthlyRent => $composableBuilder(
    column: $table.monthlyRent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cancelled => $composableBuilder(
    column: $table.cancelled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cancelledOn => $composableBuilder(
    column: $table.cancelledOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get precision => $composableBuilder(
    column: $table.precision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TxRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $TxRowsTable> {
  $$TxRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rid => $composableBuilder(
    column: $table.rid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txId => $composableBuilder(
    column: $table.txId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sggCd => $composableBuilder(
    column: $table.sggCd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get umdNm => $composableBuilder(
    column: $table.umdNm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jibun => $composableBuilder(
    column: $table.jibun,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contractedOn => $composableBuilder(
    column: $table.contractedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get areaSqm => $composableBuilder(
    column: $table.areaSqm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get floor => $composableBuilder(
    column: $table.floor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get builtYear => $composableBuilder(
    column: $table.builtYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deposit => $composableBuilder(
    column: $table.deposit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get monthlyRent => $composableBuilder(
    column: $table.monthlyRent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cancelled => $composableBuilder(
    column: $table.cancelled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cancelledOn => $composableBuilder(
    column: $table.cancelledOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get precision => $composableBuilder(
    column: $table.precision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TxRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TxRowsTable> {
  $$TxRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rid =>
      $composableBuilder(column: $table.rid, builder: (column) => column);

  GeneratedColumn<String> get txId =>
      $composableBuilder(column: $table.txId, builder: (column) => column);

  GeneratedColumn<String> get sggCd =>
      $composableBuilder(column: $table.sggCd, builder: (column) => column);

  GeneratedColumn<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<String> get umdNm =>
      $composableBuilder(column: $table.umdNm, builder: (column) => column);

  GeneratedColumn<String> get jibun =>
      $composableBuilder(column: $table.jibun, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get contractedOn => $composableBuilder(
    column: $table.contractedOn,
    builder: (column) => column,
  );

  GeneratedColumn<double> get areaSqm =>
      $composableBuilder(column: $table.areaSqm, builder: (column) => column);

  GeneratedColumn<int> get floor =>
      $composableBuilder(column: $table.floor, builder: (column) => column);

  GeneratedColumn<int> get builtYear =>
      $composableBuilder(column: $table.builtYear, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get deposit =>
      $composableBuilder(column: $table.deposit, builder: (column) => column);

  GeneratedColumn<int> get monthlyRent => $composableBuilder(
    column: $table.monthlyRent,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get cancelled =>
      $composableBuilder(column: $table.cancelled, builder: (column) => column);

  GeneratedColumn<String> get cancelledOn => $composableBuilder(
    column: $table.cancelledOn,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<String> get precision =>
      $composableBuilder(column: $table.precision, builder: (column) => column);

  GeneratedColumn<String> get raw =>
      $composableBuilder(column: $table.raw, builder: (column) => column);
}

class $$TxRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TxRowsTable,
          TxRow,
          $$TxRowsTableFilterComposer,
          $$TxRowsTableOrderingComposer,
          $$TxRowsTableAnnotationComposer,
          $$TxRowsTableCreateCompanionBuilder,
          $$TxRowsTableUpdateCompanionBuilder,
          (TxRow, BaseReferences<_$AppDatabase, $TxRowsTable, TxRow>),
          TxRow,
          PrefetchHooks Function()
        > {
  $$TxRowsTableTableManager(_$AppDatabase db, $TxRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TxRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TxRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TxRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> rid = const Value.absent(),
                Value<String> txId = const Value.absent(),
                Value<String> sggCd = const Value.absent(),
                Value<String> datasetKey = const Value.absent(),
                Value<String> period = const Value.absent(),
                Value<String> umdNm = const Value.absent(),
                Value<String?> jibun = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String> contractedOn = const Value.absent(),
                Value<double?> areaSqm = const Value.absent(),
                Value<int?> floor = const Value.absent(),
                Value<int?> builtYear = const Value.absent(),
                Value<int?> amount = const Value.absent(),
                Value<int?> deposit = const Value.absent(),
                Value<int?> monthlyRent = const Value.absent(),
                Value<bool> cancelled = const Value.absent(),
                Value<String?> cancelledOn = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<String> precision = const Value.absent(),
                Value<String> raw = const Value.absent(),
              }) => TxRowsCompanion(
                rid: rid,
                txId: txId,
                sggCd: sggCd,
                datasetKey: datasetKey,
                period: period,
                umdNm: umdNm,
                jibun: jibun,
                name: name,
                contractedOn: contractedOn,
                areaSqm: areaSqm,
                floor: floor,
                builtYear: builtYear,
                amount: amount,
                deposit: deposit,
                monthlyRent: monthlyRent,
                cancelled: cancelled,
                cancelledOn: cancelledOn,
                lat: lat,
                lng: lng,
                precision: precision,
                raw: raw,
              ),
          createCompanionCallback:
              ({
                Value<int> rid = const Value.absent(),
                required String txId,
                required String sggCd,
                required String datasetKey,
                required String period,
                required String umdNm,
                Value<String?> jibun = const Value.absent(),
                Value<String?> name = const Value.absent(),
                required String contractedOn,
                Value<double?> areaSqm = const Value.absent(),
                Value<int?> floor = const Value.absent(),
                Value<int?> builtYear = const Value.absent(),
                Value<int?> amount = const Value.absent(),
                Value<int?> deposit = const Value.absent(),
                Value<int?> monthlyRent = const Value.absent(),
                required bool cancelled,
                Value<String?> cancelledOn = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                required String precision,
                required String raw,
              }) => TxRowsCompanion.insert(
                rid: rid,
                txId: txId,
                sggCd: sggCd,
                datasetKey: datasetKey,
                period: period,
                umdNm: umdNm,
                jibun: jibun,
                name: name,
                contractedOn: contractedOn,
                areaSqm: areaSqm,
                floor: floor,
                builtYear: builtYear,
                amount: amount,
                deposit: deposit,
                monthlyRent: monthlyRent,
                cancelled: cancelled,
                cancelledOn: cancelledOn,
                lat: lat,
                lng: lng,
                precision: precision,
                raw: raw,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TxRowsTable, TxRow>(table),
                  BaseReferences<_$AppDatabase, $TxRowsTable, TxRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TxRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TxRowsTable,
      TxRow,
      $$TxRowsTableFilterComposer,
      $$TxRowsTableOrderingComposer,
      $$TxRowsTableAnnotationComposer,
      $$TxRowsTableCreateCompanionBuilder,
      $$TxRowsTableUpdateCompanionBuilder,
      (TxRow, BaseReferences<_$AppDatabase, $TxRowsTable, TxRow>),
      TxRow,
      PrefetchHooks Function()
    >;
typedef $$RegionRowsTableCreateCompanionBuilder =
    RegionRowsCompanion Function({
      required String sggCd,
      required String refreshedAt,
      required int ttlSeconds,
      required String syncedAt,
      Value<int> rowid,
    });
typedef $$RegionRowsTableUpdateCompanionBuilder =
    RegionRowsCompanion Function({
      Value<String> sggCd,
      Value<String> refreshedAt,
      Value<int> ttlSeconds,
      Value<String> syncedAt,
      Value<int> rowid,
    });

class $$RegionRowsTableFilterComposer
    extends Composer<_$AppDatabase, $RegionRowsTable> {
  $$RegionRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sggCd => $composableBuilder(
    column: $table.sggCd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ttlSeconds => $composableBuilder(
    column: $table.ttlSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RegionRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $RegionRowsTable> {
  $$RegionRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sggCd => $composableBuilder(
    column: $table.sggCd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ttlSeconds => $composableBuilder(
    column: $table.ttlSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RegionRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RegionRowsTable> {
  $$RegionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sggCd =>
      $composableBuilder(column: $table.sggCd, builder: (column) => column);

  GeneratedColumn<String> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ttlSeconds => $composableBuilder(
    column: $table.ttlSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$RegionRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RegionRowsTable,
          RegionRow,
          $$RegionRowsTableFilterComposer,
          $$RegionRowsTableOrderingComposer,
          $$RegionRowsTableAnnotationComposer,
          $$RegionRowsTableCreateCompanionBuilder,
          $$RegionRowsTableUpdateCompanionBuilder,
          (
            RegionRow,
            BaseReferences<_$AppDatabase, $RegionRowsTable, RegionRow>,
          ),
          RegionRow,
          PrefetchHooks Function()
        > {
  $$RegionRowsTableTableManager(_$AppDatabase db, $RegionRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RegionRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RegionRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RegionRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sggCd = const Value.absent(),
                Value<String> refreshedAt = const Value.absent(),
                Value<int> ttlSeconds = const Value.absent(),
                Value<String> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RegionRowsCompanion(
                sggCd: sggCd,
                refreshedAt: refreshedAt,
                ttlSeconds: ttlSeconds,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sggCd,
                required String refreshedAt,
                required int ttlSeconds,
                required String syncedAt,
                Value<int> rowid = const Value.absent(),
              }) => RegionRowsCompanion.insert(
                sggCd: sggCd,
                refreshedAt: refreshedAt,
                ttlSeconds: ttlSeconds,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RegionRowsTable, RegionRow>(table),
                  BaseReferences<_$AppDatabase, $RegionRowsTable, RegionRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RegionRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RegionRowsTable,
      RegionRow,
      $$RegionRowsTableFilterComposer,
      $$RegionRowsTableOrderingComposer,
      $$RegionRowsTableAnnotationComposer,
      $$RegionRowsTableCreateCompanionBuilder,
      $$RegionRowsTableUpdateCompanionBuilder,
      (RegionRow, BaseReferences<_$AppDatabase, $RegionRowsTable, RegionRow>),
      RegionRow,
      PrefetchHooks Function()
    >;
typedef $$ChunkRowsTableCreateCompanionBuilder =
    ChunkRowsCompanion Function({
      required String path,
      required String sggCd,
      required String datasetKey,
      required String period,
      required String sha256,
      required int records,
      required String appliedAt,
      Value<int> rowid,
    });
typedef $$ChunkRowsTableUpdateCompanionBuilder =
    ChunkRowsCompanion Function({
      Value<String> path,
      Value<String> sggCd,
      Value<String> datasetKey,
      Value<String> period,
      Value<String> sha256,
      Value<int> records,
      Value<String> appliedAt,
      Value<int> rowid,
    });

class $$ChunkRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ChunkRowsTable> {
  $$ChunkRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sggCd => $composableBuilder(
    column: $table.sggCd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get records => $composableBuilder(
    column: $table.records,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChunkRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChunkRowsTable> {
  $$ChunkRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sggCd => $composableBuilder(
    column: $table.sggCd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get records => $composableBuilder(
    column: $table.records,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChunkRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChunkRowsTable> {
  $$ChunkRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get sggCd =>
      $composableBuilder(column: $table.sggCd, builder: (column) => column);

  GeneratedColumn<String> get datasetKey => $composableBuilder(
    column: $table.datasetKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get records =>
      $composableBuilder(column: $table.records, builder: (column) => column);

  GeneratedColumn<String> get appliedAt =>
      $composableBuilder(column: $table.appliedAt, builder: (column) => column);
}

class $$ChunkRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChunkRowsTable,
          ChunkRow,
          $$ChunkRowsTableFilterComposer,
          $$ChunkRowsTableOrderingComposer,
          $$ChunkRowsTableAnnotationComposer,
          $$ChunkRowsTableCreateCompanionBuilder,
          $$ChunkRowsTableUpdateCompanionBuilder,
          (ChunkRow, BaseReferences<_$AppDatabase, $ChunkRowsTable, ChunkRow>),
          ChunkRow,
          PrefetchHooks Function()
        > {
  $$ChunkRowsTableTableManager(_$AppDatabase db, $ChunkRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChunkRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChunkRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChunkRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<String> sggCd = const Value.absent(),
                Value<String> datasetKey = const Value.absent(),
                Value<String> period = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int> records = const Value.absent(),
                Value<String> appliedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChunkRowsCompanion(
                path: path,
                sggCd: sggCd,
                datasetKey: datasetKey,
                period: period,
                sha256: sha256,
                records: records,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required String sggCd,
                required String datasetKey,
                required String period,
                required String sha256,
                required int records,
                required String appliedAt,
                Value<int> rowid = const Value.absent(),
              }) => ChunkRowsCompanion.insert(
                path: path,
                sggCd: sggCd,
                datasetKey: datasetKey,
                period: period,
                sha256: sha256,
                records: records,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChunkRowsTable, ChunkRow>(table),
                  BaseReferences<_$AppDatabase, $ChunkRowsTable, ChunkRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChunkRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChunkRowsTable,
      ChunkRow,
      $$ChunkRowsTableFilterComposer,
      $$ChunkRowsTableOrderingComposer,
      $$ChunkRowsTableAnnotationComposer,
      $$ChunkRowsTableCreateCompanionBuilder,
      $$ChunkRowsTableUpdateCompanionBuilder,
      (ChunkRow, BaseReferences<_$AppDatabase, $ChunkRowsTable, ChunkRow>),
      ChunkRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TxRowsTableTableManager get txRows =>
      $$TxRowsTableTableManager(_db, _db.txRows);
  $$RegionRowsTableTableManager get regionRows =>
      $$RegionRowsTableTableManager(_db, _db.regionRows);
  $$ChunkRowsTableTableManager get chunkRows =>
      $$ChunkRowsTableTableManager(_db, _db.chunkRows);
}
