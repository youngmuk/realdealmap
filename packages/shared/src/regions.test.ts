import { afterEach, describe, expect, test, vi } from 'vitest';

import {
  clearRegionCache,
  findRegion,
  loadLegacyCatalog,
  loadRegionCatalog,
  queryableRegions,
  toCurrentCode,
} from './regions.js';

describe('시군구 카탈로그', () => {
  test('조회 대상 수가 카탈로그의 선언값과 일치한다', () => {
    const catalog = loadRegionCatalog();
    expect(queryableRegions()).toHaveLength(catalog.queryableCount);
    expect(catalog.regions).toHaveLength(catalog.totalSggLevel);
  });

  test('모든 시군구 코드는 5자리 숫자이며 중복이 없다', () => {
    const codes = loadRegionCatalog().regions.map((r) => r.sggCd);
    for (const code of codes) {
      expect(code).toMatch(/^\d{5}$/);
    }
    expect(new Set(codes).size).toBe(codes.length);
  });

  test('조회 대상에는 하위 일반구를 가진 상위 시가 포함되지 않는다', () => {
    // 상위 시를 조회하면 하위 구와 거래가 중복 집계된다.
    const parents = queryableRegions().filter((r) => r.hasSubGu);
    expect(parents).toEqual([]);
  });

  test('일반구의 parentCd는 실재하는 상위 시를 가리킨다', () => {
    const withParent = loadRegionCatalog().regions.filter((r) => r.parentCd !== undefined);
    expect(withParent.length).toBeGreaterThan(0);

    for (const region of withParent) {
      const parent = findRegion(region.parentCd as string);
      expect(parent, `${region.name}의 상위 시를 찾지 못함`).toBeDefined();
      expect(parent?.hasSubGu).toBe(true);
      expect(region.name.startsWith(`${parent?.name} `)).toBe(true);
    }
  });

  test('시도 코드는 시군구 코드의 앞 두 자리와 일치한다', () => {
    for (const region of loadRegionCatalog().regions) {
      expect(region.sidoCd).toBe(region.sggCd.slice(0, 2));
    }
  });

  test('세종특별자치시는 하위 시군구 없이 단일 코드로 존재한다', () => {
    const sejong = findRegion('36110');
    expect(sejong?.name).toBe('세종특별자치시');
    expect(sejong?.queryable).toBe(true);
  });
});

describe('폐지 코드 매핑', () => {
  test('모든 매핑의 현행 코드가 카탈로그에 존재한다', () => {
    for (const mapping of loadLegacyCatalog().mappings) {
      expect(findRegion(mapping.currentCd), `${mapping.legacyName} → ${mapping.currentCd}`).toBeDefined();
    }
  });

  test('폐지 코드와 현행 코드가 서로 다르다', () => {
    for (const mapping of loadLegacyCatalog().mappings) {
      expect(mapping.legacyCd).not.toBe(mapping.currentCd);
    }
  });

  test('통합으로 폐지된 광주광역시 코드를 현행 코드로 옮긴다', () => {
    // 광주광역시(29)와 전라남도(46)는 전남광주통합특별시(12)로 통합되었다.
    expect(toCurrentCode('29110')).toBe('12210');
    expect(toCurrentCode('46110')).toBe('12110');
  });

  test('현행 코드는 그대로 통과시킨다', () => {
    expect(toCurrentCode('11110')).toBe('11110');
    expect(toCurrentCode('36110')).toBe('36110');
  });

  test('알 수 없는 코드는 입력을 그대로 돌려준다', () => {
    expect(toCurrentCode('00000')).toBe('00000');
  });
});

describe('카탈로그 적재', () => {
  afterEach(() => {
    vi.doUnmock('node:fs');
    vi.resetModules();
    clearRegionCache();
  });

  test('캐시를 비우면 같은 내용을 다시 읽어 온다', () => {
    const before = loadRegionCatalog();
    clearRegionCache();
    const after = loadRegionCatalog();

    // 캐시를 비웠으므로 새 객체지만 내용은 같아야 한다.
    expect(after).not.toBe(before);
    expect(after.queryableCount).toBe(before.queryableCount);
  });

  test('카탈로그 파일을 읽지 못하면 생성 방법을 안내하며 실패한다', async () => {
    vi.resetModules();
    vi.doMock('node:fs', () => ({
      readFileSync: () => {
        throw new Error('ENOENT: no such file or directory');
      },
    }));

    const mod = await import('./regions.js');
    expect(() => mod.loadRegionCatalog()).toThrow(/npm run regions/);
  });
});
