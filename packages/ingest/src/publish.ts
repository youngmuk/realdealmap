import type { PropertyType, TradeType } from '@realdealmap/shared';

import { chunkObjectKey, regionPrefix, type Chunk } from './chunk.js';
import { MAX_MONTHS, recentPeriods } from './tasks.js';
import type { R2Client } from './r2.js';

/**
 * R2 배포 — 청크 업로드와 매니페스트 교체.
 *
 * 규칙 하나가 전부다: **청크가 전부 올라간 뒤에만 매니페스트를 바꾼다.**
 * 매니페스트가 가리키는 청크가 없으면 앱은 빈 화면을 보게 되고,
 * 그 상태가 다음 갱신까지 유지된다. 순서를 뒤집으면 부분 실패가 곧 장애다.
 *
 * 여기에 R-14 대응이 하나 더 붙는다. 원천이 조용히 0건을 주므로
 * "성공했지만 데이터가 비었다"를 배포 직전에 잡아야 한다.
 */

export interface ManifestFile {
  readonly propertyType: PropertyType;
  readonly tradeType: TradeType;
  /** 계약 연월 `YYYYMM` */
  readonly month: string;
  readonly path: string;
  readonly sha256: string;
  readonly bytes: number;
  readonly records: number;
}

export interface Manifest {
  readonly schemaVersion: number;
  readonly sggCd: string;
  /** 앱이 이 값으로 TTL을 판정한다 (§5.2) */
  readonly refreshedAt: string;
  /** 서버가 원격 조정 가능 */
  readonly ttlSeconds: number;
  readonly files: readonly ManifestFile[];
}

export const SCHEMA_VERSION = 1;
export const manifestKey = (sggCd: string): string => `v1/regions/${sggCd}/manifest.json`;

export class PublishError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PublishError';
  }
}

/** 배포가 보류된 이유. 실패와 구분해서 다룬다 — 보류는 이전 상태가 온전히 남는다. */
export type HoldReason =
  /** 직전 대비 건수가 급락했다. 원천의 조용한 0건일 수 있다 (R-14) */
  | { readonly kind: 'recordDrop'; readonly before: number; readonly after: number; readonly ratio: number }
  /**
   * 이전에 있던 (유형 · 월) 조합이 통째로 사라졌다.
   *
   * 합계 게이트만으로는 못 잡는 자리다. 9종 중 하나만 조용히 0건이 되면
   * 나머지 8종이 합계를 떠받쳐 그대로 통과한다 — 원천이 오류 대신 0건을 주는
   * R-14에서 가장 흔한 모습이 바로 이것이다.
   */
  | { readonly kind: 'datasetDrop'; readonly vanished: readonly string[] }
  /** 올려야 할 청크 수가 상한을 넘었다. 폭주 방지 */
  | { readonly kind: 'uploadCap'; readonly needed: number; readonly cap: number };

export interface PublishResult {
  readonly sggCd: string;
  /** 실제로 올린 청크 */
  readonly uploaded: readonly string[];
  /** 내용이 그대로라 올리지 않은 청크. 콘텐츠 해시 경로 덕분에 생긴다 */
  readonly skipped: readonly string[];
  readonly manifestReplaced: boolean;
  readonly hold: HoldReason | undefined;
  readonly manifest: Manifest;
  readonly totalRecords: number;
}

export interface PublishOptions {
  /**
   * 직전 매니페스트 대비 허용하는 최소 건수 비율.
   * 0.5면 절반 아래로 떨어질 때 교체를 보류한다. 0이면 게이트를 끈다.
   */
  readonly minRecordRatio?: number;
  /**
   * 이번 배치가 **다시 만들려고 시도한** 계약 연월.
   *
   * 이어받기의 기준이다. 여기 있는 달은 이번 결과를 그대로 쓰고(0건이면 0건으로
   * 게이트에 걸린다), 여기 없는 달만 이전 매니페스트에서 가져온다.
   * 넘기지 않으면 이어받지 않는다.
   */
  readonly periods?: readonly string[];
  /**
   * 쿼터가 바닥나 **손도 못 댄** 조합 (`comboKey('유형/거래', '연월')`).
   *
   * 이 조합은 이번에 시도하지 않은 것으로 쳐서 이전 매니페스트에서 이어받는다.
   * 넘기지 않으면 못 받은 유형이 사라진 것으로 취급되어 게이트에 걸린다.
   */
  readonly unattempted?: readonly string[];
  /**
   * 이번 배치에 없는 달을 이전 매니페스트에서 **몇 달까지 이어받을지**.
   *
   * 매니페스트는 그 지역에서 살아 있는 파일의 전체 목록이다. 이어받지 않으면
   * 최근 3개월 갱신 한 번이 12개월 적재를 3개월로 줄인다 — 청크는 R2에 그대로
   * 남아 있는데 목록에서 빠져 앱에서 사라진다.
   *
   * 실제로는 그렇게 줄어들기 전에 건수 게이트가 먼저 보류를 건다. 그래서
   * 이어받기가 없으면 12개월을 채운 지역은 **매 시간 갱신이 보류된다.**
   * 조용한 손실은 아니지만 갱신이 멎는다.
   *
   * 0이면 이어받지 않는다(옛 동작).
   */
  readonly retainMonths?: number;
  /** 한 번에 올릴 수 있는 청크 수 상한. Class A 연산 폭주를 막는다 */
  readonly maxUploads?: number;
  readonly ttlSeconds?: number;
  /** 실제로 올리지 않고 계획만 만든다 */
  readonly dryRun?: boolean;
  readonly now?: () => Date;
}

