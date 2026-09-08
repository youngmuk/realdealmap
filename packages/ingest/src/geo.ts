import type { GeocodePrecision } from './datasets.js';

import type { Transaction } from './normalize.js';

/**
 * 좌표 사전 — 주소를 좌표로 바꾼 결과를 지역 단위로 모아 둔다 (T3.1).
 *
 * **이 사전의 존재 이유는 쿼터다.** 카카오 일간 한도는 10만인데, 갱신할 때마다
 * 전국을 다시 변환하면 한도를 태우기만 하고 결과는 같다. 주소는 거의 바뀌지 않으므로
 * 한 번 알아낸 좌표는 계속 쓴다.
 *
 * 앱은 이 사전을 받지 않는다. 좌표는 **청크 레코드에 직접 구워서** 나가고(AD-1),
 * 사전은 수집측 캐시로만 존재한다. 앱이 두 파일을 받아 조인하게 만들 이유가 없다.
 */

/** 사전 형식의 판(版). 형식을 바꾸면 올려서 옛 사전을 무시하게 한다. */
export const GEO_VERSION = 1;

export const geoObjectKey = (sggCd: string): string => `v1/geo/${sggCd}.json`;

/**
 * 좌표를 알아낸 경로.
 *
 * `nomatch`도 저장한다. **실패를 기록하지 않으면 갱신할 때마다 같은 주소를 다시
 * 물어보게 되고**, 원천이 모르는 주소일수록 영원히 쿼터를 먹는다.
 */
export type GeoSource = 'kakao' | 'vworld' | 'nomatch';

export interface GeoEntry {
  readonly lat: number;
  readonly lng: number;
  readonly source: GeoSource;
  /** 마지막으로 시도한 날짜 `YYYY-MM-DD`. 실패를 언제 다시 물어볼지 정하는 기준이다 */
  readonly checkedOn: string;
}

export interface GeoDictionary {
  readonly version: number;
  readonly sggCd: string;
  readonly generatedAt: string;
  readonly entries: Readonly<Record<string, GeoEntry>>;
}

/**
 * 사전 열쇠 — `법정동|지번`.
 *
 * **마스킹된 지번은 지번을 버리고 법정동까지만 쓴다.** 카카오가 `*`를 조용히 버리고
 * `논현동 3*`을 `논현동 3`으로 매칭해 "지번 정확 일치"라고 답하기 때문이다
 * (T1.5 실측 226~582 m 오차). 미매칭보다 나쁘다 — 오탐은 엉뚱한 건물에 정확한
 * 마커를 찍는다. 같은 이유로 마스킹된 것들은 하나의 열쇠로 접힌다.
 */
export const geoKey = (umdNm: string, jibun: string | null): string =>
  !jibun || jibun.includes('*') ? `${umdNm}|` : `${umdNm}|${jibun}`;

export const geoKeyOf = (tx: Pick<Transaction, 'umdNm' | 'jibun'>): string =>
  geoKey(tx.umdNm, tx.jibun);

/** 카카오에 실제로 보낼 주소 문자열. 열쇠와 같은 규칙으로 만든다. */
export const geoQuery = (regionName: string, umdNm: string, jibun: string | null): string =>
  !jibun || jibun.includes('*') ? `${regionName} ${umdNm}` : `${regionName} ${umdNm} ${jibun}`;

export const emptyDictionary = (sggCd: string): GeoDictionary => ({
  version: GEO_VERSION,
  sggCd,
  generatedAt: new Date(0).toISOString(),
  entries: {},
});

/**
 * 사전을 읽어 들인다. 판이 다르거나 모양이 깨졌으면 **빈 사전으로 시작한다.**
 *
 * 깨진 사전을 부분적으로 살려 쓰면 어떤 항목이 옛 규칙으로 만들어졌는지 알 수 없다.
 * 다시 변환하는 비용은 쿼터의 몇 %지만, 틀린 좌표는 지도에 그대로 찍힌다.
 */
export const parseDictionary = (sggCd: string, text: string | null): GeoDictionary => {
  if (text === null) return emptyDictionary(sggCd);
  try {
    const parsed = JSON.parse(text) as Partial<GeoDictionary>;
    if (parsed.version !== GEO_VERSION) return emptyDictionary(sggCd);
    if (typeof parsed.entries !== 'object' || parsed.entries === null) {
      return emptyDictionary(sggCd);
    }
    return {
      version: GEO_VERSION,
      sggCd,
      generatedAt: parsed.generatedAt ?? new Date(0).toISOString(),
      entries: parsed.entries,
    };
  } catch {
    return emptyDictionary(sggCd);
  }
};

/**
 * 실패를 다시 물어보기까지 기다리는 날 수.
 *
 * 원천에 없던 주소가 나중에 생기는 일은 있다(신축). 다만 드무므로 자주 물으면
 * 쿼터만 태운다. 한 달이면 신축이 반영될 시간으로 충분하다.
 */
