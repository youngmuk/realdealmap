export type { DatasetSpec, FieldMapping, GeocodePrecision } from './datasets.js';
export { DATASETS, datasetKeys, operationOf } from './datasets.js';

export type { XmlElement } from './xml.js';
export { child, children, decodeEntities, parseXml, textOf, XmlParseError } from './xml.js';

export type { ParsedFault, ParsedResponse, ParseResult, RawItem } from './parse.js';
export { hasSchemaDrift, parseResponse, ResponseShapeError } from './parse.js';

export type { NormalizeFailure, NormalizeReport, Transaction } from './normalize.js';
export { NormalizeError, normalizeAll, normalizeItem, parseCancelDate } from './normalize.js';

export type { ChangedTransaction, IndexedTransaction, SnapshotDiff } from './identity.js';
export {
  contentHash,
  contentParts,
  diffSnapshots,
  identityHash,
  identityParts,
  indexSnapshot,
  transactionId,
} from './identity.js';

export type { Chunk, ChunkPayload, ChunkRecord } from './chunk.js';
export {
  buildChunk,
  ChunkError,
  chunkObjectKey,
  isDeterministic,
  KEY_PREFIX,
  PERIOD,
  regionPrefix,
  SGG_CD,
} from './chunk.js';

export type { BuildTasksOptions, Task } from './tasks.js';
export {
  buildTasks,
  countByDataset,
  hotTasks,
  MAX_MONTHS,
  recentPeriods,
  TaskError,
  taskLabel,
} from './tasks.js';

export type { ClientOptions, FetchAllResult, PageResult, RunReport, TaskFailure } from './client.js';
export {
  encodeServiceKey,
  InvalidRequestError,
  MolitClient,
  QuotaExceededError,
  UpstreamError,
} from './client.js';

export type { PutOptions, R2Config } from './r2.js';
export { amzDate, configFromEnv, R2Client, R2ConfigError, R2Error, signRequest } from './r2.js';

export type { HoldReason, Manifest, ManifestFile, PublishOptions, PublishResult } from './publish.js';
export {
  checkRecordDrop,
  findObsoleteChunks,
  findVanishedCombos,
  carryOver,
  manifestKey,
  comboKey,
  publishRegion,
  PublishError,
  readManifest,
  SCHEMA_VERSION,
} from './publish.js';
export {
  GEO_VERSION,
  geoObjectKey,
  geoKey,
  geoKeyOf,
  geoQuery,
  emptyDictionary,
  parseDictionary,
  isStale,
  findMissing,
  withEntries,
  locate,
  coverageByDataset,
  effectivePrecision,
  coverageMarkdown,
  evaluateG3,
  G3_DATASETS,
  G3_THRESHOLD,
  NOMATCH_RETRY_DAYS,
} from './geo.js';
export type {
  GeoSource,
  GeoEntry,
  GeoDictionary,
  MissingAddress,
  Located,
  CoverageRow,
  GateResult,
} from './geo.js';
export { dictionaryBytes, readDictionary, writeDictionary } from './geo-store.js';

export type { BoundingBox, LatLng, RegionIndex, RegionSummary } from './region-index.js';
export {
  COLD_MIN_AGE_HOURS,
  HOT_MIN_AGE_HOURS,
  pickCold,
  pickHot,
} from './region-pick.js';
export {
  emptyIndex,
  indexObjectKey,
  INDEX_VERSION,
  parseIndex,
  readIndex,
  sameSummary,
  summarize,
  updateRegionIndex,
  withRegion,
  writeIndex,
} from './region-index.js';