const toManifestFile = (chunk: Chunk): ManifestFile => {
  const [propertyType, tradeType] = chunk.payload.datasetKey.split('/') as [
    PropertyType,
    TradeType,
  ];
  return {
    propertyType,
    tradeType,
    month: chunk.payload.period,
    path: chunkObjectKey(chunk),
    sha256: chunk.sha256,
    bytes: chunk.bytes.byteLength,
    records: chunk.payload.count,
  };
};

/** 매니페스트의 파일 순서를 고정한다. 순서가 흔들리면 내용이 같아도 바이트가 달라진다. */
const sortFiles = (files: readonly ManifestFile[]): readonly ManifestFile[] =>
  [...files].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));

/**
 * 이번 배치에 없는 달을 이전 매니페스트에서 이어받는다.
 *
 * 청크는 콘텐츠 해시 경로에 있고 지우지 않으므로, 옛 달의 항목을 그대로 들고
 * 와도 가리키는 파일은 전부 살아 있다.
 *
 * 보관 창(기본 12개월) 밖은 이어받지 않는다. 그것까지 들고 오면 매니페스트가
 * 영원히 자라고, 앱은 볼 일 없는 달을 계속 내려받는다.
 */
/**
 * (유형 · 월) 조합의 유일한 이름.
 *
 * 보류 사유를 사람에게 보일 때도, 이어받기에서 무엇을 손 못 댔는지 가릴 때도
 * 같은 것을 쓴다. 두 자리에서 형식이 갈라지면 한쪽만 맞는 상태를 아무도 못 본다.
 */
export const comboKey = (datasetKey: string, month: string): string => `${datasetKey} ${month}`;

const fileCombo = (f: ManifestFile): string =>
  comboKey(`${f.propertyType}/${f.tradeType}`, f.month);

export const carryOver = (
  previous: Manifest | undefined,
  attempted: readonly string[] | undefined,
  retainMonths: number,
  now: Date,
  /**
   * 시도하려 했으나 **손도 못 댄** 조합 (`comboKey`).
   *
   * 일일 쿼터가 바닥나면 그 유형은 그 회차에 한 건도 받지 못한다. 그것을
   * "시도했는데 0건"과 같이 다루면 이전 것을 버리게 되고, 유형 하나가 통째로
   * 사라진다 — 원천이 지운 것과 구별되지 않는다. 실제로 전국 적재에서 토지
   * 매매만 쿼터가 바닥났는데, 나머지 여덟 유형이 멀쩡한 지역 174곳이 아무것도
   * 배포하지 못했다.
   *
   * 그래서 못 댄 것은 안 시도한 것으로 친다. 원천이 조용히 0건을 준 경우(R-14)는
   * 여전히 "시도했는데 0건"이라 그대로 게이트에 걸린다.
   */
  unattempted: readonly string[] = [],
): readonly ManifestFile[] => {
  // 무엇을 시도했는지 모르면 이어받지 않는다.
  //
  // 만들어진 달을 기준으로 삼으면 안 된다. 원천이 조용히 0건을 주면(R-14)
  // 그 달은 결과에 없고, 그러면 "안 만든 달"로 보여 이전 것을 그대로 이어받는다.
  // 건수는 그대로니 게이트도 통과한다 — 실종이 완벽하게 감춰진다.
  if (!previous || retainMonths <= 0 || !attempted) return [];

  const rebuilt = new Set(attempted);
  const untouched = new Set(unattempted);
  const keep = new Set(recentPeriods(now, Math.min(retainMonths, MAX_MONTHS)));

  const wasRebuilt = (f: ManifestFile): boolean =>
    rebuilt.has(f.month) && !untouched.has(fileCombo(f));

  return previous.files.filter((f) => !wasRebuilt(f) && keep.has(f.month));
};

