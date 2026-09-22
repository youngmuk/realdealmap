/**
 * 첫 설치용 묶음 — 한 지역의 청크 전부를 파일 하나로.
 *
 * **왜 만드나.** 한 지역은 9종 × 12개월 = 청크 108개다. 앱을 막 깐 사람은
 * 그 108개를 전부 받는다 — 즉 **요청 108번**. 공개 버킷(`r2.dev`)은
 * Cloudflare 캐시를 타지 않아 요청 하나가 그대로 R2 읽기 한 번이고,
 * 무료 한도는 월 1,000만 번이다. 사용자가 늘면 여기서 먼저 막힌다.
 * 묶음 하나면 같은 자료가 요청 **한 번**이 된다.
 *
 * **왜 최신이 아니어도 되나.** 청크 경로에는 내용 해시가 박혀 있다. 묶음이
 * 조금 뒤처져 있으면, 그 안의 옛 청크는 지금 매니페스트의 어느 경로와도
 * 맞지 않아 **그냥 무시된다**. 앱은 묶음으로 덮인 만큼만 쓰고 나머지는
 * 낱개로 받는다. 그래서 묶음을 매번 다시 만들 필요가 없다 —
 * 틀릴 수가 없는 구조라 최신성을 지킬 의무 자체가 없다.
 *
 * **그래서 언제 만드나.** 12개월을 통째로 다시 구운 배포에서만 만든다
 * (`resync-cold` · `backfill`). 3개월만 손대는 예열(`prewarm-hot`)에서
 * 만들려면 나머지 9개월치를 R2에서 도로 받아야 하는데, 그것은 지금 아끼려는
 * 바로 그 요청이다. 주 1회 재수집이 알아서 묶음을 따라잡힌다.
 */
import { createHash } from 'node:crypto';
import { constants, gzipSync } from 'node:zlib';

import { canonical, normalizeGzipHeader, type ChunkPayload } from './chunk.js';

/** 묶음 구조의 판. 모양이 바뀌면 올린다 — 앱은 모르는 판을 통째로 버린다. */
export const BUNDLE_SCHEMA_VERSION = 1;

/** 묶음 안의 청크 하나. `path`는 그때 매니페스트에 있던 경로 그대로다. */
export interface BundleEntry {
  readonly path: string;
  readonly body: ChunkPayload;
}

export interface BundlePayload {
  readonly schemaVersion: number;
  readonly sggCd: string;
  readonly chunks: readonly BundleEntry[];
}

/** 매니페스트가 묶음을 가리키는 방법. */
export interface BundleRef {
  readonly path: string;
  /** **압축 전** 정규 JSON의 해시. 청크와 같은 규칙이다 */
  readonly sha256: string;
  /** 압축 후 바이트. 앱이 "낱개로 받는 것보다 싼가"를 이걸로 판단한다 */
  readonly bytes: number;
  readonly chunks: number;
}

export interface Bundle {
  readonly ref: BundleRef;
  readonly gzip: Buffer;
}

export class BundleError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BundleError';
  }
}

/**
 * 묶음을 만든다.
 *
 * 경로에 내용 해시를 박는 것은 청크와 같은 이유다 — 내용이 바뀌면 경로가
 * 바뀌므로 캐시를 무효화할 일이 없고, 1년 immutable로 걸어도 안전하다.
 */
export const buildBundle = (sggCd: string, entries: readonly BundleEntry[]): Bundle => {
  if (entries.length === 0) throw new BundleError('빈 묶음은 만들지 않는다');

  const mismatched = entries.find((e) => e.body.sggCd !== sggCd);
  if (mismatched) {
    throw new BundleError(`지역이 섞였다: ${sggCd} 묶음에 ${mismatched.body.sggCd}`);
  }

  // 경로로 정렬한다. 같은 자료가 들어오면 같은 바이트가 나와야 경로가 그대로이고,
  // 경로가 그대로여야 이미 올라간 것을 다시 올리지 않는다.
  const sorted = [...entries].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));

  const duplicate = sorted.find((e, i) => i > 0 && e.path === sorted[i - 1]?.path);
  if (duplicate) throw new BundleError(`경로가 겹친다: ${duplicate.path}`);

  const payload: BundlePayload = {
    schemaVersion: BUNDLE_SCHEMA_VERSION,
    sggCd,
    chunks: sorted,
  };

  const json = Buffer.from(canonical(payload), 'utf8');
  const gzip = normalizeGzipHeader(gzipSync(json, { level: constants.Z_BEST_COMPRESSION }));
  const sha256 = createHash('sha256').update(json).digest('hex');

  return {
    gzip,
    ref: {
      path: bundleObjectKey(sggCd, sha256),
      sha256,
      bytes: gzip.byteLength,
      chunks: sorted.length,
    },
  };
};

export const bundleObjectKey = (sggCd: string, sha256: string): string =>
  `v1/regions/${sggCd}/bundle.${sha256.slice(0, 16)}.json.gz`;
