import type { Chunk } from './chunk.js';
import type { R2Client } from './r2.js';

/**
 * 지역 색인 — 앱이 "지금 보는 자리가 어느 시군구인가"를 알아내는 유일한 근거.
 *
 * 경계 폴리곤이 없어서 생긴 자리다. 대안이 둘 있었다.
 *   ① 앱에서 카카오 역지오코딩 → **키가 앱에 박힌다.** 배포된 앱에서 키를 빼내는 것은
 *      막을 수 없고, 우리 쿼터를 아무나 쓰게 된다.
 *   ② Worker가 대신 물어봄 → 지도를 움직일 때마다 요청이다. 무료 한도가 곧
 *      동시 사용자 수 상한이 된다.
 *
 * 그래서 **이미 가진 것으로 만든다.** 배포한 거래에 좌표가 실려 있으므로 그 좌표의
 * 경계상자가 곧 그 지역이 실제로 차지하는 범위다. 행정 경계는 아니지만 앱이 필요한
 * 것은 "어느 지역 데이터를 받을까"지 법정 경계가 아니다. 게다가 공짜고 오프라인이다.
 */

export const INDEX_VERSION = 1;
export const indexObjectKey = (): string => 'v1/regions/index.json';

export interface RegionSummary {
  readonly sggCd: string;
  /** 표시 이름 `서울특별시 강남구` */
  readonly name: string;
  readonly sidoName: string;
  readonly sggName: string;
  /** 좌표가 있는 거래의 경계상자. 좌표가 하나도 없으면 undefined */
  readonly bbox?: BoundingBox;
  /** 지도를 처음 놓을 자리. 경계상자 중심이 아니라 **거래의 중앙값**이다 */
  readonly center?: LatLng;
  /**
   * 이 지역이 **매니페스트에 들고 있는 전체 건수.**
   *
   * 이번 회차에 만든 청크의 건수가 아니다. 매 시간 갱신은 최근 3개월만 다시
   * 만들므로, 그 숫자를 넣으면 12개월을 적재해 둔 지역이 한 시간 뒤에 1/4로
   * 줄어 보인다 — 지역 선택 화면이 그 값을 그대로 보여주므로 사용자에게는
   * "이 지역은 자료가 적다"로 읽힌다. 적재를 통째로 되돌리는 셈이다.
   */
  readonly records: number;

  /**
   * [located]의 분모. 이번 회차에 실제로 훑어 본 건수다.
   *
   * [records]와 나누면 안 된다 — 분자는 이번 회차의 것이고 분모는 전체라서,
   * 좌표 채움 비율이 실제보다 낮게 나온다.
   */
  readonly sampled: number;

  /** 이번 회차에 훑어 본 것 중 좌표가 있는 건수 */
  readonly located: number;
  readonly refreshedAt: string;
}

export interface BoundingBox {
  readonly south: number;
  readonly north: number;
  readonly west: number;
  readonly east: number;
}

export interface LatLng {
  readonly lat: number;
  readonly lng: number;
}

export interface RegionIndex {
  readonly version: number;
  readonly generatedAt: string;
  readonly regions: readonly RegionSummary[];
}

const median = (values: number[]): number => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? ((sorted[mid - 1] as number) + (sorted[mid] as number)) / 2
    : (sorted[mid] as number);
};

const round6 = (value: number): number => Number(value.toFixed(6));

/**
 * 한 지역의 요약을 청크에서 뽑는다.
 *
 * 중심을 평균이 아니라 **중앙값**으로 잡는다. 평균은 외곽에 한 건 있는 토지 거래에
 * 끌려가서 지도가 엉뚱한 곳에서 열린다. 중앙값은 거래가 몰린 곳을 가리킨다.
 */
