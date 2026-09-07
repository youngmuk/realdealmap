import type { DatasetKey } from '@realdealmap/shared';
import { describe, expect, test } from 'vitest';

import type { GeocodePrecision } from './datasets.js';

import {
  coverageByDataset,
  coverageMarkdown,
  effectivePrecision,
  emptyDictionary,
  evaluateG3,
  findMissing,
  geoKey,
  geoQuery,
  GEO_VERSION,
  isStale,
  locate,
  NOMATCH_RETRY_DAYS,
  parseDictionary,
  withEntries,
  type GeoDictionary,
  type GeoEntry,
} from './geo.js';

const entry = (over: Partial<GeoEntry> = {}): GeoEntry => ({
  lat: 37.5,
  lng: 127.0,
  source: 'kakao',
  checkedOn: '2026-09-01',
  ...over,
});

const dict = (entries: Record<string, GeoEntry>): GeoDictionary => ({
  version: GEO_VERSION,
  sggCd: '11680',
  generatedAt: '2026-09-01T00:00:00.000Z',
  entries,
});

const tx = (
  umdNm: string,
  jibun: string | null,
  precision: GeocodePrecision = 'jibun',
): { umdNm: string; jibun: string | null; precision: GeocodePrecision } => ({
  umdNm,
  jibun,
  precision,
});

describe('사전 열쇠', () => {
  test('지번이 있으면 지번까지 쓴다', () => {
    expect(geoKey('논현동', '123')).toBe('논현동|123');
  });

  // 카카오는 `*`를 조용히 버리고 `논현동 3*`을 `논현동 3`으로 매칭한 뒤
  // "지번 정확 일치"로 답한다. 실측 226~582m 오차 — 미매칭보다 나쁘다.
  test.each(['3*', '1**', '12*', '**'])('마스킹된 지번 %s은 버린다', (jibun) => {
    expect(geoKey('논현동', jibun)).toBe('논현동|');
  });

  test('지번이 없으면 법정동까지만 쓴다', () => {
    expect(geoKey('논현동', null)).toBe('논현동|');
  });

  test('조회 주소도 같은 규칙을 따른다', () => {
    expect(geoQuery('서울특별시 강남구', '논현동', '123')).toBe('서울특별시 강남구 논현동 123');
    expect(geoQuery('서울특별시 강남구', '논현동', '3*')).toBe('서울특별시 강남구 논현동');
  });

  // 열쇠와 조회 주소가 어긋나면 사전에 없는 것을 계속 물어보거나
  // 물어본 것과 다른 자리에 저장하게 된다.
  test('마스킹 여부 판정이 열쇠와 조회 주소에서 같다', () => {
    for (const jibun of ['123', '3*', null, '']) {
      const keyed = geoKey('논현동', jibun) === '논현동|';
      const queried = geoQuery('구', '논현동', jibun) === '구 논현동';
      expect(keyed).toBe(queried);
    }
  });
});

describe('사전 읽기', () => {
  test('없으면 빈 사전으로 시작한다', () => {
    expect(parseDictionary('11680', null).entries).toEqual({});
  });

  test.each([
    ['깨진 JSON', '{'],
    ['entries가 없음', '{"version":1}'],
    ['entries가 null', '{"version":1,"entries":null}'],
  ])('%s이면 빈 사전으로 시작한다', (_label, text) => {
    expect(parseDictionary('11680', text).entries).toEqual({});
  });

  // 옛 판을 부분적으로 살려 쓰면 어떤 항목이 옛 규칙으로 만들어졌는지 알 수 없다.
  // 다시 변환하는 비용은 쿼터의 몇 %지만 틀린 좌표는 지도에 그대로 찍힌다.
  test('판이 다르면 통째로 버린다', () => {
    const old = JSON.stringify({ version: 0, entries: { '논현동|1': entry() } });
    expect(parseDictionary('11680', old).entries).toEqual({});
  });

  test('판이 같으면 항목을 살린다', () => {
    const text = JSON.stringify({ version: GEO_VERSION, entries: { '논현동|1': entry() } });
    expect(Object.keys(parseDictionary('11680', text).entries)).toEqual(['논현동|1']);
  });
});

describe('실패 재시도 시점', () => {
  test('성공한 항목은 다시 묻지 않는다', () => {
    expect(isStale(entry({ source: 'kakao', checkedOn: '2020-01-01' }), '2026-09-07')).toBe(false);
  });

  test(`실패는 ${NOMATCH_RETRY_DAYS}일이 지나야 다시 묻는다`, () => {
    const failed = entry({ source: 'nomatch', checkedOn: '2026-09-01' });
    expect(isStale(failed, '2026-09-20')).toBe(false);
    expect(isStale(failed, '2026-10-01')).toBe(true);
  });
});

