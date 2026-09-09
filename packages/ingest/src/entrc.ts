/**
 * 도로명주소 위치정보요약DB를 읽는다 (행정안전부).
 *
 * **이 파일이 마지막 칸이다.** `juso.ts`가 `지번 → 건물키`까지 왔고, 여기가
 * `건물키 → 좌표`를 준다.
 *
 *     실거래가 (법정동명|지번)  →  건물DB  →  건물키  →  위치정보요약DB  →  좌표
 *                                                        ^^^^^^^^^^^^^^^^^^^^^^^
 *
 * **형식.** `|` 구분 · CP949 · CRLF · 18열. 시도별로 쪼개져 온다
 * (`entrc_seoul.txt`). 실제 배포본으로 확인했다(202602 전체분).
 * 건물 하나에 한 줄이다 — 서울 524,976줄에 중복 건물키가 0건이었다.
 *
 * 좌표는 UTM-K(EPSG:5179)다. 옮기는 일은 `utmk.ts`가 한다.
 */
import { toCurrentCode } from '@realdealmap/shared';

import { jusoBuildingKey, JUSO_DELIMITER } from './juso.js';

/** 위치정보요약DB 한 줄에서 쓸 것만 뽑은 것. */
export interface EntrcPoint {
  /** 시군구코드 5자리. **현행 코드로 옮긴 것**이다 */
  readonly sggCd: string;
  /** `juso.ts`의 건물키와 같은 모양. 도로명코드도 현행 코드로 옮겼다 */
  readonly buildingKey: string;
  /** UTM-K x (동쪽) */
  readonly x: number;
  /** UTM-K y (북쪽) */
  readonly y: number;
}

/** 열 배치. 실제 배포본(202602)으로 확인했다. */
const COLS = { min: 18, sgg: 0, road: 6, under: 8, bMain: 9, bSub: 10, x: 16, y: 17 } as const;

