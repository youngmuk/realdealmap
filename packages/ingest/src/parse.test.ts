import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import { DATASETS, datasetKeys } from './datasets.js';
import { hasSchemaDrift, parseResponse, ResponseShapeError, type ParsedResponse } from './parse.js';

const FIXTURE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../test/fixtures');
const load = (name: string): string => readFileSync(resolve(FIXTURE_DIR, `${name}.xml`), 'utf8');
const fixtureOf = (key: string): string => load(key.replace('/', '-'));

/** 봉투만 바꿔 끼우는 최소 응답. 봉투 검증 테스트에서 쓴다. */
const envelope = (body: string, code = '000'): string =>
  `<response><header><resultCode>${code}</resultCode><resultMsg>OK</resultMsg></header>` +
  `<body>${body}</body></response>`;

const counts = '<numOfRows>10</numOfRows><pageNo>1</pageNo><totalCount>0</totalCount>';

const asData = (xml: string): ParsedResponse => {
  const parsed = parseResponse('land/sale', xml);
  if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
  return parsed;
};

describe('골든 픽스처 파싱', () => {
  test.each(datasetKeys())('%s 응답이 명세대로 파싱된다', (key) => {
    const parsed = parseResponse(key, fixtureOf(key));

    expect(parsed.kind).toBe('data');
    if (parsed.kind !== 'data') return;

    expect(parsed.resultCode).toBe('000');
    expect(parsed.items.length).toBeGreaterThan(0);
    // 페이지에 담긴 건수는 전체 건수를 넘을 수 없다.
    expect(parsed.items.length).toBeLessThanOrEqual(parsed.totalCount);
    expect(parsed.items.length).toBeLessThanOrEqual(parsed.numOfRows);

    // T2.4 완료 기준: 9종이 전부 파싱되고 필드 누락 0.
    expect(hasSchemaDrift(parsed), `${key} 스키마 차이`).toBe(false);
  });

  test('모든 item이 명세의 필드를 빠짐없이 가진다', () => {
    for (const key of datasetKeys()) {
      const parsed = parseResponse(key, fixtureOf(key));
      if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
      for (const item of parsed.items) {
        expect(Object.keys(item).sort(), key).toEqual([...DATASETS[key].fields].sort());
      }
    }
  });

  test('빈 값은 공백이 아니라 빈 문자열로 들어온다', () => {
    // 원천이 <preDeposit> </preDeposit>로 준다. 정규화기가 공백을 값으로 오인하면 안 된다.
    const parsed = parseResponse('detached/rent', fixtureOf('detached/rent'));
    if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
    const values = parsed.items.flatMap((i) => Object.values(i));
    expect(values.some((v) => v === '')).toBe(true);
    expect(values.every((v) => v === v.trim())).toBe(true);
  });

  test('마스킹된 지번이 원문 그대로 보존된다', () => {
    const parsed = parseResponse('land/sale', fixtureOf('land/sale'));
    if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
    expect(parsed.items.some((i) => (i['jibun'] ?? '').includes('*'))).toBe(true);
  });
});

describe('오류 봉투', () => {
  test('등록되지 않은 서비스키는 코드 30으로 읽힌다', () => {
    const parsed = parseResponse('apartment/sale', load('fault-badkey'));
    expect(parsed).toEqual({
      kind: 'fault',
      code: '30',
      errMsg: 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR',
      authMsg: '등록되지 않은 서비스키',
    });
  });

  test('서비스키 누락은 코드 20으로 읽힌다', () => {
    const parsed = parseResponse('apartment/sale', load('fault-nokey'));
    expect(parsed.kind).toBe('fault');
    if (parsed.kind !== 'fault') return;
    expect(parsed.code).toBe('20');
    expect(parsed.errMsg).toBe('SERVICE_KEY_IS_NULL');
  });

  test('cmmMsgHeader가 없으면 형태 오류다', () => {
    expect(() => parseResponse('land/sale', '<OpenAPI_ServiceResponse><x/></OpenAPI_ServiceResponse>'))
      .toThrow(ResponseShapeError);
  });
});

