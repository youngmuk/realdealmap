import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/data/db/database.dart';
import 'package:realdealmap/features/detail/detail_model.dart';

/// 원천이 실제로 주는 필드 이름. `packages/ingest/src/datasets.ts`와 1:1이다.
/// 한쪽만 늘어나면 그 항목이 상세화면에서 조용히 사라지므로 여기서 붙잡는다.
const Map<String, List<String>> kRawFields = {
  'apartment/sale': [
    'sggCd',
    'umdCd',
    'landCd',
    'bonbun',
    'bubun',
    'roadNm',
    'roadNmSggCd',
    'roadNmCd',
    'roadNmSeq',
    'roadNmbCd',
    'roadNmBonbun',
    'roadNmBubun',
    'umdNm',
    'aptNm',
    'jibun',
    'excluUseAr',
    'dealYear',
    'dealMonth',
    'dealDay',
    'dealAmount',
    'floor',
    'buildYear',
    'aptSeq',
    'cdealType',
    'cdealDay',
    'dealingGbn',
    'estateAgentSggNm',
    'rgstDate',
    'aptDong',
    'slerGbn',
    'buyerGbn',
    'landLeaseholdGbn',
  ],
  'apartment/rent': [
    'sggCd',
    'umdNm',
    'aptNm',
    'aptSeq',
    'jibun',
    'excluUseAr',
    'roadnm',
    'roadnmsggcd',
    'roadnmcd',
    'roadnmseq',
    'roadnmbcd',
    'roadnmbonbun',
    'roadnmbubun',
    'dealYear',
    'dealMonth',
    'dealDay',
    'deposit',
    'monthlyRent',
    'floor',
    'buildYear',
    'contractTerm',
    'contractType',
    'useRRRight',
    'preDeposit',
    'preMonthlyRent',
  ],
  'officetel/sale': [
    'sggCd',
    'sggNm',
    'umdNm',
    'jibun',
    'offiNm',
    'excluUseAr',
    'dealYear',
    'dealMonth',
    'dealDay',
    'dealAmount',
    'floor',
    'buildYear',
    'cdealType',
    'cdealDay',
    'dealingGbn',
    'estateAgentSggNm',
    'slerGbn',
    'buyerGbn',
  ],
  'officetel/rent': [
    'sggCd',
    'sggNm',
    'umdNm',
    'jibun',
    'offiNm',
    'excluUseAr',
    'dealYear',
    'dealMonth',
    'dealDay',
    'deposit',
    'monthlyRent',
    'floor',
    'buildYear',
    'contractTerm',
    'contractType',
    'useRRRight',
    'preDeposit',
    'preMonthlyRent',
  ],
  'rowhouse/sale': [
    'sggCd',
    'umdNm',
    'mhouseNm',
    'houseType',
    'jibun',
    'buildYear',
    'excluUseAr',
    'landAr',
    'dealYear',
    'dealMonth',
    'dealDay',
    'dealAmount',
    'floor',
    'cdealType',
    'cdealDay',
    'dealingGbn',
    'estateAgentSggNm',
    'rgstDate',
    'slerGbn',
    'buyerGbn',
  ],
  'rowhouse/rent': [
    'sggCd',
    'umdNm',
    'mhouseNm',
    'houseType',
    'jibun',
    'buildYear',
    'excluUseAr',
    'dealYear',
    'dealMonth',
    'dealDay',
    'deposit',
    'monthlyRent',
    'floor',
    'contractTerm',
    'contractType',
    'useRRRight',
    'preDeposit',
    'preMonthlyRent',
  ],
  'detached/sale': [
    'sggCd',
    'umdNm',
    'houseType',
    'jibun',
    'totalFloorAr',
    'plottageAr',
    'dealYear',
    'dealMonth',
    'dealDay',
    'dealAmount',
    'buildYear',
    'cdealType',
    'cdealDay',
    'dealingGbn',
    'estateAgentSggNm',
    'slerGbn',
    'buyerGbn',
  ],
  'detached/rent': [
    'sggCd',
    'umdNm',
    'houseType',
    'totalFloorAr',
    'dealYear',
    'dealMonth',
    'dealDay',
    'deposit',
    'monthlyRent',
    'buildYear',
    'contractTerm',
    'contractType',
    'useRRRight',
    'preDeposit',
    'preMonthlyRent',
  ],
  'land/sale': [
    'sggCd',
    'sggNm',
    'umdNm',
    'jibun',
    'jimok',
    'landUse',
    'dealYear',
    'dealMonth',
    'dealDay',
    'dealArea',
    'dealAmount',
    'shareDealingType',
    'cdealType',
    'cdealDay',
    'dealingGbn',
    'estateAgentSggNm',
  ],
};