describe('처리 대상 고르기', () => {
  test('사전에 있는 주소는 빠진다', () => {
    const missing = findMissing(
      [tx('논현동', '1'), tx('삼성동', '2')],
      dict({ '논현동|1': entry() }),
      '2026-09-07',
    );
    expect(missing.map((m) => m.key)).toEqual(['삼성동|2']);
  });

  // 쿼터가 모자라 중간에 끊겨도 화면에 보이는 마커가 가장 많이 늘어나야 한다.
  test('거래가 많은 주소가 앞에 온다', () => {
    const missing = findMissing(
      [tx('가동', '1'), tx('나동', '2'), tx('나동', '2'), tx('나동', '2')],
      dict({}),
      '2026-09-07',
    );
    expect(missing[0]?.key).toBe('나동|2');
    expect(missing[0]?.deals).toBe(3);
  });

  test('거래 수가 같으면 열쇠 순으로 고정된다', () => {
    const a = findMissing([tx('나동', '1'), tx('가동', '1')], dict({}), '2026-09-07');
    const b = findMissing([tx('가동', '1'), tx('나동', '1')], dict({}), '2026-09-07');
    expect(a.map((m) => m.key)).toEqual(b.map((m) => m.key));
  });

  // 열쇠에서 버린 지번을 조회 주소에 남기면 카카오가 오탐으로 답한다.
  test('마스킹된 지번은 조회 대상에서도 지운다', () => {
    const missing = findMissing([tx('논현동', '3*')], dict({}), '2026-09-07');
    expect(missing[0]?.jibun).toBeNull();
  });

  test('오래된 실패는 다시 대상이 된다', () => {
    const stale = { '논현동|1': entry({ source: 'nomatch', checkedOn: '2026-01-01' }) };
    expect(findMissing([tx('논현동', '1')], dict(stale), '2026-09-07')).toHaveLength(1);
  });
});

describe('좌표 붙이기', () => {
  test('사전에 있으면 좌표와 등급을 준다', () => {
    const located = locate(tx('논현동', '1', 'exact'), dict({ '논현동|1': entry() }));
    expect(located).toEqual({ lat: 37.5, lng: 127.0, precision: 'exact' });
  });

  // 좌표가 없을 때 등급을 unknown으로 덮으면 "단독주택이라 지번이 가려진 것"과
  // "아파트인데 지오코딩에 실패한 것"이 같은 값이 되어 앱이 구분할 수 없다.
  test('좌표가 없어도 원천 등급은 유지한다', () => {
    expect(locate(tx('논현동', '1', 'exact'), dict({}))).toEqual({
      lat: null,
      lng: null,
      precision: 'exact',
    });
  });

  test('미확인은 좌표가 null인 것으로 표현한다', () => {
    expect(locate(tx('논현동', '1', 'partial'), dict({})).lat).toBeNull();
    expect(locate(tx('논현동', '1', 'partial'), dict({ '논현동|1': entry() })).lat).not.toBeNull();
  });

  test('영구 실패는 좌표 없음으로 다룬다', () => {
    const failed = dict({ '논현동|1': entry({ source: 'nomatch', lat: 0, lng: 0 }) });
    expect(locate(tx('논현동', '1', 'exact'), failed).lat).toBeNull();
  });
});

describe('사전 갱신', () => {
  test('원본을 건드리지 않는다', () => {
    const before = dict({ a: entry() });
    const after = withEntries(before, { b: entry() }, new Date('2026-09-07'));
    expect(Object.keys(before.entries)).toEqual(['a']);
    expect(Object.keys(after.entries).sort()).toEqual(['a', 'b']);
  });

  test('같은 열쇠는 새 값이 이긴다', () => {
    const before = dict({ a: entry({ lat: 1 }) });
    const after = withEntries(before, { a: entry({ lat: 2 }) }, new Date('2026-09-07'));
    expect(after.entries.a?.lat).toBe(2);
  });
});