describe('봉투 검증', () => {
  test('0건 응답도 정상으로 읽는다', () => {
    // 잘못된 코드·미래 월이 전부 이 형태로 온다(R-14). 파서 단계에서는 오류가 아니다.
    const parsed = asData(envelope(`<items></items>${counts}`));
    expect(parsed.items).toEqual([]);
    expect(parsed.totalCount).toBe(0);
    expect(hasSchemaDrift(parsed)).toBe(false);
  });

  test('items 노드 자체가 없어도 0건으로 읽는다', () => {
    expect(asData(envelope(counts)).items).toEqual([]);
  });

  test.each([
    ['header 없음', '<response><body>x</body></response>'],
    ['body 없음', '<response><header/></response>'],
  ])('%s은 형태 오류다', (_label, xml) => {
    expect(() => parseResponse('land/sale', xml)).toThrow(ResponseShapeError);
  });

  test.each([
    ['totalCount 없음', '<items></items><numOfRows>10</numOfRows><pageNo>1</pageNo>'],
    ['숫자가 아님', `<items></items><numOfRows>10</numOfRows><pageNo>1</pageNo><totalCount>x</totalCount>`],
    ['음수', `<items></items><numOfRows>10</numOfRows><pageNo>1</pageNo><totalCount>-1</totalCount>`],
  ])('%s은 형태 오류다 — 조용히 0으로 두지 않는다', (_label, body) => {
    expect(() => parseResponse('land/sale', envelope(body))).toThrow(ResponseShapeError);
  });

  test('알 수 없는 봉투는 형태 오류다', () => {
    expect(() => parseResponse('land/sale', '<html><body>maintenance</body></html>'))
      .toThrow(ResponseShapeError);
  });
});

describe('스키마 변화 감지 (R-14)', () => {
  const item = (fields: string): string => `<items><item>${fields}</item></items>${counts.replace('>0<', '>1<')}`;
  const landFields = DATASETS['land/sale'].fields.map((f) => `<${f}>v</${f}>`).join('');

  test('명세대로면 차이가 없다', () => {
    const parsed = asData(envelope(item(landFields)));
    expect(parsed.unknownFields).toEqual([]);
    expect(parsed.missingFields).toEqual([]);
    expect(hasSchemaDrift(parsed)).toBe(false);
  });

  test('원천이 필드를 추가하면 unknownFields로 드러난다', () => {
    const parsed = asData(envelope(item(`${landFields}<newField>v</newField>`)));
    expect(parsed.unknownFields).toEqual(['newField']);
    expect(hasSchemaDrift(parsed)).toBe(true);
  });

  test('원천이 필드를 빼면 missingFields로 드러난다', () => {
    const without = landFields.replace('<jimok>v</jimok>', '');
    const parsed = asData(envelope(item(without)));
    expect(parsed.missingFields).toEqual(['jimok']);
    expect(hasSchemaDrift(parsed)).toBe(true);
  });

  test('0건일 때는 비교하지 않는다', () => {
    // item이 없으면 필드 부재가 스키마 변화인지 알 수 없다. 거짓 경보를 내지 않는다.
    const parsed = asData(envelope(`<items></items>${counts}`));
    expect(parsed.missingFields).toEqual([]);
  });

  test('여러 item에 걸쳐 필드를 합산한다', () => {
    // 값이 비면 태그를 통째로 빼는 개체가 있어도 다른 개체가 채우면 정상이다.
    const first = landFields.replace('<jimok>v</jimok>', '');
    const two = `<items><item>${first}</item><item>${landFields}</item></items>${counts.replace('>0<', '>2<')}`;
    expect(asData(envelope(two)).missingFields).toEqual([]);
  });
});