/// 정규화된 열에서 렌더링되는 필드. 원문 값이 아니라 정규화 값이 나오므로
/// 표식으로 추적할 수 없다. 이들이 화면에 나온다는 것은 다른 테스트가 본다.
const Set<String> kFromNormalized = {
  'sggCd',
  'umdNm',
  'jibun',
  'aptNm',
  'offiNm',
  'mhouseNm',
};

/// 숫자로 와야 하는 필드. 나머지는 표식 문자열을 넣어 화면까지 도달하는지 본다.
const Map<String, String> kNumericValues = {
  'dealAmount': '320,000',
  'deposit': '50000',
  'monthlyRent': '150',
  'preDeposit': '45000',
  'preMonthlyRent': '100',
  'excluUseAr': '84.97',
  'dealArea': '330.5',
  'totalFloorAr': '210.4',
  'plottageAr': '180.2',
  'landAr': '45.6',
  'floor': '12',
  'buildYear': '2004',
  'dealYear': '2026',
  'dealMonth': '8',
  'dealDay': '14',
};

Map<String, String> rawFor(String datasetKey) => {
  for (final field in kRawFields[datasetKey]!)
    field: kNumericValues[field] ?? 'v_$field',
};

TxRowsCompanion companion(
  String datasetKey, {
  double? lat = 37.5,
  double? lng = 127.0,
  String precision = 'exact',
  bool cancelled = false,
  int? deposit,
  int? monthlyRent,
  int? amount,
  Map<String, String>? raw,
}) {
  final isRent = datasetKey.endsWith('/rent');
  return TxRowsCompanion.insert(
    txId: 'tx-$datasetKey',
    sggCd: '11680',
    datasetKey: datasetKey,
    period: '202608',
    umdNm: '논현동',
    contractedOn: '2026-08-14',
    cancelled: cancelled,
    precision: precision,
    raw: jsonEncode(raw ?? rawFor(datasetKey)),
    jibun: const Value('123'),
    name: const Value('테스트아파트'),
    areaSqm: const Value(84.97),
    floor: const Value(12),
    builtYear: const Value(2004),
    amount: Value(isRent ? null : (amount ?? 320000)),
    deposit: Value(isRent ? (deposit ?? 50000) : null),
    monthlyRent: Value(isRent ? (monthlyRent ?? 150) : null),
    lat: Value(lat),
    lng: Value(lng),
  );
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<TxRow> insert(TxRowsCompanion c) async {
    await db.into(db.txRows).insert(c);
    return (await db.byTxId(c.txId.value))!;
  }

  String rendered(TxDetail detail) => [
    detail.header.title,
    detail.header.address,
    detail.header.price,
    detail.header.summary,
    for (final s in detail.sections)
      for (final r in s.rows) '${r.label}=${r.value}',
    for (final e in detail.raw.entries) '${e.key}=${e.value}',
  ].join('\n');

  group('9종 전부', () {
    // 원천이 준 항목이 화면 어디에도 없으면 그 정보는 사용자에게 도달하지 않는다.
    // 표에 자리를 못 잡은 것은 "원문 전체"로라도 나가야 한다(FR-3).
    for (final datasetKey in kRawFields.keys) {
      test('$datasetKey — 원문 항목이 하나도 사라지지 않는다', () async {
        final detail = buildDetail(await insert(companion(datasetKey)));
        final output = rendered(detail);

        final missing = kRawFields[datasetKey]!
            .where((f) => !kNumericValues.containsKey(f))
            .where((f) => !kFromNormalized.contains(f))
            .where((f) => !output.contains('v_$f'))
            .toList();

        expect(missing, isEmpty, reason: '화면에 없는 항목: $missing');
      });

      test('$datasetKey — 금액과 요약이 비지 않는다', () async {
        final detail = buildDetail(await insert(companion(datasetKey)));
        expect(detail.header.price, isNotEmpty);
        expect(detail.header.summary, isNotEmpty);
        expect(detail.sections, isNotEmpty);
      });
    }
  });

  group('요약 머리', () {
    test('매매는 거래금액을 낸다', () async {
      final detail = buildDetail(await insert(companion('apartment/sale')));
      expect(detail.header.price, '32억');
      expect(detail.header.datasetLabel, '아파트 매매');
    });

    test('전월세는 보증금과 월세를 낸다', () async {
      final detail = buildDetail(await insert(companion('apartment/rent')));
      expect(detail.header.price, '5억 / 150만원');
    });

    test('월세가 없으면 전세로 낸다', () async {
      final detail = buildDetail(
        await insert(companion('apartment/rent', monthlyRent: 0)),
      );
      expect(detail.header.price, '전세 5억');
    });

    // 토지는 이름이 없다. 빈 제목을 두면 무엇을 보고 있는지 알 수 없다.
    test('이름이 없으면 법정동을 제목으로 쓴다', () async {
      final row = await insert(
        companion('land/sale').copyWith(name: const Value(null)),
      );
      expect(buildDetail(row).header.title, '논현동');
    });
  });

  group('갱신 계약', () {
    // 이 화면에서 가장 값어치 있는 한 줄이다.
    test('종전 대비 인상폭을 보여준다', () async {
      final detail = buildDetail(await insert(companion('apartment/rent')));
      final rows = detail.sections
          .expand((s) => s.rows)
          .where((r) => r.label == '보증금 변동');

      expect(rows, hasLength(1));
      expect(rows.single.value, '+5,000만원 (+11.1%)');
      expect(rows.single.emphasis, isTrue);
    });

    test('종전이 없으면 변동 행을 만들지 않는다', () async {
      final raw = rawFor('apartment/rent')
        ..remove('preDeposit')
        ..remove('preMonthlyRent');
      final detail = buildDetail(
        await insert(companion('apartment/rent', raw: raw)),
      );

      expect(
        detail.sections.expand((s) => s.rows).map((r) => r.label),
        isNot(contains('보증금 변동')),
      );
    });
  });

  group('빈 값', () {
    // "—"로 채운 행을 늘어놓으면 원천이 안 준 것인지 우리가 못 읽은 것인지
    // 구별되지 않고 화면만 길어진다.
    test('값이 없는 행은 넣지 않는다', () async {
      final detail = buildDetail(
        await insert(companion('apartment/sale', raw: {'aptNm': '테스트'})),
      );

      for (final section in detail.sections) {
        for (final row in section.rows) {
          expect(row.value.trim(), isNotEmpty, reason: '빈 행: ${row.label}');
        }
      }
    });

    test('빈 섹션은 통째로 없앤다', () async {
      final detail = buildDetail(
        await insert(companion('apartment/sale', raw: const {})),
      );
      for (final section in detail.sections) {
        expect(section.rows, isNotEmpty);
      }
    });

    // 원문을 못 읽어도 정규화된 필드는 멀쩡하다. 상세화면을 통째로 잃지 않는다.
    test('원문 JSON이 깨져도 표는 나온다', () async {
      await db
          .into(db.txRows)
          .insert(
            TxRowsCompanion.insert(
              txId: 'broken',
              sggCd: '11680',
              datasetKey: 'apartment/sale',
              period: '202608',
              umdNm: '논현동',
              contractedOn: '2026-08-14',
              cancelled: false,
              precision: 'exact',
              raw: '{ not json',
              amount: const Value(320000),
            ),
          );

      final detail = buildDetail((await db.byTxId('broken'))!);
      expect(detail.header.price, '32억');
      expect(detail.sections, isNotEmpty);
    });
  });

  group('좌표 정확도', () {
    // 지도의 위치를 믿으면 안 된다는 뜻이라 반드시 표시한다.
    test('근사 좌표임을 알린다', () async {
      for (final precision in ['partial', 'umd']) {
        final row = await insert(
          companion(
            'detached/sale',
            precision: precision,
          ).copyWith(txId: Value('p-$precision')),
        );
        final detail = buildDetail(row);
        expect(detail.header.approximate, isTrue);
        expect(
          detail.sections
              .expand((s) => s.rows)
              .firstWhere((r) => r.label == '좌표 정확도')
              .value,
          contains('법정동 근사'),
        );
      }
    });

    test('지번 기준이면 그렇게 쓴다', () async {
      final detail = buildDetail(await insert(companion('apartment/sale')));
      expect(detail.header.approximate, isFalse);
      expect(
        detail.sections
            .expand((s) => s.rows)
            .firstWhere((r) => r.label == '좌표 정확도')
            .value,
        '지번 기준',
      );
    });

    // 좌표가 없는 것과 근사 좌표는 다르다. 섞으면 목록에서 왜 안 보이는지 모른다.
    test('좌표가 없으면 지도에 없음을 밝힌다', () async {
      final detail = buildDetail(
        await insert(companion('detached/rent', lat: null, lng: null)),
      );
      expect(
        detail.sections
            .expand((s) => s.rows)
            .firstWhere((r) => r.label == '좌표 정확도')
            .value,
        contains('지도에 표시하지 않음'),
      );
    });
  });

  group('해제된 거래', () {
    test('해제 행을 만든다', () async {
      final row = await insert(
        companion(
          'apartment/sale',
          cancelled: true,
        ).copyWith(cancelledOn: const Value('2026-08-20')),
      );
      final detail = buildDetail(row);

      expect(detail.header.cancelled, isTrue);
      expect(
        detail.sections
            .expand((s) => s.rows)
            .firstWhere((r) => r.label == '해제')
            .value,
        contains('2026.08.20'),
      );
    });

    // 해제일 형식을 못 읽은 경우다. 해제 사실 자체는 사라지면 안 된다.
    test('해제일을 몰라도 해제 사실은 남긴다', () async {
      final row = await insert(companion('apartment/sale', cancelled: true));
      expect(
        buildDetail(row).sections.expand((s) => s.rows).map((r) => r.label),
        contains('해제'),
      );
    });
  });
}
