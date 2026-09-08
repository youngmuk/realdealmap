import { describe, expect, test } from 'vitest';

import { buildChunk, type Chunk } from './chunk.js';
import { emptyDictionary, type GeoDictionary, type GeoEntry } from './geo.js';
import type { Transaction } from './normalize.js';
import {
  emptyIndex,
  INDEX_VERSION,
  parseIndex,
  sameSummary,
  summarize,
  withRegion,
  type RegionSummary,
} from './region-index.js';

const REGION = { name: '서울특별시 강남구', sidoName: '서울특별시', sggName: '강남구' };

const tx = (jibun: string): Transaction => ({
  datasetKey: 'apartment/sale',
  propertyType: 'apartment',
  tradeType: 'sale',
  sggCd: '11680',
  umdNm: '논현동',
  jibun,
  jibunMasked: jibun.includes('*'),
  name: '테스트',
  contractedOn: '2026-08-14',
  areaSqm: 84.97,
  floor: 12,
  builtYear: 2004,
  amount: 320000,
  deposit: null,
  monthlyRent: null,
  cancelled: false,
  cancelledOn: null,
  precision: 'exact',
  raw: { jibun },
});

const entry = (lat: number, lng: number): GeoEntry => ({
  lat,
  lng,
  source: 'address',
  checkedOn: '2026-09-07',
});

const dict = (entries: Record<string, GeoEntry>): GeoDictionary => ({
  ...emptyDictionary('11680'),
  entries,
});

const chunkOf = (points: Record<string, [number, number] | null>): Chunk => {
  const entries: Record<string, GeoEntry> = {};
  for (const [jibun, point] of Object.entries(points)) {
    if (point) entries[`논현동|${jibun}`] = entry(point[0], point[1]);
  }
  return buildChunk(
    '11680',
    'apartment/sale',
    '202608',
    Object.keys(points).map(tx),
    dict(entries),
  );
};

const summary = (over: Partial<RegionSummary> = {}): RegionSummary => ({
  sggCd: '11680',
  name: '서울특별시 강남구',
  sidoName: '서울특별시',
  sggName: '강남구',
  records: 10,
  sampled: 10,
  located: 10,
  refreshedAt: '2026-09-07T00:00:00.000Z',
  ...over,
});

describe('지역 요약', () => {
  test('좌표의 경계상자를 잡는다', () => {
    const chunk = chunkOf({ '1': [37.5, 127.0], '2': [37.6, 127.1] });
    const result = summarize('11680', REGION, [chunk], '2026-09-07T00:00:00.000Z');

    expect(result.bbox).toEqual({ south: 37.5, north: 37.6, west: 127.0, east: 127.1 });
  });

  // 평균은 외곽에 한 건 있는 토지 거래에 끌려가 지도가 엉뚱한 곳에서 열린다.
  test('중심은 평균이 아니라 중앙값이다', () => {
    const chunk = chunkOf({
      '1': [37.50, 127.0],
      '2': [37.51, 127.0],
      '3': [37.52, 127.0],
      '4': [38.90, 127.0],
    });
    const result = summarize('11680', REGION, [chunk], '2026-09-07T00:00:00.000Z');

    expect(result.center?.lat).toBeCloseTo(37.515, 3);
  });

  test('좌표 없는 건은 경계상자에 넣지 않지만 건수에는 센다', () => {
    const chunk = chunkOf({ '1': [37.5, 127.0], '2': null });
    const result = summarize('11680', REGION, [chunk], '2026-09-07T00:00:00.000Z');

    expect(result.records).toBe(2);
    expect(result.located).toBe(1);
    expect(result.bbox).toEqual({ south: 37.5, north: 37.5, west: 127.0, east: 127.0 });
  });

  // 좌표가 하나도 없는데 경계상자를 0,0으로 두면 앱이 기니만 앞바다를 연다.
  test('좌표가 하나도 없으면 경계상자를 만들지 않는다', () => {
    const chunk = chunkOf({ '1': null, '2': null });
    const result = summarize('11680', REGION, [chunk], '2026-09-07T00:00:00.000Z');

    expect(result.bbox).toBeUndefined();
    expect(result.center).toBeUndefined();
    expect(result.records).toBe(2);
  });

  // 매 시간 갱신은 최근 3개월만 다시 만든다. 그 건수를 색인에 넣으면 12개월을
  // 적재해 둔 지역이 한 시간 뒤에 1/4로 줄어 보인다 — 지역 선택 화면이 그 값을
  // 그대로 쓰므로, 사용자에게는 적재가 통째로 되돌려진 것으로 보인다.
  describe('부분 갱신', () => {
    test('전체 건수는 매니페스트에서 온다', () => {
      const chunk = chunkOf({ '1': [37.5, 127.0], '2': [37.6, 127.1] });

      const result = summarize('11680', REGION, [chunk], '2026-09-07T00:00:00.000Z', 44174);

      expect(result.records).toBe(44174);
    });

    // 분자는 이번 회차, 분모가 전체면 좌표 채움률이 실제보다 낮게 나온다.
    // 지표가 낮게 나오면 없는 문제를 쫓게 된다.
    test('좌표 채움률의 분모는 이번 회차 건수다', () => {
      const chunk = chunkOf({ '1': [37.5, 127.0], '2': null });

      const result = summarize('11680', REGION, [chunk], '2026-09-07T00:00:00.000Z', 44174);

      expect(result.sampled).toBe(2);
      expect(result.located).toBe(1);
    });

    test('전체 건수를 안 주면 이번 회차 건수를 쓴다', () => {
      const chunk = chunkOf({ '1': [37.5, 127.0], '2': null });

      const result = summarize('11680', REGION, [chunk], '2026-09-07T00:00:00.000Z');

      expect(result.records).toBe(2);
      expect(result.sampled).toBe(2);
    });
  });

  test('거래가 없어도 지역은 남는다', () => {
    const result = summarize('11680', REGION, [], '2026-09-07T00:00:00.000Z');
    expect(result.records).toBe(0);
    expect(result.name).toBe('서울특별시 강남구');
  });

  test('이름이 없으면 시도명과 시군구명을 붙인다', () => {
    const result = summarize(
      '11680',
      { sidoName: '서울특별시', sggName: '강남구' },
      [],
      '2026-09-07T00:00:00.000Z',
    );
    expect(result.name).toBe('서울특별시 강남구');
  });
});

