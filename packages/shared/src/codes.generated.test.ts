import { describe, expect, test } from 'vitest';

import { isQueryableSggCd, QUERYABLE_SGG_CODES } from './codes.generated.js';
import { queryableRegions } from './regions.js';

/**
 * 생성된 코드 집합이 카탈로그와 같은지 잠근다.
 *
 * 같은 사실을 두 곳에 두면 언젠가 어긋난다. 여기서 어긋나면 Worker가
 * 실재하는 시군구를 거부하거나(갱신 불가) 폐지된 코드를 통과시킨다 —
 * 후자는 원천이 조용히 0건을 주므로(R-14) 증상 없이 빈 지역이 된다.
 *
 * 어긋나면 `npm run regions:build`를 다시 돌리면 된다.
 */
describe('생성된 코드 집합', () => {
  test('카탈로그의 조회 대상과 정확히 같다', () => {
    const fromCatalog = queryableRegions().map((r) => r.sggCd);
    expect([...QUERYABLE_SGG_CODES].sort()).toEqual([...fromCatalog].sort());
  });

  test('개수가 맞다', () => {
    expect(QUERYABLE_SGG_CODES).toHaveLength(queryableRegions().length);
  });

  test('전부 5자리 숫자다', () => {
    expect(QUERYABLE_SGG_CODES.every((c) => /^\d{5}$/.test(c))).toBe(true);
  });

  test('중복이 없다', () => {
    expect(new Set(QUERYABLE_SGG_CODES).size).toBe(QUERYABLE_SGG_CODES.length);
  });

  test('실재하는 코드를 통과시킨다', () => {
    expect(isQueryableSggCd('11680')).toBe(true); // 서울특별시 강남구
    expect(isQueryableSggCd('11110')).toBe(true); // 서울특별시 종로구
  });

  test('조회 대상이 아닌 코드를 거부한다', () => {
    expect(isQueryableSggCd('41110')).toBe(false); // 수원시 — 하위 구로 나뉜 상위 시
    expect(isQueryableSggCd('99999')).toBe(false);
    expect(isQueryableSggCd('1168')).toBe(false);
    expect(isQueryableSggCd('')).toBe(false);
  });
});