const num = (value: string | undefined): number | null => {
  if (value === undefined || value.trim() === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

/**
 * 배포 시점이 다른 두 파일을 잇는다.
 *
 * 건물DB는 202608, 위치정보요약DB는 202602다. 그 사이에 **광주광역시와
 * 전라남도가 전남광주통합특별시로 합쳐졌다**. 2월 파일은 통합 전 코드를 쓴다 —
 * 목포시가 `46110`이고 도로명코드가 `461102281002`인데, 8월 건물DB와 앱은
 * 같은 건물을 `12110` · `121102281002`로 부른다. **뒤 7자리는 같고 앞 5자리만
 * 다르다.**
 *
 * 그냥 이으면 이 27개 시군구가 **정확히 0%**가 되고, 나머지 229개는 멀쩡해서
 * 전국 합계는 89%쯤으로 나온다 — "6개월 차이 때문인가 보다"로 읽히는 수다.
 * 실측으로 확인한 실패 모양이라 여기 적어 둔다.
 *
 * 대응표는 이미 있다. `legacy-codes.json`이 R-14(폐지 코드가 오류가 아니라
 * 0건으로 오는 문제) 때문에 만들어져 있고 27개 대응이 전부 들어 있다.
 */
const currentRoadCode = (roadCd: string, currentSgg: string): string =>
  `${currentSgg}${roadCd.slice(5)}`;

/**
 * 갈라진 시군구 — 새 코드 → 그 땅이 원래 속했던 옛 코드들.
 *
 * 두 파일 사이에 **인천이 갈라졌다**. 중구·동구가 제물포구와 영종구로,
 * 서구가 서해구와 검단구로 나뉘었다.
 *
 * 합쳐진 것(광주·전남)은 `legacy-codes.json`이 1:1로 옮겨 주지만, 갈라진 것은
 * **시군구코드만 보고는 어느 쪽인지 알 수 없다.** 옛 중구 하나가 제물포와 영종
 * 둘로 가기 때문이다. 그대로 두면 이 4개 구가 좌표를 하나도 못 받는다.
 *
 * 다행히 **도로명번호(도로명코드 뒤 7자리)는 갈라진 뒤에도 그대로다.** 앞 5자리를
 * 버리고 이으면 98.4~99.8%가 붙고, 갈라진 방향도 실제 개편과 맞는다 —
 * 제물포구는 옛 중구와 동구 양쪽에서, 영종구는 옛 중구에서만 온다.
 *
 * **이 표는 두 파일의 시점 차이 때문에 있는 것이다.** 건물DB와 같은 달의
 * 위치정보요약DB를 받으면 이 표도 `toCurrentCode`도 필요 없어진다.
 */
export const ENTRC_SPLIT_PARENTS: Readonly<Record<string, readonly string[]>> = {
  '28125': ['28110', '28140'], // 제물포구 ← 중구 · 동구
  '28155': ['28110'], //          영종구  ← 중구
  '28275': ['28260'], //          서해구  ← 서구
  '28290': ['28260'], //          검단구  ← 서구
};

/**
 * 시군구코드를 뺀 건물키. 갈라진 구를 이을 때만 쓴다.
 *
 * 도로명번호는 **시군구 안에서만** 유일하므로 이 열쇠도 그 범위에서만 안전하다.
 * 그래서 부르는 쪽이 후보를 [ENTRC_SPLIT_PARENTS]의 옛 구로 좁힌 뒤에 쓴다 —
 * 시도 전체에서 찾으면 엉뚱한 동네 건물에 붙을 수 있고, 그것은 좌표가 없는 것보다
 * 나쁘다.
 */
export const entrcSplitKey = (buildingKey: string): string => {
  const cut = buildingKey.indexOf(JUSO_DELIMITER);
  return `${buildingKey.slice(5, cut)}${buildingKey.slice(cut)}`;
};

/**
 * 한 줄을 읽는다. 모양이 안 맞거나 좌표가 없으면 `null`.
 *
 * **좌표 `(0, 0)`은 없는 값이다.** EPSG:5179에서 (0,0)은 한반도에서 서쪽으로
 * 1,000 km, 남쪽으로 2,000 km 떨어진 **바다 한가운데**다. 표본 171만 줄 중
 * 2,880건(0.17%)이 이랬고 전부 공공용시설이었다. 그대로 옮기면 던지지도 않고
 * 태평양에 핀이 박힌다 — 숫자만 봐서는 알 수 없는 종류의 값이다.
 */
export const parseEntrcRow = (line: string): EntrcPoint | null => {
  const c = line.split(JUSO_DELIMITER);
  if (c.length < COLS.min) return null;

  const roadCd = c[COLS.road] ?? '';
  const under = c[COLS.under] ?? '';
  if (!/^\d{12}$/.test(roadCd) || under === '') return null;

  const bMain = num(c[COLS.bMain]);
  const bSub = num(c[COLS.bSub]);
  const x = num(c[COLS.x]);
  const y = num(c[COLS.y]);
  if (bMain === null || bSub === null || x === null || y === null) return null;
  if (x === 0 && y === 0) return null;

  const sggCd = toCurrentCode(roadCd.slice(0, 5));
  return {
    sggCd,
    buildingKey: jusoBuildingKey(currentRoadCode(roadCd, sggCd), under, bMain, bSub),
    x,
    y,
  };
};

export interface EntrcReport {
  /** 좌표를 담은 건물 수 */
  readonly points: number;
  /** 모양이 안 맞거나 좌표가 없어 건너뛴 줄 수 */
  readonly skipped: number;
  /**
   * 같은 건물키에 **다른 좌표**가 온 횟수.
   *
   * 실측으로는 0이었다(서울 52만 줄). 0이 아니게 되면 건물 하나에 여러 줄인
   * 배포본으로 바뀐 것이므로, 조용히 먼저 온 것을 쓰기 전에 알아야 한다.
   */
  readonly collisions: number;
}

/**
 * 시군구별 `건물키 → (x, y)` 표를 쌓는다.
 *
 * 전국을 한 번에 들 수 없으므로 부르는 쪽이 시도 파일을 나눠 흘려 넣는다.
 * `juso.ts`의 `addJusoRows`와 같은 모양으로 둔 것은 부르는 쪽이 두 파일을
 * 같은 방식으로 다루게 하기 위해서다.
 */
export const addEntrcRows = (
  index: Map<string, Map<string, readonly [number, number]>>,
  lines: Iterable<string>,
): EntrcReport => {
  let points = 0;
  let skipped = 0;
  let collisions = 0;

  for (const line of lines) {
    if (line === '') continue;
    const row = parseEntrcRow(line);
    if (row === null) {
      skipped += 1;
      continue;
    }

    let bucket = index.get(row.sggCd);
    if (bucket === undefined) {
      bucket = new Map();
      index.set(row.sggCd, bucket);
    }

    const seen = bucket.get(row.buildingKey);
    if (seen === undefined) {
      bucket.set(row.buildingKey, [row.x, row.y]);
      points += 1;
    } else if (seen[0] !== row.x || seen[1] !== row.y) {
      collisions += 1;
    }
  }

  return { points, skipped, collisions };
};

export interface SplitReport {
  /** 새로 채운 시군구코드 */
  readonly filled: readonly string[];
  /** 옛 구가 둘인데 도로명번호가 겹쳐 어느 쪽인지 못 정한 건물 수 */
  readonly ambiguous: number;
}

/**
 * 갈라진 구의 좌표 표를 옛 구들에서 만들어 낸다.
 *
 * 옛 구의 도로명코드에서 앞 5자리만 새 구 코드로 바꾸면 색인이 쥐고 있는
 * 건물키와 같은 모양이 된다. 그래서 이 함수가 채워 놓으면 **부르는 쪽은
 * 갈라졌다는 사실을 몰라도 된다** — 조회 경로가 하나로 유지된다.
 *
 * 옛 구가 둘인 경우(제물포구 ← 중구·동구) 도로명번호가 겹칠 수 있다.
 * 도로명번호는 시군구 안에서만 유일하기 때문이다. 겹치면 **버린다** —
 * 반반 확률로 옆 동네에 핀을 찍느니 좌표가 없는 편이 낫다.
 *
 * 이미 그 코드로 들어온 줄이 있으면 아무것도 하지 않는다. 같은 달의
 * 위치정보요약DB를 받으면 그 상태가 되고, 이 함수는 조용히 아무 일도 안 한다.
 */
export const addSplitRegions = (
  index: Map<string, Map<string, readonly [number, number]>>,
): SplitReport => {
  const filled: string[] = [];
  let ambiguous = 0;

  for (const [child, parents] of Object.entries(ENTRC_SPLIT_PARENTS)) {
    if (index.has(child)) continue;
    const sources = parents.filter((p) => index.has(p));
    if (sources.length === 0) continue;

    const bucket = new Map<string, readonly [number, number]>();
    const dropped = new Set<string>();
    for (const parent of sources) {
      for (const [buildingKey, xy] of index.get(parent) ?? []) {
        const key = `${child}${entrcSplitKey(buildingKey)}`;
        const seen = bucket.get(key);
        if (seen === undefined) {
          bucket.set(key, xy);
        } else if (seen[0] !== xy[0] || seen[1] !== xy[1]) {
          bucket.delete(key);
          dropped.add(key);
        }
      }
    }
    ambiguous += dropped.size;
    index.set(child, bucket);
    filled.push(child);
  }

  return { filled, ambiguous };
};
