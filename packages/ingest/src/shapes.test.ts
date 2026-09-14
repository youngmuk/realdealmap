import { describe, expect, it } from 'vitest';

import { jusoBuildingKey } from './juso.js';
import type { Polygon } from './shapefile.js';
import {
  dongShapes,
  outlinesOf,
  ringToLngLat,
  SHAPE_SCHEMA_VERSION,
  partFor,
  shapeBuildingKey,
  shapeIndex,
} from './shapes.js';
import { wgs84ToUtmk } from './utmk.js';

/// 건물 외곽선을 굽는 규칙.
///
/// 여기가 틀리면 상세창이 **남의 건물을 그린다.** 좌표도 도형도 각각은 멀쩡해
/// 보이므로 화면만 봐서는 잡히지 않는다.

const row = (over: Record<string, string> = {}): Record<string, string> => ({
  SIG_CD: '11215',
  RN_CD: '3100012',
  BULD_SE_CD: '0',
  BULD_MNNM: '94',
  BULD_SLNO: '0',
  ...over,
});

/** 반시계 사각형 하나(UTM-K). 위경도로 옮겨도 모양은 그대로여야 한다. */
const square = (x: number, y: number, size: number): Float64Array =>
  new Float64Array([x, y, x + size, y, x + size, y + size, x, y + size, x, y]);

describe('건물키', () => {
  // 도형과 색인이 같은 열쇠를 만들어야 이어 붙는다. 한쪽이라도 다르게 만들면
  // 전부 0%가 되고, 그것은 "자료가 없다"로 오해된다.
  it('색인과 같은 모양으로 만든다', () => {
    expect(shapeBuildingKey(row())).toEqual({
      sggCd: '11215',
      buildingKey: jusoBuildingKey('112153100012', '0', 94, 0),
    });
  });

  // .dbf는 자릿수를 맞춘 숫자를 준다. 그대로 두면 색인의 `94`와 안 맞는다.
  it('앞의 0을 지운다', () => {
    expect(shapeBuildingKey(row({ BULD_MNNM: '00094', BULD_SLNO: '00000' }))?.buildingKey).toBe(
      jusoBuildingKey('112153100012', '0', 94, 0),
    );
  });

  // 광주·전남처럼 통합된 곳은 옛 코드가 섞여 온다. 옮기지 않으면 그 시군구가
  // 통째로 0%가 되고, 나머지가 멀쩡해서 합계만 보면 눈치채지 못한다.
  it('폐지된 시군구코드는 현행으로 옮긴다', () => {
    const made = shapeBuildingKey(row({ SIG_CD: '46110', RN_CD: '2281002' }));
    expect(made?.sggCd).toBe('12110');
    expect(made?.buildingKey).toBe(jusoBuildingKey('121102281002', '0', 94, 0));
  });

  it('모양이 안 맞으면 null이다', () => {
    expect(shapeBuildingKey(row({ SIG_CD: '1121' }))).toBeNull();
    expect(shapeBuildingKey(row({ RN_CD: '310001' }))).toBeNull();
    expect(shapeBuildingKey(row({ BULD_SE_CD: '' }))).toBeNull();
    expect(shapeBuildingKey(row({ BULD_MNNM: '' }))).toBeNull();
    expect(shapeBuildingKey(row({ BULD_SLNO: '일이삼' }))).toBeNull();
  });
});

