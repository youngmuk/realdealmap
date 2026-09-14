/**
 * 검색 색인 — "주소를 쳐서 그 자리로 간다"의 재료.
 *
 * 앱이 가진 것은 두 가지였다. 전국 **시군구** 목록(`v1/regions/index.json`)과,
 * 지금 열어 둔 지역의 **거래**다. 그 사이가 비어 있다 — 사람이 치는 것은
 * "중곡동"이지 "광진구"가 아니고, 그 동이 어느 구인지는 대개 모른다.
 *
 * 그 사이를 메우는 것이 이 색인이다. 전국 법정동 이름과 중심점 하나씩,
 * 18,696개. 좌표 사전(`build-geo-dict.mjs`)이 이미 만들어 둔 `법정동명|` 항목을
 * 그대로 쓴다 — 그 동에 속한 건물 좌표의 **중앙값**이라 강을 건너거나 길게
 * 늘어진 동에서도 한쪽 끝으로 끌려가지 않는다.
 *
 * **지오코딩이 아니다.** "테헤란로 123"은 여기서 풀리지 않는다. 도로명 단위로
 * 풀려면 외부 API가 필요하고, 그 길은 키 유출과 응답 저장 금지 때문에 이미
 * 접었다. 여기서 답할 수 있는 것은 **동 이름까지**다.
 */

/** 읽을 수 있는 판. 앞으로 나온 판은 무엇이 옛 규칙으로 들어왔는지 알 수 없어 버린다. */
export const SEARCH_SCHEMA_VERSION = 1;

export const SEARCH_ATTRIBUTION = '행정안전부 도로명주소 · 공공누리 제1유형';

/** 좌표 자릿수. 6자리면 약 11cm라 동 중심점에는 넘치고도 남는다. */
export const SEARCH_DIGITS = 6;

/**
 * 법정동 하나. **배열로 담는다** — 객체로 담으면 열쇠 이름이 18,696번 반복돼
 * gzip 전 크기가 두 배가 된다.
 *
 *   `[법정동명, 시군구코드, 위도, 경도]`
 */
export type UmdRow = readonly [string, string, number, number];

export interface UmdIndex {
  readonly schemaVersion: number;
  readonly source: string;
  readonly attribution: string;
  readonly umds: readonly UmdRow[];
}

const round = (n: number): number => {
  const f = 10 ** SEARCH_DIGITS;
  return Math.round(n * f) / f;
};

/**
 * 검색어와 후보를 같은 모양으로 만든다.
 *
 * 공백을 지우는 이유: 사람은 "중곡 동", "중곡동"을 같은 것으로 친다. 원자료에도
 * "성산동1가"와 "성산동 1가"가 섞여 들어온다.
 */
export const normalizeQuery = (s: string): string =>
  s.normalize('NFC').toLowerCase().replace(/\s+/g, '');

/** 한글 음절 첫 자음 19개. 유니코드 순서 그대로다 */
const CHOSEONG = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
] as const;

const HANGUL_BASE = 0xac00;
const HANGUL_LAST = 0xd7a3;
/** 한 초성이 거느리는 음절 수 = 중성 21 × 종성 28 */
const PER_CHOSEONG = 588;

/**
 * "중곡동" → "ㅈㄱㄷ". 한글이 아닌 글자는 그대로 둔다.
 *
 * 초성 검색을 붙이는 이유는 오타 보정이 아니라 **속도**다. 휴대폰에서 "ㅈㄱㄷ"은
 * 세 번 두드리면 끝나는데 "중곡동"은 여덟 번이다.
 */
export const choseongOf = (s: string): string => {
  let out = '';
  for (const ch of s) {
    const code = ch.codePointAt(0) ?? 0;
    if (code >= HANGUL_BASE && code <= HANGUL_LAST) {
      out += CHOSEONG[Math.floor((code - HANGUL_BASE) / PER_CHOSEONG)];
    } else {
      out += ch;
    }
  }
  return out;
};

/** 자음만 친 검색어인가. "ㅈㄱㄷ"은 초성으로, "중곡"은 글자로 맞춰 본다 */
export const isChoseongQuery = (q: string): boolean =>
  q.length > 0 && /^[ㄱ-ㅎ]+$/.test(q);

/**
 * 후보 하나의 점수. 0이면 안 맞는 것이다.
 *
 * **앞에서 맞는 것을 위로 올린다.** "중곡"을 쳤을 때 "중곡동"이 "용중곡리"보다
 * 위에 있어야 한다 — 사람은 이름의 앞을 치지 가운데를 치지 않는다.
 */
export const scoreOf = (text: string, query: string): number => {
  if (query.length === 0) return 0;
  const normalized = normalizeQuery(text);
  if (normalized === query) return 1000;
  if (normalized.startsWith(query)) return 700 - Math.min(normalized.length, 99);
  if (normalized.includes(query)) return 400 - Math.min(normalized.length, 99);

  // 초성은 글자로 맞지 않을 때만 본다. 그러지 않으면 "ㄱㄴ" 같은 짧은 검색어가
  // 온 나라를 다 끌어온다.
  if (isChoseongQuery(query)) {
    const cho = choseongOf(normalized);
    if (cho.startsWith(query)) return 300 - Math.min(cho.length, 99);
    if (cho.includes(query)) return 150 - Math.min(cho.length, 99);
  }
  return 0;
};

/**
 * 좌표 사전이 만든 `법정동명|` 항목을 색인 한 줄로 바꾼다.
 *
 * 이름이 비었거나 좌표가 없는 것은 버린다 — 목록에 이름 없는 칸을 띄우느니
 * 없는 편이 낫고, 좌표가 없으면 골라도 갈 곳이 없다.
 */
export const umdRowsOf = (
  sggCd: string,
  entries: Readonly<Record<string, { lat?: number; lng?: number }>>,
): UmdRow[] => {
  const rows: UmdRow[] = [];
  for (const [key, value] of Object.entries(entries)) {
    if (!key.endsWith('|')) continue;
    const name = key.slice(0, -1).trim();
    if (name.length === 0) continue;
    const { lat, lng } = value;
    if (typeof lat !== 'number' || typeof lng !== 'number') continue;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    rows.push([name, sggCd, round(lat), round(lng)]);
  }
  return rows;
};

/**
 * 색인을 만든다. 이름·시군구 순으로 정렬해 **같은 자료면 같은 바이트**가 나오게 한다 —
 * 그래야 다시 구웠을 때 바뀐 것이 없으면 올릴 것도 없다.
 */
export const umdIndex = (source: string, rows: readonly UmdRow[]): UmdIndex => {
  const seen = new Set<string>();
  const unique: UmdRow[] = [];
  for (const row of rows) {
    const key = `${row[0]}|${row[1]}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(row);
  }
  unique.sort((a, b) => (a[0] === b[0] ? a[1].localeCompare(b[1]) : a[0].localeCompare(b[0])));
  return {
    schemaVersion: SEARCH_SCHEMA_VERSION,
    source,
    attribution: SEARCH_ATTRIBUTION,
    umds: unique,
  };
};
