import 'package:flutter_test/flutter_test.dart';
import 'package:realdealmap/format.dart';
import 'package:realdealmap/state/filters.dart';

void main() {
  group('금액', () {
    // 억 단위로만 줄이면 "3억 2천"과 "3억 2백"이 같아 보인다.
    test('억과 만원을 함께 쓴다', () {
      expect(formatMoney(325000), '32억 5,000만원');
      expect(formatMoney(320000), '32억');
      expect(formatMoney(9500), '9,500만원');
      expect(formatMoney(30200), '3억 200만원');
    });

    test('없으면 빈 문자열이다', () {
      expect(formatMoney(null), '');
    });

    // 해제 거래에서 실제로 0이 나온다. 빈칸으로 두면 값이 없는 것과 구별되지 않는다.
    test('0은 0원이다', () {
      expect(formatMoney(0), '0원');
    });

    test('음수도 읽힌다', () {
      expect(formatMoney(-5000), '-5,000만원');
    });
  });

  group('전월세', () {
    test('월세가 0이면 전세다', () {
      expect(formatRent(50000, 0), '전세 5억');
      expect(formatRent(50000, null), '전세 5억');
    });

    test('월세가 있으면 보증금과 나란히 쓴다', () {
      expect(formatRent(10000, 150), '1억 / 150만원');
    });
  });

  group('면적', () {
    test('제곱미터를 쓰고 평을 붙인다', () {
      expect(formatArea(84.97), '84.97m² (25.7평)');
    });

    test('소수점 뒤 0은 지운다', () {
      expect(formatArea(84), '84m² (25.4평)');
    });
  });

  group('인상폭', () {
    // 이 화면에서 가장 값어치 있는 한 줄이다.
    test('종전 대비 금액과 비율을 준다', () {
      expect(formatChange(50000, 55000), '+5,000만원 (+10.0%)');
      expect(formatChange(50000, 45000), '-5,000만원 (-10.0%)');
    });

    test('같으면 동결이다', () {
      expect(formatChange(50000, 50000), '동결');
    });

    // 0에서 오른 것을 무한대로 쓸 수는 없다.
    test('종전이 없거나 0이면 계산하지 않는다', () {
      expect(formatChange(null, 50000), isNull);
      expect(formatChange(0, 50000), isNull);
    });
  });

  group('날짜', () {
    test('여러 형식을 하나로 만든다', () {
      expect(formatDate('20260814'), '2026.08.14');
      expect(formatDate('2026-08-14'), '2026.08.14');
    });

    // 원천이 형식을 바꿔도 원문을 보여주는 편이 빈칸보다 낫다.
    test('모르는 형식은 원문 그대로 낸다', () {
      expect(formatDate('언젠가'), '언젠가');
    });

    test('연월을 읽는다', () {
      expect(formatMonth('202608'), '2026년 8월');
    });
  });

  group('기준 시각', () {
    final base = DateTime.utc(2026, 9, 7, 12);

    test('경과 시간을 짧게 쓴다', () {
      expect(formatAge(base, base.add(const Duration(seconds: 30))), '방금');
      expect(formatAge(base, base.add(const Duration(minutes: 5))), '5분 전');
      expect(formatAge(base, base.add(const Duration(hours: 3))), '3시간 전');
      expect(formatAge(base, base.add(const Duration(days: 2))), '2일 전');
    });

    // 기기 시계가 서버보다 뒤처져 있으면 음수가 나온다. "-3분 전"을 보여줄 수는 없다.
    test('미래여도 깨지지 않는다', () {
      expect(formatAge(base, base.subtract(const Duration(hours: 1))), '방금');
    });
  });

  group('필터', () {
    // "아무것도 안 보임"과 "전부 보임"을 같은 값으로 두면 필터를 다 끈 사용자가
    // 빈 지도를 보게 된다.
    test('비어 있으면 전부다', () {
      expect(const TxFilter().datasetKeysOrNull, isNull);
      expect(const TxFilter().isEmpty, isTrue);
    });

    test('유형을 켜고 끈다', () {
      final on = const TxFilter().toggleDataset('apartment/sale');
      expect(on.datasetKeys, {'apartment/sale'});
      expect(on.toggleDataset('apartment/sale').datasetKeys, isEmpty);
    });

    test('같은 내용이면 같은 필터다', () {
      expect(
        const TxFilter(datasetKeys: {'a', 'b'}),
        const TxFilter(datasetKeys: {'b', 'a'}),
      );
    });

    test('이름표를 붙인다', () {
      expect(datasetLabel('apartment/sale'), '아파트 매매');
      expect(datasetLabel('land/sale'), '토지 매매');
      expect(datasetLabel('알 수 없음'), '알 수 없음');
    });
  });

  // 지도 위 문장은 스치듯 읽힌다. 20648과 20,648은 읽는 속도가 다르다.
  group('건수 표기', () {
    test('천 단위로 끊는다', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1,000');
      expect(formatCount(20648), '20,648');
      expect(formatCount(1234567), '1,234,567');
    });

    test('음수도 끊는다', () {
      expect(formatCount(-1234), '-1,234');
    });
  });

  // "북구은"과 "담양군는"은 읽는 사람에게 틀린 글이다. 지역 이름은 데이터에서
  // 오므로 문장을 미리 써 둘 수 없고, 붙일 때 정해야 한다.
  group('조사', () {
    test('받침이 없으면 는', () {
      expect(topic('북구'), '북구는');
      expect(topic('강남구'), '강남구는');
      expect(topic('제주시'), '제주시는');
    });

    test('받침이 있으면 은', () {
      expect(topic('담양군'), '담양군은');
      expect(topic('종로구'), '종로구는');
      expect(topic('광산구'), '광산구는');
      expect(topic('여수시'), '여수시는');
      expect(topic('영등포'), '영등포는');
      expect(topic('안산'), '안산은');
    });

    test('한글이 아니면 판단하지 않고 받침 쪽으로 둔다', () {
      expect(topic('Seoul'), 'Seoul은');
      expect(topic(''), '은');
    });
  });
}
