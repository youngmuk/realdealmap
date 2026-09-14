/**
 * 건물 외곽선을 앱이 쓸 모양으로 굽는다 (행정안전부 도로명주소 건물 도형).
 *
 * **무엇에 쓰나.** 상세창에서 "이 거래가 어느 건물인가"를 보여 준다. 지금은
 * OpenStreetMap 도형을 쓰는데 광진구 실측에서 거래 건물의 **13.5%**만 덮었다.
 * 이 자료는 같은 곳에서 **99.9%**다(`Doc/전자지도-신청.html` 10절).
 *
 *     실거래가 (법정동명|지번)  →  건물DB  →  건물키  →  건물 도형  →  외곽선
 *                                                      ^^^^^^^^^^^^^^^^^^^^^^
 *
 * **법정동으로 쪼개는 이유.** 시군구 하나를 통째로 담으면 광진구가 892KB다.
 * 상세창 하나를 열자고 그것을 받게 할 수는 없다. 법정동이면 수십 KB다 —
 * 사용자가 보고 있는 동네의 것만 받는다.
 *
 * **구멍은 담지 않는다.** 서울 522,836조각 중 구멍이 23개뿐이라, 담는 값보다
 * 앱에서 구멍 있는 도형을 그리는 비용이 크다. 안뜰이 있는 건물은 채워져 보인다.
 *
 * **아직 올리지 않는다.** 이 자료는 보안각서를 쓰고 받은 것이라 국외 반출
 * 가부를 묻고 있다(같은 문서 2절). 답이 오기 전까지 굽기만 하고 배포하지 않는다.
 */
import { toCurrentCode } from '@realdealmap/shared';

import { jusoBuildingKey } from './juso.js';
import type { Polygon } from './shapefile.js';
import { utmkToWgs84 } from './utmk.js';

/** 앱이 읽을 판. 뜻이 달라지면 올린다 — 앱은 모르는 판을 통째로 버린다. */
export const SHAPE_SCHEMA_VERSION = 1;

/** 공공누리 제1유형의 조건이다. 빠지면 재배포가 라이선스 위반이 된다. */
export const SHAPE_ATTRIBUTION = '행정안전부 도로명주소 건물 도형 · 공공누리 제1유형';

/**
 * 좌표를 소수 몇 자리로 줄이나.
 *
 * 6자리는 약 11cm다. 건물 외곽선에 그보다 촘촘할 이유가 없고, 실측으로
 * 동당 40바이트(gzip)였다. 꼭짓점이 평균 9.2개라 단순화는 하지 않는다 —
 * 줄일 것이 없는데 모양만 상한다.
 */
export const SHAPE_DIGITS = 6;

/**
 * 본번·부번을 읽는다. **빈 칸을 0으로 눙치지 않는다.**
 *
 * `Number('')`은 0이라, 그냥 바꾸면 번지가 비어 있는 행이 조용히 `0번지`가 되어
 * 엉뚱한 건물의 열쇠와 겹친다. 겹친 쪽이 상세창에 그려지면 사용자는 그것을
 * 자기가 누른 건물이라고 믿는다.
 */
const houseNumber = (value: string | undefined): number | null => {
  if (value === undefined || value.trim() === '') return null;
  const n = Number(value);
  return Number.isInteger(n) && n >= 0 ? n : null;
};

/** 도형 `.dbf` 한 행에서 우리 열쇠를 만든다. 모양이 안 맞으면 `null`. */
export const shapeBuildingKey = (
  row: Readonly<Record<string, string>>,
): { readonly sggCd: string; readonly buildingKey: string } | null => {
  const sig = row.SIG_CD ?? '';
  const roadNo = row.RN_CD ?? '';
  const under = row.BULD_SE_CD ?? '';
  if (!/^\d{5}$/.test(sig) || !/^\d{7}$/.test(roadNo) || under === '') return null;

  const main = houseNumber(row.BULD_MNNM);
  const sub = houseNumber(row.BULD_SLNO);
  if (main === null || sub === null) return null;

  // 건물DB와 같은 시점의 자료라도 폐지 코드가 섞여 올 수 있다. 열쇠를 만드는
  // 곳이 한 군데뿐이어야 두 쪽이 어긋나지 않는다(entrc.ts와 같은 이유).
  const sggCd = toCurrentCode(sig);
  return { sggCd, buildingKey: jusoBuildingKey(`${sggCd}${roadNo}`, under, main, sub) };
};

/**
 * 링 하나를 `[경도, 위도, ...]`로 옮긴다.
 *
 * 경도가 앞인 것은 GeoJSON과 같은 차례로 두기 위해서다. 점마다 객체를 만들면
 * 전국 720만 동에서 그것만으로 기가바이트다.
 */
