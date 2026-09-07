import { createHash } from 'node:crypto';
import { constants, gzipSync } from 'node:zlib';

import type { DatasetKey } from '@realdealmap/shared';

import { indexSnapshot } from './identity.js';
import type { Transaction } from './normalize.js';

/**
 * 청크 직렬화 — 정렬 → JSON → gzip → SHA-256.
 *
 * 요구사항은 **결정적 출력**이다. 같은 입력을 두 번 처리하면 바이트까지 같아야
 * 콘텐츠 해시 경로가 성립하고, 내용이 안 바뀌었는데 R2에 새 객체가 쌓이는 일을 막는다.
 * 결정성을 깨는 요소가 셋 있어 각각 막아 두었다(아래 주석 참조).
 */

/** 앱이 받는 거래 한 건. `raw`는 상세화면용 원문이다(FR-3). */
export interface ChunkRecord {
  readonly id: string;
  readonly datasetKey: DatasetKey;
  readonly sggCd: string;
  readonly umdNm: string;
  readonly jibun: string | null;
  readonly name: string | null;
  readonly contractedOn: string;
  readonly areaSqm: number | null;
  readonly floor: number | null;
  readonly builtYear: number | null;
  readonly amount: number | null;
  readonly deposit: number | null;
  readonly monthlyRent: number | null;
  readonly cancelled: boolean;
  readonly cancelledOn: string | null;
  readonly precision: Transaction['precision'];
  readonly raw: Readonly<Record<string, string>>;
}

export interface ChunkPayload {
  readonly sggCd: string;
  readonly datasetKey: DatasetKey;
  /** 계약 연월 `YYYYMM` */
  readonly period: string;
  readonly count: number;
  readonly records: readonly ChunkRecord[];
}

export interface Chunk {
  readonly payload: ChunkPayload;
  /** gzip 바이트 */
  readonly bytes: Buffer;
  /**
   * **압축 전 정규 JSON의** SHA-256. R2 키의 콘텐츠 해시로 쓴다.
   *
   * 압축 결과가 아니라 내용을 해시한다. gzip 바이트는 zlib 버전이나 플랫폼에 따라
   * 달라질 수 있고(헤더의 OS 바이트), 그러면 같은 데이터가 다른 경로에 올라가
   * 콘텐츠 주소화가 무너진다. 내용을 해시하면 어디서 만들든 경로가 같다.
   */
  readonly sha256: string;
  /** 압축 전 JSON 바이트 수 */
  readonly rawSize: number;
}

/**
 * gzip 헤더의 OS 바이트를 "미상"으로 고정한다.
 *
 * Node는 이 자리에 빌드 플랫폼 값을 넣는다(Windows 10, Linux 3). 정보성 필드라
 * 압축 해제에는 영향이 없지만, 그대로 두면 로컬과 CI가 만든 바이트가 달라진다.
 * 업로드 바이트까지 동일하게 만들어 불필요한 재업로드를 막는다.
 */
const OS_UNKNOWN = 255;
const normalizeGzipHeader = (bytes: Buffer): Buffer => {
  const copy = Buffer.from(bytes);
  copy[9] = OS_UNKNOWN;
  return copy;
};

/**
 * 키 순서가 고정된 JSON을 만든다.
 *
 * 결정성 위협 ①: `JSON.stringify`는 객체의 키 삽입 순서를 그대로 쓴다.
 * 같은 데이터라도 필드 순서가 달라지면 바이트가 달라지므로 직접 정렬한다.
 */
const canonical = (value: unknown): string => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;

  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`).join(',')}}`;
};

const toRecord = (id: string, tx: Transaction): ChunkRecord => ({
  id,
  datasetKey: tx.datasetKey,
  sggCd: tx.sggCd,
  umdNm: tx.umdNm,
  jibun: tx.jibun,
  name: tx.name,
  contractedOn: tx.contractedOn,
  areaSqm: tx.areaSqm,
  floor: tx.floor,
  builtYear: tx.builtYear,
  amount: tx.amount,
  deposit: tx.deposit,
  monthlyRent: tx.monthlyRent,
  cancelled: tx.cancelled,
  cancelledOn: tx.cancelledOn,
  precision: tx.precision,
  raw: tx.raw,
});

export class ChunkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ChunkError';
  }
}

