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