const totalRecordsOf = (files: readonly ManifestFile[]): number =>
  files.reduce((sum, f) => sum + f.records, 0);

/** 이전 매니페스트를 읽는다. 없으면(첫 배포) undefined. */
export const readManifest = async (
  r2: R2Client,
  sggCd: string,
): Promise<Manifest | undefined> => {
  const bytes = await r2.get(manifestKey(sggCd));
  if (bytes === null) return undefined;
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as Manifest;
  } catch (error) {
    throw new PublishError(
      `${sggCd}의 기존 매니페스트를 읽을 수 없습니다: ${error instanceof Error ? error.message : error}`,
    );
  }
};

/**
 * 급락 게이트.
 *
 * 첫 배포는 비교 대상이 없으므로 통과시킨다. 0건에서 0건으로 가는 것도 변화가 아니다.
 * 이전이 있었는데 크게 줄어든 경우만 잡는다 — 정상적인 감소(해제 반영 등)는
 * 이 정도로 급격하지 않다.
 */
export const checkRecordDrop = (
  previous: Manifest | undefined,
  nextTotal: number,
  minRatio: number,
): HoldReason | undefined => {
  if (minRatio <= 0 || !previous) return undefined;
  const before = totalRecordsOf(previous.files);
  if (before === 0) return undefined;

  const ratio = nextTotal / before;
  if (ratio >= minRatio) return undefined;
  return { kind: 'recordDrop', before, after: nextTotal, ratio };
};

/**
 * 사라진 (유형 · 월) 조합을 찾는다.
 *
 * 합계 게이트는 **지역 전체가 초토화됐을 때만** 걸린다. 강남구 3개월 5,455건에서
 * 토지 매매가 3개월치 88건 통째로 빠져도 비율은 98.4%라 그냥 통과한다.
 * 원천이 오류 대신 0건을 주는 이상 이건 못 본 채로 배포되고, 그 달 그 유형은
 * 매니페스트에서 조용히 사라진다.
 *
 * 그래서 조합 단위로 한 번 더 본다. 실거래는 사라지지 않는다 — 해제도 삭제가 아니라
 * `cancelled` 상태로 남으므로, 있던 조합이 0건이 되는 것은 정상 경로에 없다.
 *
 * 다만 **이번 배치의 월 범위 밖은 제외한다.** 최근 N개월만 올리므로 창이 밀리면
 * 옛 달이 목록에서 빠지는 것은 정상이다. 그것까지 잡으면 매번 보류된다.
 */
export const findVanishedCombos = (
  previous: readonly ManifestFile[],
  next: readonly ManifestFile[],
): readonly string[] => {
  const months = new Set(next.map((f) => f.month));
  const records = new Map(next.map((f) => [fileCombo(f), f.records]));

  const vanished = previous
    .filter((f) => f.records > 0 && months.has(f.month))
    .filter((f) => (records.get(fileCombo(f)) ?? 0) === 0)
    .map(fileCombo);

  return [...new Set(vanished)].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
};

/** 조합 실종을 보류 사유로 바꾼다. 사라진 게 없으면 undefined. */
const vanishHold = (
  previous: Manifest | undefined,
  next: readonly ManifestFile[],
  minRatio: number,
): HoldReason | undefined => {
  if (minRatio <= 0 || !previous) return undefined;
  const vanished = findVanishedCombos(previous.files, next);
  return vanished.length > 0 ? { kind: 'datasetDrop', vanished } : undefined;
};

/**
 * 한 지역의 청크를 올리고 매니페스트를 교체한다.
 *
 * 이미 같은 콘텐츠 해시로 올라가 있는 청크는 건너뛴다. 경로에 해시가 박혀 있으므로
 * 존재하면 내용이 같다는 뜻이고, 다시 올릴 이유가 없다(Class A 절약).
 */
