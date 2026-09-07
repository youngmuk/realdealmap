export type {
  DatasetKey,
  LegacyCodeCatalog,
  LegacyCodeMapping,
  PropertyType,
  Region,
  RegionCatalog,
  TradeType,
} from './types.js';

export {
  clearRegionCache,
  findRegion,
  loadLegacyCatalog,
  loadRegionCatalog,
  queryableRegions,
  toCurrentCode,
} from './regions.js';

// Worker용 fs 없는 코드 집합. 생성 파일이다.
export { isQueryableSggCd, QUERYABLE_SGG_CODES } from './codes.generated.js';