describe('색인 읽기', () => {
  test('없으면 빈 색인이다', () => {
    expect(parseIndex(null).regions).toEqual([]);
  });

  test.each([
    ['깨진 JSON', '{'],
    ['regions가 없음', `{"version":${INDEX_VERSION}}`],
    ['판이 다름', '{"version":0,"regions":[]}'],
  ])('%s이면 빈 색인이다', (_label, text) => {
    expect(parseIndex(text).regions).toEqual([]);
  });
});

describe('색인 갱신', () => {
  test('같은 지역은 갈아 끼운다', () => {
    const before = withRegion(emptyIndex(), summary({ records: 1 }), new Date());
    const after = withRegion(before, summary({ records: 2 }), new Date());

    expect(after.regions).toHaveLength(1);
    expect(after.regions[0]?.records).toBe(2);
  });

  // 순서가 흔들리면 내용이 같아도 바이트가 달라져 매번 다시 올리게 된다.
  test('코드 순으로 정렬한다', () => {
    let index = withRegion(emptyIndex(), summary({ sggCd: '11710' }), new Date());
    index = withRegion(index, summary({ sggCd: '11680' }), new Date());

    expect(index.regions.map((r) => r.sggCd)).toEqual(['11680', '11710']);
  });

  test('원본을 건드리지 않는다', () => {
    const before = withRegion(emptyIndex(), summary({ sggCd: '11680' }), new Date());
    withRegion(before, summary({ sggCd: '11710' }), new Date());

    expect(before.regions).toHaveLength(1);
  });
});

describe('변경 판정', () => {
  test('내용이 같으면 올리지 않는다', () => {
    expect(sameSummary(summary(), summary())).toBe(true);
  });

  test('없던 지역은 다르다', () => {
    expect(sameSummary(undefined, summary())).toBe(false);
  });

  test.each([
    ['건수', { records: 11 }],
    ['좌표 건수', { located: 9 }],
    ['기준 시각', { refreshedAt: '2026-09-08T00:00:00.000Z' }],
    ['경계상자', { bbox: { south: 1, north: 2, west: 3, east: 4 } }],
  ])('%s이 바뀌면 다르다', (_label, over) => {
    expect(sameSummary(summary(), summary(over))).toBe(false);
  });
});
