import { constants, gunzipSync, gzipSync } from 'node:zlib';

import {
  emptyDictionary,
  geoObjectKey,
  parseDictionary,
  type GeoDictionary,
  type GeoEntry,
} from './geo.js';
import type { R2Client } from './r2.js';

/**
 * 좌표 사전의 R2 입출력 (T3.1).
 *
 * `geo.ts`는 순수하게 두고 I/O를 여기로 뺐다. 사전의 규칙(열쇠·판·재시도 시점)은
 * 저장소를 몰라야 테스트에서 R2 없이 전부 검증할 수 있다.
 *
 * **압축한다 (2026-09-09에 뒤집은 결정).** 원래는 압축하지 않았고 근거는
 * "강남구가 40만 바이트라 아껴야 할 크기가 아니다"였다. 그 전제가 사라졌다 —
 * 사전은 지오코딩으로 알아낸 주소만 담는 성긴 캐시였는데, 이제 도로명주소
 * 파일에서 만든 **전국 주소 표**다. 강남구가 2.3 MB, 전국 738 MB가 되어
 * 무료 저장 한도 10 GB의 20%를 사전 혼자 쓴다. 압축하면 10%로 줄어든다.
 *
 * `content-encoding: gzip`은 **붙이지 않는다.** 붙이면 읽는 쪽 런타임이 알아서
 * 풀지 말지가 보장이 아니라 관측이 된다 — 원래 이 파일이 압축을 피한 진짜 이유가
 * 그것이었다. 대신 매직 바이트를 보고 우리가 직접 푼다. 압축되지 않은 옛 사전도
 * 그대로 읽힌다.
 */

/** gzip 매직 바이트. 옛 사전(평문 JSON)과 구별하는 데 쓴다. */
const GZIP_MAGIC = [0x1f, 0x8b] as const;

const isGzip = (bytes: Uint8Array): boolean =>
  bytes.length >= 2 && bytes[0] === GZIP_MAGIC[0] && bytes[1] === GZIP_MAGIC[1];

/**
 * 열쇠 순으로 고정된 JSON.
 *
 * 사전은 매 실행마다 다시 쓰인다. 항목 순서가 삽입 순서를 따르면 내용이 같아도
 * 바이트가 달라져, 무엇이 실제로 바뀌었는지 비교할 수 없다.
 */
const serialize = (dictionary: GeoDictionary): string => {
  const entries: Record<string, GeoEntry> = {};
  for (const key of Object.keys(dictionary.entries).sort()) {
    const entry = dictionary.entries[key];
    if (entry) entries[key] = entry;
  }
  return JSON.stringify(
    {
      version: dictionary.version,
      sggCd: dictionary.sggCd,
      generatedAt: dictionary.generatedAt,
      entries,
    },
    null,
    0,
  );
};

/**
 * 사전을 읽는다. 없거나 깨졌으면 **빈 사전**을 준다 — 실패가 아니다.
 *
 * 사전이 없는 것은 첫 실행의 정상 상태다. 여기서 던지면 좌표가 없다는 이유로
 * 수집·배포 전체가 멈춘다. 좌표는 나중에 채워 다시 구우면 붙는다.
 */
export const readDictionary = async (
  r2: R2Client,
  sggCd: string,
): Promise<GeoDictionary> => {
  const bytes = await r2.get(geoObjectKey(sggCd));
  if (bytes === null) return emptyDictionary(sggCd);
  const json = isGzip(bytes) ? gunzipSync(bytes) : bytes;
  return parseDictionary(sggCd, new TextDecoder().decode(json));
};

/** 사전을 덮어쓴다. 콘텐츠 해시 경로가 아니라 고정 경로이므로 캐시하지 않는다. */
export const writeDictionary = async (
  r2: R2Client,
  dictionary: GeoDictionary,
): Promise<void> => {
  await r2.put(geoObjectKey(dictionary.sggCd), dictionaryBody(dictionary), {
    // 실제로 담긴 바이트대로 적는다. `content-encoding`을 쓰지 않는 이유는 위에 있다.
    contentType: 'application/gzip',
    cacheControl: 'no-store',
  });
};

/** 올라가는 바이트. gzip이다. */
export const dictionaryBody = (dictionary: GeoDictionary): Buffer =>
  gzipSync(Buffer.from(serialize(dictionary), 'utf8'), {
    level: constants.Z_BEST_COMPRESSION,
  });

/** 저장될 바이트 수. 테스트와 진단에서 쓴다. */
export const dictionaryBytes = (dictionary: GeoDictionary): number =>
  dictionaryBody(dictionary).byteLength;