export const publishRegion = async (
  r2: R2Client,
  sggCd: string,
  chunks: readonly Chunk[],
  options: PublishOptions = {},
): Promise<PublishResult> => {
  const {
    minRecordRatio = 0.5,
    maxUploads = 200,
    ttlSeconds = 3600,
    retainMonths = MAX_MONTHS,
    periods,
    unattempted = [],
    dryRun = false,
    now = () => new Date(),
  } = options;

  const mismatched = chunks.find((c) => c.payload.sggCd !== sggCd);
  if (mismatched) {
    throw new PublishError(`지역이 섞였다: ${sggCd} 배포에 ${mismatched.payload.sggCd}`);
  }

  // 이전 매니페스트를 **먼저** 읽는다. 이번에 안 만든 달을 거기서 이어받아야
  // 하므로, 목록을 짜기 전에 있어야 한다.
  const previous = await readManifest(r2, sggCd);

  const fresh = chunks.map(toManifestFile);
  const files = sortFiles([
    ...fresh,
    ...carryOver(previous, periods, retainMonths, now(), unattempted),
  ]);
  const totalRecords = totalRecordsOf(files);
  const manifest: Manifest = {
    schemaVersion: SCHEMA_VERSION,
    sggCd,
    refreshedAt: now().toISOString(),
    ttlSeconds,
    files,
  };

  // 게이트 둘을 순서대로 본다. 합계는 지역 전체의 붕괴를, 조합은 한 유형의 실종을 잡는다.
  // `minRecordRatio <= 0`은 둘 다 끄는 스위치다 — R-14 방어를 통째로 내리는 것이므로
  // 유형을 정말로 수집 중단할 때만 쓴다.
  const drop =
    checkRecordDrop(previous, totalRecords, minRecordRatio) ??
    vanishHold(previous, files, minRecordRatio);
  if (drop) {
    // 보류다. 청크도 올리지 않는다 — 어차피 매니페스트를 바꾸지 않으면 아무도 안 본다.
    return {
      sggCd,
      uploaded: [],
      skipped: [],
      manifestReplaced: false,
      hold: drop,
      manifest,
      totalRecords,
    };
  }

  // 이미 올라가 있는 것을 먼저 걸러낸다.
  const pending: Chunk[] = [];
  const skipped: string[] = [];
  for (const chunk of chunks) {
    const key = chunkObjectKey(chunk);
    if (await r2.exists(key)) skipped.push(key);
    else pending.push(chunk);
  }

  if (pending.length > maxUploads) {
    return {
      sggCd,
      uploaded: [],
      skipped,
      manifestReplaced: false,
      hold: { kind: 'uploadCap', needed: pending.length, cap: maxUploads },
      manifest,
      totalRecords,
    };
  }

  if (dryRun) {
    return {
      sggCd,
      uploaded: pending.map(chunkObjectKey),
      skipped,
      manifestReplaced: false,
      hold: undefined,
      manifest,
      totalRecords,
    };
  }

  // 청크를 먼저 전부 올린다. 하나라도 실패하면 여기서 던지고 매니페스트는 손대지 않는다.
  const uploaded: string[] = [];
  for (const chunk of pending) {
    const key = chunkObjectKey(chunk);
    await r2.put(key, chunk.bytes, {
      contentType: 'application/json',
      contentEncoding: 'gzip',
      // 콘텐츠 해시 경로라 내용이 바뀌면 경로가 바뀐다. 영구 캐시해도 안전하다.
      cacheControl: 'public, max-age=31536000, immutable',
    });
    uploaded.push(key);
  }

  // 전량 성공한 뒤에야 매니페스트를 바꾼다.
  await r2.put(
    manifestKey(sggCd),
    new TextEncoder().encode(JSON.stringify(manifest, null, 2)),
    {
      contentType: 'application/json',
      // 앱이 TTL을 판정하는 입구다. 짧게 잡고 매번 확인하게 한다(§5.3).
      cacheControl: 'public, max-age=60, must-revalidate',
    },
  );

  return {
    sggCd,
    uploaded,
    skipped,
    manifestReplaced: true,
    hold: undefined,
    manifest,
    totalRecords,
  };
};

/**
 * 매니페스트가 가리키지 않는 낡은 청크를 찾는다.
 *
 * **찾기만 하고 지우지 않는다.** 앱이 이전 매니페스트를 캐시하고 있을 수 있어,
 * 교체 직후 삭제하면 그 앱은 404를 만난다. 보관 기간을 둔 별도 작업이 지운다.
 */
export const findObsoleteChunks = async (
  r2: R2Client,
  sggCd: string,
  manifest: Manifest,
): Promise<readonly string[]> => {
  const live = new Set(manifest.files.map((f) => f.path));
  const obsolete: string[] = [];

  let token: string | undefined;
  do {
    const page = await r2.list(regionPrefix(sggCd), token);
    for (const key of page.keys) if (!live.has(key)) obsolete.push(key);
    token = page.nextToken;
  } while (token);

  return obsolete;
};