/**
 * 계약 연월 `YYYYMM`. 월이 `01`~`12`인지까지 본다.
 *
 * 자릿수만 세면 `202613` 같은 값이 통과한다. 원천은 이런 요청에도
 * `200 · 000 · totalCount=0`으로 답하므로(R-14) **오타가 "거래 없음"으로 위장된다.**
 */
export const PERIOD = /^\d{4}(?:0[1-9]|1[0-2])$/;

/**
 * 시군구 코드 5자리.
 *
 * `period`만 막고 이건 안 막고 있었다. 지금은 호출부(`resolveSggCd`)가 전부 걸러 주지만,
 * 이 모듈은 라이브러리로 export되고 배치 경로(`buildTasks`)는 아직 연결 전이다.
 * 호출자가 검증을 빠뜨리면 R2 오브젝트 키에 그대로 실려 나가므로 경계에서 막는다.
 */
export const SGG_CD = /^\d{5}$/;

/**
 * 한 (시군구 · 유형 · 연월) 묶음을 청크로 만든다.
 *
 * 결정성 위협 ②: gzip 헤더. MTIME은 Node가 0으로 두지만 OS 바이트는 플랫폼값이 들어가므로
 * 고정한다. 애초에 해시는 압축 결과가 아니라 내용을 대상으로 한다.
 * 위협 ③: 레코드 순서. `indexSnapshot`이 id로 정렬해 돌려주므로 입력 순서와 무관하다.
 */
export const buildChunk = (
  sggCd: string,
  datasetKey: DatasetKey,
  period: string,
  transactions: readonly Transaction[],
): Chunk => {
  if (!SGG_CD.test(sggCd)) throw new ChunkError(`시군구 코드 형식이 아님: ${sggCd}`);
  if (!PERIOD.test(period)) throw new ChunkError(`연월 형식이 아님: ${period}`);

  const mismatched = transactions.find((t) => t.datasetKey !== datasetKey);
  if (mismatched) {
    throw new ChunkError(`유형이 섞였다: ${datasetKey} 청크에 ${mismatched.datasetKey}`);
  }

  const records = indexSnapshot(transactions).map((i) => toRecord(i.id, i.transaction));
  const payload: ChunkPayload = { sggCd, datasetKey, period, count: records.length, records };

  const json = Buffer.from(canonical(payload), 'utf8');
  const bytes = normalizeGzipHeader(gzipSync(json, { level: constants.Z_BEST_COMPRESSION }));

  return {
    payload,
    bytes,
    sha256: createHash('sha256').update(json).digest('hex'),
    rawSize: json.byteLength,
  };
};

/** 오브젝트 키의 스키마 버전. 구조가 바뀌면 올려서 구·신을 공존시킨다. */
export const KEY_PREFIX = 'v1/data';

/**
 * 콘텐츠 해시가 박힌 R2 오브젝트 키.
 *
 * 내용이 바뀌면 경로가 바뀌므로 캐시를 무효화할 필요가 없다(§5.3).
 * manifest만 교체하면 앱이 새 청크를 본다.
 *
 * **시군구를 유형보다 앞에 둔다.** 갱신도 정리도 단위가 지역이라
 * `v1/data/11680/`으로 그 지역의 청크를 한 번에 나열할 수 있어야 한다.
 * 유형을 앞에 두면 지역 하나를 훑는 데 9번 나열해야 한다.
 */
export const chunkObjectKey = (chunk: Chunk): string => {
  const type = chunk.payload.datasetKey.replace('/', '-');
  const { sggCd, period } = chunk.payload;
  return `${KEY_PREFIX}/${sggCd}/${period}/${type}.${chunk.sha256.slice(0, 16)}.json.gz`;
};

/** 한 지역의 모든 청크를 덮는 접두사. 정리 작업이 이걸로 훑는다. */
export const regionPrefix = (sggCd: string): string => `${KEY_PREFIX}/${sggCd}/`;

/** 결정성 확인용. 같은 입력이면 같은 해시가 나와야 한다. */
export const isDeterministic = (
  a: readonly Transaction[],
  b: readonly Transaction[],
  sggCd = '11110',
  key: DatasetKey = 'apartment/sale',
  period = '202608',
): boolean =>
  buildChunk(sggCd, key, period, a).sha256 === buildChunk(sggCd, key, period, b).sha256;