export const NOMATCH_RETRY_DAYS = 30;

const daysBetween = (from: string, to: string): number =>
  Math.floor((Date.parse(to) - Date.parse(from)) / 86_400_000);

/** 이 항목을 다시 물어봐야 하는가. */
export const isStale = (entry: GeoEntry, today: string): boolean =>
  entry.source === 'nomatch' && daysBetween(entry.checkedOn, today) >= NOMATCH_RETRY_DAYS;

export interface MissingAddress {
  readonly key: string;
  readonly umdNm: string;
  readonly jibun: string | null;
  /** 이 주소에 걸린 거래 수. 많은 것부터 처리해 커버리지를 빨리 올린다 */
  readonly deals: number;
}

/**
 * 사전에 없거나 다시 물어볼 때가 된 주소를 뽑는다.
 *
 * 거래 수가 많은 주소를 앞에 둔다. 쿼터가 모자라 중간에 끊겨도 **화면에 보이는
 * 마커가 가장 많이 늘어나는 순서**로 채워진다. 같은 수면 열쇠 순으로 정렬해
 * 실행마다 순서가 흔들리지 않게 한다.
 */
export const findMissing = (
  transactions: readonly Pick<Transaction, 'umdNm' | 'jibun'>[],
  dictionary: GeoDictionary,
  today: string,
): readonly MissingAddress[] => {
  const counts = new Map<string, MissingAddress>();

  for (const tx of transactions) {
    const key = geoKeyOf(tx);
    const known = dictionary.entries[key];
    if (known && !isStale(known, today)) continue;

    const hit = counts.get(key);
    if (hit) {
      counts.set(key, { ...hit, deals: hit.deals + 1 });
      continue;
    }
    // 마스킹된 지번은 열쇠에서 버려지므로 조회 주소에서도 버려야 한다.
    const jibun = !tx.jibun || tx.jibun.includes('*') ? null : tx.jibun;
    counts.set(key, { key, umdNm: tx.umdNm, jibun, deals: 1 });
  }

  return [...counts.values()].sort(
    (a, b) => b.deals - a.deals || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0),
  );
};

/** 항목을 얹은 새 사전을 만든다. 원본은 건드리지 않는다. */
export const withEntries = (
  dictionary: GeoDictionary,
  added: Readonly<Record<string, GeoEntry>>,
  now: Date,
): GeoDictionary => ({
  version: GEO_VERSION,
  sggCd: dictionary.sggCd,
  generatedAt: now.toISOString(),
  entries: { ...dictionary.entries, ...added },
});

/**
 * 좌표를 붙인 결과. 좌표를 못 찾으면 `null`이고, 그 사실이 `precision`에 남는다.
 */
export interface Located {
  readonly lat: number | null;
  readonly lng: number | null;
  readonly precision: GeocodePrecision;
}

/**
 * 이 거래 하나에 실제로 적용되는 정밀도 등급.
 *
 * `DatasetSpec.geocode`는 **유형 전체의 상한**이다. 아파트는 `exact`지만 그건
 * "원천이 대체로 지번을 준다"는 뜻이지 모든 행이 그렇다는 뜻이 아니다.
 * 지번이 가려진 행은 열쇠가 법정동까지만 접히므로 **법정동 중심점**을 받는데,
 * 등급을 유형값 그대로 두면 앱이 그 근사 좌표에 정확한 핀을 찍는다.
 * T1.5 실측으로 그 오차가 226~582 m였다 — 등급이 곧 거짓말이 된다.
 *
 * 그래서 등급을 **행 단위로** 정한다. 우리가 실제로 무엇을 물었는지가 기준이다.
 * 단독·토지는 어차피 전부 가려져 있어 유형 등급과 결과가 같고, 아파트·오피스텔에서
 * 드물게 섞이는 마스킹 행만 정직하게 내려간다.
 */
export const effectivePrecision = (
  tx: Pick<Transaction, 'jibun' | 'precision'>,
): GeocodePrecision => {
  if (!tx.jibun) return 'umd';
  if (tx.jibun.includes('*')) return 'partial';
  return tx.precision;
};

/**
 * 거래 하나에 좌표를 붙인다 (T3.4).
 *
 * **좌표가 없다고 등급을 지우지는 않는다.** 처음엔 `unknown`으로 덮었는데, 그러면
 * "단독주택이라 원천이 지번을 가린 것"과 "아파트인데 지오코딩에 실패한 것"이 같은 값이
 * 되어 앱이 구분할 수 없다. 정보가 줄어드는 설계였다.
 *
 * **미확인은 `lat === null`**로 표현한다. 타입이 `number | null`이라 소비자가 null을
 * 다루지 않으면 컴파일되지 않는다 — "정확한 좌표가 있다"고 잘못 읽힐 여지를 타입이 막는다.
 */