export const ringToLngLat = (ring: Float64Array, digits = SHAPE_DIGITS): number[] => {
  const out: number[] = [];
  const round = 10 ** digits;
  for (let i = 0; i < ring.length; i += 2) {
    const { lat, lng } = utmkToWgs84(ring[i]!, ring[i + 1]!);
    out.push(Math.round(lng * round) / round, Math.round(lat * round) / round);
  }
  return out;
};

/** 조각들의 바깥 링만 위경도로 옮긴다. 구멍은 버린다. */
export const outlinesOf = (polygons: readonly Polygon[], digits = SHAPE_DIGITS): number[][] =>
  polygons.map((p) => ringToLngLat(p.outer, digits));

/**
 * 한 법정동의 건물 외곽선.
 *
 * **모양을 따로 두고 지번은 번호로 가리킨다.** 한 건물에 지번이 여럿 딸리는 일이
 * 흔한데(관련지번), 지번마다 모양을 복사하면 같은 건물이 파일 안에 여러 번 들어간다.
 *
 * 지번 하나가 모양 여럿을 가리키는 것도 정상이다 — **아파트 단지**가 그렇다.
 * 거래 자료에는 동 번호가 없으므로 단지의 동을 모두 그리는 편이 정직하다.
 */
export interface DongShapes {
  readonly schemaVersion: number;
  readonly sggCd: string;
  readonly bjdCd: string;
  readonly umdNm: string;
  /** 원자료 시점. 파일명에서 온다(`20260901`) */
  readonly source: string;
  readonly attribution: string;
  /** 조각들. 각각 `[경도, 위도, ...]`로 평평한 바깥 링이다 */
  readonly shapes: readonly (readonly number[])[];
  /** 지번 → [shapes]의 번호들 */
  readonly buildings: Readonly<Record<string, readonly number[]>>;
}

export const dongShapes = (
  meta: { sggCd: string; bjdCd: string; umdNm: string; source: string },
  shapes: readonly (readonly number[])[],
  buildings: Readonly<Record<string, readonly number[]>>,
): DongShapes => ({
  schemaVersion: SHAPE_SCHEMA_VERSION,
  sggCd: meta.sggCd,
  bjdCd: meta.bjdCd,
  umdNm: meta.umdNm,
  source: meta.source,
  attribution: SHAPE_ATTRIBUTION,
  shapes,
  buildings,
});

/**
 * 법정동 파일 한 조각.
 *
 * **큰 동은 쪼갠다.** 서울에서 신림동 하나가 873KB였다 — 상세창 하나를 열자고
 * 받게 할 크기가 아니다. 지번을 사전 순으로 줄 세워 [from]~[to]로 끊는다.
 * 앱은 보고 있는 지번이 든 조각 하나만 받는다.
 *
 * 사전 순인 것은 **셈을 하지 않기 위해서다.** `산 12`·`12-3`을 숫자로 읽으려면
 * 양쪽이 같은 규칙을 써야 하는데, 그 규칙이 어긋나면 조각을 잘못 골라
 * "도형이 없는 건물"로 보인다. 문자열 비교는 어긋날 자리가 없다.
 */
export interface ShapePart {
  readonly file: string;
  /** 이 조각이 담은 첫 지번(사전 순, 포함) */
  readonly from: string;
  /** 마지막 지번(포함) */
  readonly to: string;
  readonly buildings: number;
  readonly bytes: number;
}

export interface ShapeDong {
  readonly bjdCd: string;
  readonly buildings: number;
  readonly bytes: number;
  /** 조각들. 쪼개지 않은 동도 조각 하나로 적는다 — 앱이 한 가지 길만 타게 한다 */
  readonly parts: readonly ShapePart[];
}

/** 시군구 하나의 목차. 앱은 법정동명만 알고 있어 코드로 옮겨 줘야 한다. */
export interface ShapeIndex {
  readonly schemaVersion: number;
  readonly sggCd: string;
  readonly source: string;
  readonly attribution: string;
  /** 법정동명 → 그 동의 조각들 */
  readonly dongs: Readonly<Record<string, ShapeDong>>;
}

/** 지번이 든 조각을 고른다. 없으면 `undefined` — 그 동에 그 지번이 없는 것이다. */
export const partFor = (dong: ShapeDong, jibun: string): ShapePart | undefined =>
  dong.parts.find((p) => p.from <= jibun && jibun <= p.to);

export const shapeIndex = (
  meta: { sggCd: string; source: string },
  dongs: Readonly<Record<string, ShapeDong>>,
): ShapeIndex => ({
  schemaVersion: SHAPE_SCHEMA_VERSION,
  sggCd: meta.sggCd,
  source: meta.source,
  attribution: SHAPE_ATTRIBUTION,
  dongs,
});