export const summarize = (
  sggCd: string,
  region: { name?: string; sidoName: string; sggName: string },
  chunks: readonly Chunk[],
  refreshedAt: string,
  /**
   * 매니페스트가 들고 있는 전체 건수. 주지 않으면 이번 청크의 건수를 쓴다
   * (전량을 다시 만든 회차에서는 같은 값이다).
   */
  totalRecords?: number,
): RegionSummary => {
  const lats: number[] = [];
  const lngs: number[] = [];
  let records = 0;

  for (const chunk of chunks) {
    for (const record of chunk.payload.records) {
      records += 1;
      if (record.lat === null || record.lng === null) continue;
      lats.push(record.lat);
      lngs.push(record.lng);
    }
  }

  const base = {
    sggCd,
    name: region.name ?? `${region.sidoName} ${region.sggName}`,
    sidoName: region.sidoName,
    sggName: region.sggName,
    records: totalRecords ?? records,
    sampled: records,
    located: lats.length,
    refreshedAt,
  };

  if (lats.length === 0) return base;

  return {
    ...base,
    bbox: {
      south: round6(Math.min(...lats)),
      north: round6(Math.max(...lats)),
      west: round6(Math.min(...lngs)),
      east: round6(Math.max(...lngs)),
    },
    center: { lat: round6(median(lats)), lng: round6(median(lngs)) },
  };
};

export const emptyIndex = (): RegionIndex => ({
  version: INDEX_VERSION,
  generatedAt: new Date(0).toISOString(),
  regions: [],
});

/** 판이 다르거나 모양이 깨졌으면 빈 색인으로 시작한다. 다시 만들면 되는 파일이다. */
export const parseIndex = (text: string | null): RegionIndex => {
  if (text === null) return emptyIndex();
  try {
    const parsed = JSON.parse(text) as Partial<RegionIndex>;
    if (parsed.version !== INDEX_VERSION) return emptyIndex();
    if (!Array.isArray(parsed.regions)) return emptyIndex();
    return {
      version: INDEX_VERSION,
      generatedAt: parsed.generatedAt ?? new Date(0).toISOString(),
      regions: parsed.regions,
    };
  } catch {
    return emptyIndex();
  }
};

/** 한 지역을 갈아 끼운 새 색인. 코드 순으로 정렬해 바이트가 안정적이다. */
export const withRegion = (
  index: RegionIndex,
  summary: RegionSummary,
  now: Date,
): RegionIndex => ({
  version: INDEX_VERSION,
  generatedAt: now.toISOString(),
  regions: [...index.regions.filter((r) => r.sggCd !== summary.sggCd), summary].sort(
    (a, b) => (a.sggCd < b.sggCd ? -1 : a.sggCd > b.sggCd ? 1 : 0),
  ),
});

/** 내용이 실제로 달라졌는가. 같으면 올리지 않는다 — Class A 연산을 아낀다. */
export const sameSummary = (a: RegionSummary | undefined, b: RegionSummary): boolean =>
  a !== undefined && serializeSummary(a) === serializeSummary(b);

const serializeSummary = (s: RegionSummary): string =>
  JSON.stringify([
    s.sggCd,
    s.name,
    s.records,
    s.sampled,
    s.located,
    s.refreshedAt,
    s.bbox?.south,
    s.bbox?.north,
    s.bbox?.west,
    s.bbox?.east,
    s.center?.lat,
    s.center?.lng,
  ]);

export const readIndex = async (r2: R2Client): Promise<RegionIndex> => {
  const bytes = await r2.get(indexObjectKey());
  return parseIndex(bytes === null ? null : new TextDecoder().decode(bytes));
};

export const writeIndex = async (r2: R2Client, index: RegionIndex): Promise<void> => {
  await r2.put(indexObjectKey(), new TextEncoder().encode(JSON.stringify(index)), {
    contentType: 'application/json',
    // 매니페스트와 같은 이유로 짧게 잡는다. 지역이 늘면 앱이 곧 알아야 한다(§5.3).
    cacheControl: 'public, max-age=300, must-revalidate',
  });
};
