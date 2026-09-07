import { describe, expect, test } from 'vitest';

import { DATASETS, datasetKeys, operationOf } from './datasets.js';

/** T1.1 실호출 응답(11110 / 202608)에서 실측한 item 항목 수. */
const EXPECTED_FIELD_COUNT = {
  'apartment/sale': 32,
  'apartment/rent': 25,
  'officetel/sale': 18,
  'officetel/rent': 18,
  'rowhouse/sale': 20,
  'rowhouse/rent': 18,
  'detached/sale': 17,
  'detached/rent': 15,
  'land/sale': 16,
} as const;

describe('데이터셋 명세', () => {
  test('MVP 대상 9종이 모두 정의되어 있다', () => {
    expect(datasetKeys()).toHaveLength(9);
  });

  test('필드 수가 Swagger 실측값과 일치한다', () => {
    for (const [key, count] of Object.entries(EXPECTED_FIELD_COUNT)) {
      const spec = DATASETS[key as keyof typeof EXPECTED_FIELD_COUNT];
      expect(spec.fields, `${key}의 필드 수`).toHaveLength(count);
    }
  });

  test('한 데이터셋 안에 중복 필드가 없다', () => {
    for (const key of datasetKeys()) {
      const fields = DATASETS[key].fields;
      expect(new Set(fields).size, `${key}에 중복 필드`).toBe(fields.length);
    }
  });

  test('정규화 대응에 쓰인 원천 항목은 모두 필드 목록에 존재한다', () => {
    // 오타로 매핑이 조용히 깨지는 것을 막는다.
    for (const key of datasetKeys()) {
      const spec = DATASETS[key];
      for (const [target, source] of Object.entries(spec.map)) {
        expect(spec.fields, `${key}.${target} → ${source}`).toContain(source);
      }
    }
  });

  test('오퍼레이션명은 get + 서비스명 규칙을 따른다', () => {
    expect(operationOf(DATASETS['land/sale'])).toBe('getRTMSDataSvcLandTrade');
    expect(operationOf(DATASETS['apartment/sale'])).toBe('getRTMSDataSvcAptTradeDev');
  });

  test('포털 데이터셋 번호와 서비스명은 서로 겹치지 않는다', () => {
    const ids = datasetKeys().map((k) => DATASETS[k].portalId);
    const services = datasetKeys().map((k) => DATASETS[k].service);
    expect(new Set(ids).size).toBe(ids.length);
    expect(new Set(services).size).toBe(services.length);
  });
});

describe('거래 유형별 불변식', () => {
  const saleKeys = datasetKeys().filter((k) => k.endsWith('/sale'));
  const rentKeys = datasetKeys().filter((k) => k.endsWith('/rent'));

  test('매매는 거래금액을, 전월세는 보증금과 월세를 매핑한다', () => {
    for (const key of saleKeys) {
      expect(DATASETS[key].map.amount, `${key}`).toBeDefined();
      expect(DATASETS[key].map.deposit, `${key}`).toBeUndefined();
    }
    for (const key of rentKeys) {
      expect(DATASETS[key].map.deposit, `${key}`).toBeDefined();
      expect(DATASETS[key].map.monthlyRent, `${key}`).toBeDefined();
      expect(DATASETS[key].map.amount, `${key}`).toBeUndefined();
    }
  });

  test('해제 정보 제공 여부가 실제 필드 유무와 일치한다', () => {
    // 전월세 4종은 해제 항목을 제공하지 않으므로 해제 반영 로직을 태우면 안 된다.
    for (const key of datasetKeys()) {
      const spec = DATASETS[key];
      const hasCancelFields = spec.fields.includes('cdealType') && spec.fields.includes('cdealDay');
      expect(hasCancelFields, `${key}`).toBe(spec.cancellable);
    }
    expect(saleKeys.every((k) => DATASETS[k].cancellable)).toBe(true);
    expect(rentKeys.some((k) => DATASETS[k].cancellable)).toBe(false);
  });

  test('모든 데이터셋이 계약일 3분할과 지역코드를 제공한다', () => {
    for (const key of datasetKeys()) {
      expect(DATASETS[key].fields).toEqual(
        expect.arrayContaining(['sggCd', 'umdNm', 'dealYear', 'dealMonth', 'dealDay']),
      );
    }
  });
});

describe('좌표 확보 가능성', () => {
  test('지번을 매핑한 데이터셋만 지번 단위 정밀도를 주장한다', () => {
    for (const key of datasetKeys()) {
      const spec = DATASETS[key];
      if (spec.geocode === 'umd') {
        expect(spec.map.jibun, `${key}는 지번이 없어야 한다`).toBeUndefined();
      } else {
        expect(spec.map.jibun, `${key}는 지번이 있어야 한다`).toBeDefined();
      }
    }
  });

  test('단독다가구 전월세는 법정동 중심점 외에 위치를 특정할 수 없다', () => {
    // houseType("다가구")은 주택 종류일 뿐 건물 식별자가 아니다.
    const spec = DATASETS['detached/rent'];
    expect(spec.geocode).toBe('umd');
    expect(spec.fields).not.toContain('jibun');
    expect(spec.map.jibun).toBeUndefined();
  });

  test('지번이 마스킹되는 유형은 partial로 표시한다', () => {
    // 실응답 지번이 "2**", "4**" 형태다(test/fixtures 확인).
    expect(DATASETS['land/sale'].geocode).toBe('partial');
    expect(DATASETS['detached/sale'].geocode).toBe('partial');
  });

  test('exact 등급은 지오코딩 없이 주소 키를 조합할 수 있어야 한다', () => {
    // 매매는 법정동 지번 키(umdCd+본번+부번), 전월세는 도로명 키(도로명코드+건물번호).
    expect(DATASETS['apartment/sale'].fields).toEqual(
      expect.arrayContaining(['umdCd', 'bonbun', 'bubun', 'roadNmCd']),
    );
    expect(DATASETS['apartment/rent'].fields).toEqual(
      expect.arrayContaining(['roadnmsggcd', 'roadnmcd', 'roadnmbonbun', 'roadnmbubun']),
    );

    const exact = datasetKeys().filter((k) => DATASETS[k].geocode === 'exact');
    expect(exact).toEqual(['apartment/sale', 'apartment/rent']);
  });

  test('아파트 전월세만 도로명 필드가 소문자다', () => {
    // 원천의 표기 불일치. 파서가 camelCase를 가정하면 조용히 전부 누락된다.
    expect(DATASETS['apartment/rent'].fields).toContain('roadnmcd');
    expect(DATASETS['apartment/rent'].fields).not.toContain('roadNmCd');
    expect(DATASETS['apartment/sale'].fields).toContain('roadNmCd');
    expect(DATASETS['apartment/sale'].fields).not.toContain('roadnmcd');
  });
});
