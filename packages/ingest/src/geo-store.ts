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
 * **압축하지 않는다.** 청크와 달리 이 파일은 앱이 받지 않는 수집측 캐시고,
 * R2 egress는 무료다. 강남구가 40만 바이트 수준이라 아껴야 할 크기도 아니다.
 * gzip으로 올리면 런타임이 자동으로 풀어 주는지가 보장이 아니라 관측이라
 * (`spike-geocode.mjs`가 매직 바이트를 직접 확인해야 했다) 읽는 쪽이 복잡해진다.
 */

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
  return parseDictionary(sggCd, new TextDecoder().decode(bytes));
};

/** 사전을 덮어쓴다. 콘텐츠 해시 경로가 아니라 고정 경로이므로 캐시하지 않는다. */
export const writeDictionary = async (
  r2: R2Client,
  dictionary: GeoDictionary,
): Promise<void> => {
  await r2.put(
    geoObjectKey(dictionary.sggCd),
    new TextEncoder().encode(serialize(dictionary)),
    { contentType: 'application/json', cacheControl: 'no-store' },
  );
};

/** 저장될 바이트. 테스트와 진단에서 쓴다. */
export const dictionaryBytes = (dictionary: GeoDictionary): number =>
  new TextEncoder().encode(serialize(dictionary)).byteLength;
