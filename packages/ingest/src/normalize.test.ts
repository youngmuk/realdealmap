import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import { DATASETS, datasetKeys } from './datasets.js';
import { parseResponse, type RawItem } from './parse.js';
import { NormalizeError, normalizeAll, normalizeItem, parseCancelDate } from './normalize.js';

const FIXTURE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../test/fixtures');

const itemsOf = (key: string): readonly RawItem[] => {
  const name = key.replace('/', '-');
  const parsed = parseResponse(key as never, readFileSync(resolve(FIXTURE_DIR, name + '.xml'), 'utf8'));
  if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
  return parsed.items;
};

/** 명세의 모든 필드를 빈 값으로 채운 item. 개별 값만 바꿔 경계를 시험한다. */
const baseItem = (key: keyof typeof DATASETS, overrides: Record<string, string> = {}): RawItem => {
  const defaults: Record<string, string> = {};
  for (const field of DATASETS[key].fields) defaults[field] = '';
  return {
    ...defaults,
    sggCd: '11110',
    umdNm: '교북동',
    dealYear: '2026',
    dealMonth: '8',
    dealDay: '14',
    ...overrides,
  };
};

describe('골든 픽스처 정규화', () => {
  test.each(datasetKeys())('%s 전 건이 실패 없이 정규화된다', (key) => {
    const items = itemsOf(key);
    const report = normalizeAll(key, items);
    expect(report.failures, JSON.stringify(report.failures.slice(0, 2))).toEqual([]);
    expect(report.transactions).toHaveLength(items.length);
  });

  test('매매는 금액을, 전월세는 보증금·월세를 갖는다', () => {
    for (const key of datasetKeys()) {
      const [tx] = normalizeAll(key, itemsOf(key)).transactions;
      expect(tx, key).toBeDefined();
      if (!tx) continue;
      if (key.endsWith('/sale')) {
        expect(typeof tx.amount, key).toBe('number');
        expect(tx.deposit, key).toBeNull();
      } else {
        expect(typeof tx.deposit, key).toBe('number');
        expect(typeof tx.monthlyRent, key).toBe('number');
        expect(tx.amount, key).toBeNull();
      }
    }
  });

  test('계약일이 YYYY-MM-DD로 0채움된다', () => {
    for (const key of datasetKeys()) {
      for (const tx of normalizeAll(key, itemsOf(key)).transactions) {
        expect(tx.contractedOn, key).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      }
    }
  });

  test('전월세 4종은 해제 상태가 될 수 없다', () => {
    for (const key of datasetKeys().filter((k) => k.endsWith('/rent'))) {
      const all = normalizeAll(key, itemsOf(key)).transactions;
      expect(all.every((t) => !t.cancelled && t.cancelledOn === null), key).toBe(true);
    }
  });

  test('원문이 통째로 보존된다 (FR-3)', () => {
    const items = itemsOf('land/sale');
    const [tx] = normalizeAll('land/sale', items).transactions;
    expect(tx?.raw).toEqual(items[0]);
    // 유형 고유 항목이 상세화면에 낼 수 있게 남아 있다.
    expect(tx?.raw['jimok']).toBeDefined();
    expect(tx?.raw['landUse']).toBeDefined();
  });
});

describe('레코드별 좌표 정밀도', () => {
  test('마스킹된 지번은 partial로 내려간다', () => {
    const masked = normalizeAll('land/sale', itemsOf('land/sale')).transactions
      .filter((t) => t.jibunMasked);
    expect(masked.length).toBeGreaterThan(0);
    expect(masked.every((t) => t.precision === 'partial')).toBe(true);
  });

  test('지번이 온전하면 유형 기본 등급을 유지한다', () => {
    const all = normalizeAll('apartment/sale', itemsOf('apartment/sale')).transactions;
    expect(all.every((t) => !t.jibunMasked && t.precision === 'exact')).toBe(true);
  });

  test('지번이 없는 유형은 umd다', () => {
    const all = normalizeAll('detached/rent', itemsOf('detached/rent')).transactions;
    expect(all.every((t) => t.jibun === null && t.precision === 'umd')).toBe(true);
  });

  test('지번이 빈 값이면 유형이 jibun이어도 umd로 내려간다', () => {
    const tx = normalizeItem('officetel/sale', baseItem('officetel/sale', { jibun: ' ' }));
    expect(tx.jibun).toBeNull();
    expect(tx.precision).toBe('umd');
  });
});

