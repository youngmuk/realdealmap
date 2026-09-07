import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { LegacyCodeCatalog, Region, RegionCatalog } from './types.js';

const DATA_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../data');

function readJson<T>(fileName: string): T {
  const path = resolve(DATA_DIR, fileName);
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as T;
  } catch (cause) {
    throw new Error(
      `${fileName}을 읽지 못했습니다. \`npm run regions\`로 카탈로그를 먼저 생성하세요.`,
      { cause },
    );
  }
}

let catalogCache: RegionCatalog | undefined;
let legacyCache: LegacyCodeCatalog | undefined;

/** 시군구 카탈로그 전체(상위 시 포함). 최초 호출에서만 파일을 읽는다. */
export function loadRegionCatalog(): RegionCatalog {
  catalogCache ??= readJson<RegionCatalog>('regions.json');
  return catalogCache;
}

export function loadLegacyCatalog(): LegacyCodeCatalog {
  legacyCache ??= readJson<LegacyCodeCatalog>('legacy-codes.json');
  return legacyCache;
}

/**
 * 실제로 수집을 돌릴 시군구 목록.
 * 하위 일반구를 가진 상위 시는 제외되므로 중복 조회가 발생하지 않는다.
 */
export function queryableRegions(): readonly Region[] {
  return loadRegionCatalog().regions.filter((r) => r.queryable);
}

export function findRegion(sggCd: string): Region | undefined {
  return loadRegionCatalog().regions.find((r) => r.sggCd === sggCd);
}

/**
 * 폐지된 시군구 코드를 현행 코드로 옮긴다.
 * 이미 현행 코드이거나 대응을 찾지 못하면 입력을 그대로 돌려준다.
 */
export function toCurrentCode(sggCd: string): string {
  if (findRegion(sggCd)?.queryable) return sggCd;
  const hit = loadLegacyCatalog().mappings.find((m) => m.legacyCd === sggCd);
  return hit ? hit.currentCd : sggCd;
}

/** 테스트에서 캐시를 비울 때 사용한다. */
export function clearRegionCache(): void {
  catalogCache = undefined;
  legacyCache = undefined;
}
