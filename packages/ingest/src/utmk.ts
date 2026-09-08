/**
 * UTM-K(EPSG:5179) 좌표를 WGS84 경위도로 옮긴다.
 *
 * **왜 필요한가.** 좌표의 원천이 행정안전부 도로명주소로 바뀌었다
 * (`Doc/좌표-복구-계획.html`). 위치정보요약DB의 좌표는 GRS80 UTM-K이고 지도는
 * WGS84 경위도를 쓰므로 한 번 옮겨야 한다. 적재 시점에 한 번 하는 계산이라
 * 앱에는 이미 옮긴 값만 나간다.
 *
 * **왜 직접 안 푸나.** 횡축 메르카토르 역변환은 급수 전개라 부호 하나만 틀려도
 * 수백 미터가 어긋나는데, 그 어긋남은 지도 위에서 "대충 맞는 것"처럼 보인다.
 * 조용히 틀리는 종류의 계산이므로 검증된 구현(proj4)을 쓴다.
 */
import proj4 from 'proj4';

import type { LatLng } from './region-index.js';

/**
 * EPSG:5179 — Korea 2000 / Unified CS.
 *
 * 원점 (127.5°E, 38°N), 축척계수 0.9996, 가경도 1,000,000 · 가위도 2,000,000,
 * GRS80 타원체. 데이텀은 Korea 2000(ITRF2000)으로 WGS84와 실용상 같다 —
 * 이 앱이 다루는 정밀도(미터)에서 둘의 차이는 무시할 수 있다.
 */
const UTMK =
  '+proj=tmerc +lat_0=38 +lon_0=127.5 +k=0.9996 +x_0=1000000 +y_0=2000000 ' +
  '+ellps=GRS80 +units=m +no_defs';

const WGS84 = '+proj=longlat +datum=WGS84 +no_defs';

/** 한반도 남쪽 범위. 이 밖의 값은 좌표계를 잘못 읽은 것이다. */
const BOUNDS = { minLng: 124, maxLng: 132, minLat: 33, maxLat: 39 } as const;

export class UtmkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UtmkError';
  }
}

/**
 * UTM-K (x, y) → WGS84 (lat, lng).
 *
 * 결과가 한반도 밖이면 던진다. 좌표계를 잘못 읽었거나 열을 바꿔 읽은 것인데,
 * 그대로 두면 **지도 위 엉뚱한 자리에 조용히 찍힌다.** 숫자만 봐서는 알 수 없다.
 */
export const utmkToWgs84 = (x: number, y: number): LatLng => {
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    throw new UtmkError(`좌표가 숫자가 아닙니다: (${x}, ${y})`);
  }

  const [lng, lat] = proj4(UTMK, WGS84, [x, y]);
  if (lng === undefined || lat === undefined) {
    throw new UtmkError(`변환에 실패했습니다: (${x}, ${y})`);
  }

  if (
    lng < BOUNDS.minLng ||
    lng > BOUNDS.maxLng ||
    lat < BOUNDS.minLat ||
    lat > BOUNDS.maxLat
  ) {
    throw new UtmkError(
      `한반도 밖입니다: (${x}, ${y}) → ${lat.toFixed(5)}, ${lng.toFixed(5)}. ` +
        'x와 y를 바꿔 읽었거나 좌표계가 다릅니다.',
    );
  }

  // 사전과 청크는 소수점 6자리(약 0.1 m)로 맞춰 둔다. 그보다 잘게 두면
  // 같은 건물의 좌표가 파일마다 미세하게 달라져 청크 해시가 흔들린다.
  return { lat: round6(lat), lng: round6(lng) };
};

/** WGS84 → UTM-K. 검증과 왕복 시험에만 쓴다. */
export const wgs84ToUtmk = (lat: number, lng: number): { x: number; y: number } => {
  const [x, y] = proj4(WGS84, UTMK, [lng, lat]);
  if (x === undefined || y === undefined) {
    throw new UtmkError(`변환에 실패했습니다: (${lat}, ${lng})`);
  }
  return { x, y };
};

const round6 = (value: number): number => Math.round(value * 1e6) / 1e6;