describe('값 경계', () => {
  test('쉼표가 섞인 금액을 만원 단위 정수로 만든다', () => {
    const one = normalizeItem('land/sale', baseItem('land/sale', { dealAmount: '1,627' }));
    const two = normalizeItem('land/sale', baseItem('land/sale', { dealAmount: '260,000' }));
    expect([one.amount, two.amount]).toEqual([1627, 260000]);
  });

  test('월세 0은 결측이 아니라 전세를 뜻한다', () => {
    const tx = normalizeItem(
      'detached/rent',
      baseItem('detached/rent', { deposit: '30,000', monthlyRent: '0' }),
    );
    expect(tx.monthlyRent).toBe(0);
    expect(tx.deposit).toBe(30000);
  });

  test('빈 값과 공백은 null이 된다', () => {
    const tx = normalizeItem(
      'apartment/sale',
      baseItem('apartment/sale', { dealAmount: '100', excluUseAr: ' ', floor: '', buildYear: ' ' }),
    );
    expect([tx.areaSqm, tx.floor, tx.builtYear]).toEqual([null, null, null]);
  });

  test('지하층은 음수로 보존된다', () => {
    expect(normalizeItem('rowhouse/sale', baseItem('rowhouse/sale', { floor: '-1' })).floor).toBe(-1);
  });

  test('소수 면적을 보존한다', () => {
    const tx = normalizeItem('apartment/sale', baseItem('apartment/sale', { excluUseAr: '59.9426' }));
    expect(tx.areaSqm).toBe(59.9426);
  });

  test.each([
    ['금액에 문자', { dealAmount: '12x' }],
    ['금액이 음수', { dealAmount: '-100' }],
    ['면적이 음수', { excluUseAr: '-5' }],
    ['층이 실수', { floor: '1.5' }],
    ['시군구코드 4자리', { sggCd: '1111' }],
    ['달력에 없는 날', { dealMonth: '2', dealDay: '30' }],
    ['계약일 누락', { dealDay: '' }],
  ])('%s은 NormalizeError다', (_label, overrides) => {
    expect(() => normalizeItem('apartment/sale', baseItem('apartment/sale', overrides)))
      .toThrow(NormalizeError);
  });

  test('오류에 필드명과 원문이 담긴다', () => {
    try {
      normalizeItem('apartment/sale', baseItem('apartment/sale', { dealAmount: '12x' }));
      expect.unreachable('던져야 한다');
    } catch (error) {
      expect(error).toBeInstanceOf(NormalizeError);
      expect((error as NormalizeError).field).toBe('dealAmount');
      expect((error as NormalizeError).value).toBe('12x');
    }
  });
});

describe('해제 처리', () => {
  test('cdealType이 있으면 해제로 표시한다', () => {
    const tx = normalizeItem(
      'apartment/sale',
      baseItem('apartment/sale', { dealAmount: '100', cdealType: 'O', cdealDay: '26.08.20' }),
    );
    expect(tx.cancelled).toBe(true);
    expect(tx.cancelledOn).toBe('2026-08-20');
  });

  test('해제건도 삭제하지 않고 상태로 보존한다', () => {
    const tx = normalizeItem(
      'apartment/sale',
      baseItem('apartment/sale', { dealAmount: '100', cdealType: 'O' }),
    );
    expect(tx.amount).toBe(100);
    expect(tx.contractedOn).toBe('2026-08-14');
  });

  test.each([
    ['YY.MM.DD', '26.08.20', '2026-08-20'],
    ['YYYYMMDD', '20260820', '2026-08-20'],
    ['YYYY-MM-DD', '2026-08-20', '2026-08-20'],
    ['빈값', ' ', null],
    ['해석 불가', 'ㅁㄴㅇ', null],
    ['자릿수 이상', '123', null],
    ['날짜가 아님', '26.99.99', null],
  ])('해제일 %s → %s', (_label, input, expected) => {
    expect(parseCancelDate(input)).toBe(expected);
  });

  test('해제일을 해석하지 못해도 해제 상태는 유지하고 원문을 남긴다', () => {
    // 날짜를 지어내지 않는다. 형식이 확인되면 raw로 재처리한다.
    const tx = normalizeItem(
      'apartment/sale',
      baseItem('apartment/sale', { dealAmount: '100', cdealType: 'O', cdealDay: '알수없음' }),
    );
    expect(tx.cancelled).toBe(true);
    expect(tx.cancelledOn).toBeNull();
    expect(tx.raw['cdealDay']).toBe('알수없음');
  });
});

describe('일괄 정규화', () => {
  test('깨진 건만 실패로 모으고 나머지는 살린다', () => {
    const good = baseItem('land/sale', { dealAmount: '100' });
    const bad = baseItem('land/sale', { dealAmount: 'x' });
    const report = normalizeAll('land/sale', [good, bad, good]);

    expect(report.transactions).toHaveLength(2);
    expect(report.failures).toHaveLength(1);
    expect(report.failures[0]?.index).toBe(1);
    expect(report.failures[0]?.item).toBe(bad);
    expect(report.failures[0]?.message).toContain('dealAmount');
  });

  test('빈 입력은 빈 결과다', () => {
    expect(normalizeAll('land/sale', [])).toEqual({ transactions: [], failures: [] });
  });
});