describe('커버리지와 G3', () => {
  const rows = (located: number, total: number) => [
    { datasetKey: 'apartment/sale', total, located },
  ];

  test('유형별로 거래 기준으로 센다', () => {
    const transactions = [
      { datasetKey: 'apartment/sale' as DatasetKey, ...tx('논현동', '1') },
      { datasetKey: 'apartment/sale' as DatasetKey, ...tx('삼성동', '2') },
      { datasetKey: 'land/sale' as DatasetKey, ...tx('논현동', '1') },
    ];
    const result = coverageByDataset(transactions, dict({ '논현동|1': entry() }));
    expect(result).toEqual([
      { datasetKey: 'apartment/sale', total: 2, located: 1 },
      { datasetKey: 'land/sale', total: 1, located: 1 },
    ]);
  });

  test('임계 95%를 넘으면 통과한다', () => {
    expect(evaluateG3(rows(96, 100))?.passed).toBe(true);
    expect(evaluateG3(rows(94, 100))?.passed).toBe(false);
  });

  // 0건에서 비율을 1로 두면 데이터 없는 지역이 전부 통과로 보인다.
  test('대상이 하나도 없으면 통과가 아니라 미판정이다', () => {
    expect(evaluateG3([{ datasetKey: 'land/sale', total: 50, located: 0 }])).toBeNull();
    expect(evaluateG3([])).toBeNull();
  });

  // 단독·토지는 원천이 지번을 가려 애초에 달성할 수 없다. 섞으면 게이트가 늘 실패한다.
  test('단독·토지는 게이트 계산에서 뺀다', () => {
    const result = evaluateG3([
      { datasetKey: 'apartment/sale', total: 100, located: 100 },
      { datasetKey: 'land/sale', total: 100, located: 0 },
    ]);
    expect(result?.total).toBe(100);
    expect(result?.passed).toBe(true);
  });
});

describe('빈 사전', () => {
  test('좌표를 하나도 붙이지 않는다', () => {
    expect(locate(tx('논현동', '1'), emptyDictionary('11680')).lat).toBeNull();
  });
});

describe('커버리지 리포트', () => {
  const rows = [
    { datasetKey: 'apartment/sale', total: 100, located: 98 },
    { datasetKey: 'land/sale', total: 40, located: 0 },
  ];

  test('G3 대상에만 별표를 단다', () => {
    const md = coverageMarkdown('11680', rows, evaluateG3(rows));
    expect(md).toContain('| apartment/sale * |');
    expect(md).toContain('| land/sale |');
  });

  test('게이트는 대상만으로 판정한다', () => {
    const md = coverageMarkdown('11680', rows, evaluateG3(rows));
    expect(md).toContain('통과');
    expect(md).toContain('98/100');
  });

  // 데이터 없는 지역에 초록 체크가 뜨면 게이트처럼 보이기만 하는 게이트가 된다.
  test('미판정을 통과로 쓰지 않는다', () => {
    const md = coverageMarkdown('11680', [], null);
    expect(md).toContain('미판정');
    expect(md).toContain('통과가 아니다');
    expect(md).not.toContain('✅');
  });

  test('0건인 줄에서 나눗셈하지 않는다', () => {
    expect(coverageMarkdown('11680', [{ datasetKey: 'land/sale', total: 0, located: 0 }], null))
      .toContain('| — |');
  });
});

describe('행 단위 정밀도', () => {
  // 유형 등급을 그대로 쓰면 마스킹된 아파트 행이 법정동 중심점에 exact 핀을 찍는다.
  // T1.5 실측 오차가 226~582 m다 — 등급이 곧 거짓말이 된다.
  test('지번이 가려지면 유형이 exact여도 partial로 내린다', () => {
    expect(effectivePrecision({ jibun: '3*', precision: 'exact' })).toBe('partial');
    expect(effectivePrecision({ jibun: '12**', precision: 'jibun' })).toBe('partial');
  });

  test('지번이 아예 없으면 umd다', () => {
    expect(effectivePrecision({ jibun: null, precision: 'exact' })).toBe('umd');
    expect(effectivePrecision({ jibun: '', precision: 'exact' })).toBe('umd');
  });

  test('멀쩡한 지번이면 유형 등급을 쓴다', () => {
    expect(effectivePrecision({ jibun: '123', precision: 'exact' })).toBe('exact');
    expect(effectivePrecision({ jibun: '123-4', precision: 'jibun' })).toBe('jibun');
  });

  // 등급을 내린 것과 열쇠를 접은 것이 어긋나면, 근사 좌표에 정확한 등급이 붙는다.
  test('등급을 내리는 조건이 열쇠를 접는 조건과 같다', () => {
    for (const jibun of ['123', '3*', null, '']) {
      const folded = geoKey('논현동', jibun) === '논현동|';
      const downgraded = effectivePrecision({ jibun, precision: 'exact' }) !== 'exact';
      expect(folded).toBe(downgraded);
    }
  });

  test('붙인 좌표에도 같은 등급이 실린다', () => {
    const located = locate(tx('논현동', '3*', 'exact'), dict({ '논현동|': entry() }));
    expect(located.precision).toBe('partial');
    expect(located.lat).toBe(37.5);
  });
});