describe('좌표 옮기기', () => {
  it('경도·위도 차례로 6자리까지 준다', () => {
    const { x, y } = wgs84ToUtmk(37.554, 127.079);
    const [lng, lat] = ringToLngLat(new Float64Array([x, y]));

    expect(lng).toBeCloseTo(127.079, 5);
    expect(lat).toBeCloseTo(37.554, 5);
    // 11cm보다 촘촘한 자리는 값만 키운다.
    expect(String(lng).split('.')[1]?.length ?? 0).toBeLessThanOrEqual(6);
  });

  it('점 개수와 차례를 그대로 지킨다', () => {
    const ring = square(950_000, 1_950_000, 20);
    const out = ringToLngLat(ring);

    expect(out).toHaveLength(ring.length);
    // 닫힌 링이면 첫 점과 끝 점이 같아야 한다. 어긋나면 도형이 벌어진다.
    expect(out.slice(0, 2)).toEqual(out.slice(-2));
  });

  // 구멍은 서울 522,836조각 중 23개다. 담는 값보다 앱에서 그리는 비용이 크다.
  it('구멍은 버리고 바깥 링만 남긴다', () => {
    const polygons: Polygon[] = [
      { outer: square(950_000, 1_950_000, 40), holes: [square(950_010, 1_950_010, 10)] },
      { outer: square(950_100, 1_950_100, 20), holes: [] },
    ];

    expect(outlinesOf(polygons)).toHaveLength(2);
  });
});

describe('묶음', () => {
  it('판과 출처를 함께 담는다', () => {
    const made = dongShapes(
      { sggCd: '11215', bjdCd: '1121510100', umdNm: '중곡동', source: '20260901' },
      [[127.07, 37.55, 127.071, 37.55, 127.07, 37.55]],
      { '1-1': [0] },
    );

    expect(made.schemaVersion).toBe(SHAPE_SCHEMA_VERSION);
    expect(made.attribution).toContain('공공누리');
    expect(made.buildings['1-1']).toEqual([0]);
  });

  // 관련지번 때문에 한 건물이 여러 지번에 딸린다. 모양을 복사하지 않고
  // 번호로 가리키므로 같은 건물이 두 번 들어가지 않는다.
  it('여러 지번이 같은 모양을 가리킨다', () => {
    const made = dongShapes(
      { sggCd: '11215', bjdCd: '1121510100', umdNm: '중곡동', source: '20260901' },
      [[127.07, 37.55, 127.071, 37.55, 127.07, 37.55]],
      { '1-1': [0], '1-2': [0] },
    );

    expect(made.shapes).toHaveLength(1);
    expect(made.buildings['1-2']).toEqual(made.buildings['1-1']);
  });

  it('목차는 법정동명으로 찾게 한다', () => {
    const made = shapeIndex(
      { sggCd: '11215', source: '20260901' },
      {
        중곡동: {
          bjdCd: '1121510100',
          buildings: 3,
          bytes: 120,
          parts: [{ file: '1121510100.1.json.gz', from: '1', to: '9-9', buildings: 3, bytes: 120 }],
        },
      },
    );

    expect(made.dongs['중곡동']?.bjdCd).toBe('1121510100');
    expect(made.attribution).toContain('행정안전부');
  });
});

// 큰 동은 쪼개진다. 조각을 잘못 고르면 멀쩡한 건물이 "도형 없음"으로 보이는데,
// 화면에서는 자료가 없는 것과 구별되지 않는다.
describe('조각 고르기', () => {
  const dong = {
    bjdCd: '1162010200',
    buildings: 9,
    bytes: 300,
    parts: [
      { file: 'a.json.gz', from: '1', to: '199-9', buildings: 3, bytes: 100 },
      { file: 'b.json.gz', from: '2', to: '900', buildings: 3, bytes: 100 },
      { file: 'c.json.gz', from: '산 1', to: '산 99', buildings: 3, bytes: 100 },
    ],
  };

  it('경계에 걸친 지번도 제 조각을 찾는다', () => {
    expect(partFor(dong, '1')?.file).toBe('a.json.gz');
    expect(partFor(dong, '199-9')?.file).toBe('a.json.gz');
    expect(partFor(dong, '2')?.file).toBe('b.json.gz');
    expect(partFor(dong, '900')?.file).toBe('b.json.gz');
  });

  it('산 지번도 사전 순 그대로 찾는다', () => {
    expect(partFor(dong, '산 5')?.file).toBe('c.json.gz');
  });

  it('없는 지번은 undefined다', () => {
    expect(partFor(dong, '산 999')).toBeUndefined();
  });
});
