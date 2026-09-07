import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/state/filters.dart';

const _available = ['202608', '202607', '202606'];

void main() {
  group('계약 연월', () {
    // 비어 있는 것이 "전부"다. 이 규칙이 흔들리면 사용자가 필터를 다 끈 뒤
    // 빈 화면을 보게 된다.
    test('기본은 전부다', () {
      expect(const TxFilter().months, isEmpty);
      expect(const TxFilter().isEmpty, isTrue);
    });

    test('전부인 상태에서 하나를 누르면 그것만 남는다', () {
      final f = const TxFilter().toggleMonth('202607', _available);

      expect(f.months, {'202607'});
    });

    test('고른 것을 다시 누르면 전부로 돌아간다', () {
      final f = const TxFilter()
          .toggleMonth('202607', _available)
          .toggleMonth('202607', _available);

      expect(f.months, isEmpty, reason: '마지막 하나를 끄면 전부여야 한다');
    });

    test('둘째를 누르면 더해진다', () {
      final f = const TxFilter()
          .toggleMonth('202607', _available)
          .toggleMonth('202606', _available);

      expect(f.months, {'202607', '202606'});
    });

    // 같은 뜻을 두 값으로 두면 "전부 선택"과 "선택 없음"이 다르게 보인다.
    test('있는 달을 전부 고르면 전부와 같은 값이 된다', () {
      var f = const TxFilter().toggleMonth('202608', _available);
      f = f.toggleMonth('202607', _available);
      f = f.toggleMonth('202606', _available);

      expect(f.months, isEmpty);
      expect(f.isEmpty, isTrue);
    });
  });

  group('매물 유형 × 거래 종류', () {
    test('기본은 전부다', () {
      const f = TxFilter();

      expect(f.selectedProperties, hasLength(5));
      expect(f.selectedTrades, {'sale', 'rent'});
    });

    test('거래 종류를 좁히면 그 종류만 남는다', () {
      final f = const TxFilter().toggleTrade('rent');

      expect(f.selectedTrades, {'sale'});
      expect(f.datasetKeys, everyElement(endsWith('/sale')));
    });

    test('매물 유형을 좁히면 그 유형만 남는다', () {
      var f = const TxFilter();
      for (final p in ['officetel', 'rowhouse', 'detached', 'land']) {
        f = f.toggleProperty(p);
      }

      expect(f.selectedProperties, {'apartment'});
      expect(f.datasetKeys, {'apartment/sale', 'apartment/rent'});
    });

    // 빈 집합은 "전부"라는 뜻이라, 전부 끈 사용자에게 전부를 보여주게 된다.
    test('마지막 하나는 끌 수 없다', () {
      final f = const TxFilter().toggleTrade('rent');
      final again = f.toggleTrade('sale');

      expect(again, f, reason: '아무것도 안 남는 조합은 무시해야 한다');
    });

    // 토지는 전월세가 없다. 존재하지 않는 조합을 고르면 빈 집합이 되고,
    // 그 빈 집합은 "전부"로 읽혀 필터가 정반대로 동작한다.
    test('전월세만 고르면 토지는 아예 후보에서 빠진다', () {
      final f = const TxFilter().toggleTrade('sale');

      expect(f.selectedTrades, {'rent'});
      expect(f.selectedProperties, isNot(contains('land')));
      expect(f.availableProperties, isNot(contains('land')));
    });

    test('토지만 고르면 전월세를 고를 수 없다', () {
      var f = const TxFilter();
      for (final p in ['apartment', 'officetel', 'rowhouse', 'detached']) {
        f = f.toggleProperty(p);
      }

      expect(f.selectedProperties, {'land'});
      expect(f.availableTrades, {'sale'});
      // 없는 조합은 상태를 바꾸지 않는다
      expect(f.withTypes(trades: {'rent'}), f);
    });

    test('전부 다시 켜면 비어 있는 상태로 돌아간다', () {
      final f = const TxFilter().toggleTrade('rent').toggleTrade('rent');

      expect(f.datasetKeys, isEmpty);
      expect(f.isEmpty, isTrue);
    });
  });

  group('가격', () {
    test('양 끝은 제한 없음이다', () {
      final f = const TxFilter().withAmountRange();

      expect(f.minAmount, isNull);
      expect(f.maxAmount, isNull);
      expect(f.isEmpty, isTrue);
    });

    test('구간을 걸면 비어 있지 않다', () {
      final f = const TxFilter().withAmountRange(min: 10000, max: 50000);

      expect(f.minAmount, 10000);
      expect(f.maxAmount, 50000);
      expect(f.isEmpty, isFalse);
    });

    // copyWith의 기본값이 "유지"라 널을 넘겨도 안 지워지는 실수를 하기 쉽다.
    test('걸었던 구간을 다시 풀 수 있다', () {
      final f = const TxFilter()
          .withAmountRange(min: 10000, max: 50000)
          .withAmountRange();

      expect(f.minAmount, isNull);
      expect(f.maxAmount, isNull);
    });

    test('한쪽만 걸 수 있다', () {
      final f = const TxFilter().withAmountRange(min: 30000);

      expect(f.minAmount, 30000);
      expect(f.maxAmount, isNull);
      expect(f.isEmpty, isFalse);
    });
  });

  group('같음 판정', () {
    // 같으면 화면을 다시 그리지 않는다. 순서만 다른 집합을 다르다고 하면
    // 지도가 필터를 건드릴 때마다 통째로 다시 그려진다.
    test('집합의 순서는 상관없다', () {
      const a = TxFilter(months: {'202608', '202607'});
      const b = TxFilter(months: {'202607', '202608'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('가격이 다르면 다르다', () {
      const a = TxFilter(minAmount: 10000);
      const b = TxFilter(minAmount: 20000);

      expect(a, isNot(b));
    });
  });
}