export const locate = (
  tx: Pick<Transaction, 'umdNm' | 'jibun' | 'precision'>,
  dictionary: GeoDictionary,
): Located => {
  const precision = effectivePrecision(tx);
  const entry = dictionary.entries[geoKeyOf(tx)];
  if (!entry || entry.source === 'nomatch') return { lat: null, lng: null, precision };
  return { lat: entry.lat, lng: entry.lng, precision };
};

export interface CoverageRow {
  readonly datasetKey: string;
  readonly total: number;
  readonly located: number;
}

/** 유형별 커버리지 (T3.5). 거래 기준이다 — 사용자가 보는 것은 마커가 아니라 거래다. */
export const coverageByDataset = (
  transactions: readonly Pick<Transaction, 'datasetKey' | 'umdNm' | 'jibun' | 'precision'>[],
  dictionary: GeoDictionary,
): readonly CoverageRow[] => {
  const rows = new Map<string, { total: number; located: number }>();
  for (const tx of transactions) {
    const row = rows.get(tx.datasetKey) ?? { total: 0, located: 0 };
    const hit = locate(tx, dictionary).lat !== null;
    rows.set(tx.datasetKey, { total: row.total + 1, located: row.located + (hit ? 1 : 0) });
  }
  return [...rows.entries()]
    .map(([datasetKey, row]) => ({ datasetKey, ...row }))
    .sort((a, b) => (a.datasetKey < b.datasetKey ? -1 : 1));
};

/** G3 게이트 대상 — 아파트·오피스텔·연립다세대. 단독·토지는 원천이 지번을 가린다. */
export const G3_DATASETS = [
  'apartment/sale',
  'apartment/rent',
  'officetel/sale',
  'officetel/rent',
  'rowhouse/sale',
  'rowhouse/rent',
] as const;

export const G3_THRESHOLD = 0.95;

export interface GateResult {
  readonly total: number;
  readonly located: number;
  readonly ratio: number;
  readonly passed: boolean;
}

/**
 * G3 판정. 대상 유형이 하나도 없으면 **통과가 아니라 미판정**이다.
 *
 * 0건에서 비율을 1로 두면 데이터가 없는 지역이 전부 통과로 보인다 —
 * 게이트처럼 보이기만 하는 게이트가 된다.
 */
export const evaluateG3 = (rows: readonly CoverageRow[]): GateResult | null => {
  const target = rows.filter((r) => (G3_DATASETS as readonly string[]).includes(r.datasetKey));
  const total = target.reduce((a, r) => a + r.total, 0);
  if (total === 0) return null;
  const located = target.reduce((a, r) => a + r.located, 0);
  const ratio = located / total;
  return { total, located, ratio, passed: ratio >= G3_THRESHOLD };
};

/**
 * 커버리지 리포트 (T3.5).
 *
 * G3 대상 유형에 별표를 달아 **왜 어떤 줄은 0%인데 게이트가 통과하는지**를
 * 표 안에서 설명한다. 단독·토지는 원천이 지번을 `3*`처럼 가려 보내므로
 * 애초에 지번 좌표를 얻을 수 없다 — 그걸 모르면 리포트가 고장으로 읽힌다.
 *
 * 미판정(`gate === null`)을 통과로 쓰지 않는다. 데이터가 없는 지역에서
 * 초록 체크가 뜨면 게이트처럼 보이기만 하는 게이트가 된다.
 */
export const coverageMarkdown = (
  sggCd: string,
  rows: readonly CoverageRow[],
  gate: GateResult | null,
): string => {
  const pct = (located: number, total: number): string =>
    total === 0 ? '—' : `${((located / total) * 100).toFixed(1)}%`;

  const target = new Set<string>(G3_DATASETS);
  const body = rows.map(
    (r) =>
      `| ${r.datasetKey}${target.has(r.datasetKey) ? ' *' : ''} | ${r.total.toLocaleString()} | ${r.located.toLocaleString()} | ${pct(r.located, r.total)} |`,
  );

  const verdict =
    gate === null
      ? `미판정 — G3 대상(*) 거래가 0건이다. 통과가 아니다.`
      : `${gate.passed ? '통과' : '실패'} — 대상(*) ${gate.located.toLocaleString()}/${gate.total.toLocaleString()} = ${pct(gate.located, gate.total)} (임계 ${(G3_THRESHOLD * 100).toFixed(0)}%)`;

  return [
    `### ${gate?.passed ? '✅' : gate === null ? '❔' : '⛔'} ${sggCd} 좌표 커버리지`,
    '',
    '| 유형 | 거래 | 좌표 | 비율 |',
    '| --- | ---: | ---: | ---: |',
    ...body,
    '',
    `**G3**: ${verdict}`,
    '',
    '`*` 표시가 G3 대상이다. 단독·토지는 원천이 지번을 마스킹해 제외한다.',
  ].join('\n');
};
