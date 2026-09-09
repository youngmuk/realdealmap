import { describe, expect, it } from 'vitest';

import { addEntrcRows, addSplitRegions, parseEntrcRow } from './entrc.js';

/** 실제 배포본(202602 전체분)에서 그대로 가져온 줄이다. 손으로 만든 것이 아니다. */
const SEOUL_ROW =
  '11110|760|1111010100|서울특별시|종로구|청운동|111103100012|자하문로|0|94|0||' +
  '03047|근린생활시설|0|청운효자동|953241.683263|1954023.466812';

/** 통합 전 코드를 쓰는 줄. 목포시가 아직 `46110`이다. */
const MOKPO_ROW =
  '46110|36153|4611010100|전라남도|목포시|용당동|461102281002|백년대로|0|46|0||' +
  '58732|근린생활시설|0|연동|898862.407683|1645465.912744';

/** 광주광역시 동구. 통합 뒤에는 `12210`이 된다. */
const GWANGJU_ROW =
  '29110|23759|2911010100|광주광역시|동구|대인동|291103009001|구성로|0|194|0||' +
  '61473|유통시설|0|충장동|946629.872373|1684346.068109';

describe('위치정보요약DB 한 줄 읽기', () => {
  it('건물키와 좌표를 뽑는다', () => {
    // 건물키는 juso.test.ts의 같은 건물(청운동 144-3)과 정확히 맞물린다.
    expect(parseEntrcRow(SEOUL_ROW)).toEqual({
      sggCd: '11110',
      buildingKey: '111103100012|0|94|0',
      x: 953241.683263,
      y: 1954023.466812,
    });
  });

  it('열이 모자라면 버린다', () => {
    expect(parseEntrcRow(SEOUL_ROW.split('|').slice(0, 16).join('|'))).toBeNull();
  });

  it('도로명코드가 12자리가 아니면 버린다', () => {
    expect(parseEntrcRow(SEOUL_ROW.replace('111103100012', '1111031'))).toBeNull();
  });

  it('좌표가 비어 있으면 버린다', () => {
    expect(parseEntrcRow(SEOUL_ROW.replace('|953241.683263|', '||'))).toBeNull();
  });

  // (0,0)은 없는 값이다. EPSG:5179에서 한반도 서쪽 1,000km · 남쪽 2,000km,
  // 즉 바다 한가운데다. 실제 배포본에 0.17% 있었고 전부 공공용시설이었다.
  it('좌표가 (0,0)이면 버린다 — 바다 한가운데다', () => {
    const row = SEOUL_ROW.replace('|953241.683263|1954023.466812', '|0|0');
    expect(parseEntrcRow(row)).toBeNull();
  });

  it('빈 줄은 버린다', () => {
    expect(parseEntrcRow('')).toBeNull();
  });
});

describe('통합으로 바뀐 시군구 코드', () => {
  // 위치정보요약DB는 202602, 건물DB는 202608이다. 그 사이에 광주광역시와
  // 전라남도가 전남광주통합특별시로 합쳐졌다. 앞 5자리만 바꾸면 맞물린다.
  it('전라남도 목포시를 통합 후 코드로 옮긴다', () => {
    const row = parseEntrcRow(MOKPO_ROW);

    expect(row?.sggCd).toBe('12110');
    // 뒤 7자리(2281002)는 그대로다. 앞 5자리만 46110 → 12110이다.
    expect(row?.buildingKey).toBe('121102281002|0|46|0');
  });

  it('광주광역시 동구도 같은 규칙으로 옮긴다', () => {
    const row = parseEntrcRow(GWANGJU_ROW);

    expect(row?.sggCd).toBe('12210');
    expect(row?.buildingKey).toBe('122103009001|0|194|0');
  });

  it('바뀌지 않은 코드는 그대로 둔다', () => {
    expect(parseEntrcRow(SEOUL_ROW)?.buildingKey).toBe('111103100012|0|94|0');
  });
});

describe('좌표 표 쌓기', () => {
  it('시군구별로 나눠 담는다', () => {
    const index = new Map<string, Map<string, readonly [number, number]>>();
    const report = addEntrcRows(index, [SEOUL_ROW, MOKPO_ROW]);

    expect(report).toEqual({ points: 2, skipped: 0, collisions: 0 });
    expect(index.get('11110')?.get('111103100012|0|94|0')).toEqual([
      953241.683263, 1954023.466812,
    ]);
    // 통합 후 코드로 담긴다 — 46110이 아니라 12110이다.
    expect(index.has('46110')).toBe(false);
    expect(index.get('12110')?.size).toBe(1);
  });

  it('같은 줄이 두 번 와도 충돌로 세지 않는다', () => {
    const index = new Map<string, Map<string, readonly [number, number]>>();
    expect(addEntrcRows(index, [SEOUL_ROW, SEOUL_ROW])).toEqual({
      points: 1,
      skipped: 0,
      collisions: 0,
    });
  });

  // 실측으로는 0이었다(서울 52만 줄). 0이 아니게 되면 건물 하나에 여러 줄인
  // 배포본으로 바뀐 것이므로, 먼저 온 것을 조용히 쓰기 전에 알아야 한다.
  it('같은 건물에 다른 좌표가 오면 먼저 온 것을 남기고 센다', () => {
    const other = SEOUL_ROW.replace('953241.683263', '953999.000000');
    const index = new Map<string, Map<string, readonly [number, number]>>();
    const report = addEntrcRows(index, [SEOUL_ROW, other]);

    expect(report.points).toBe(1);
    expect(report.collisions).toBe(1);
    expect(index.get('11110')?.get('111103100012|0|94|0')?.[0]).toBe(953241.683263);
  });

  it('깨진 줄은 세어서 밖으로 낸다', () => {
    const index = new Map<string, Map<string, readonly [number, number]>>();
    const report = addEntrcRows(index, [SEOUL_ROW, '이건|줄이|아니다']);

    expect(report.points).toBe(1);
    expect(report.skipped).toBe(1);
  });
});

describe('갈라진 구 채우기', () => {
  const at = (roadCd: string, x: number, y: number): [string, readonly [number, number]] => [
    `${roadCd}|0|1|0`,
    [x, y],
  ];

  it('옛 구의 좌표를 새 구 코드로 옮겨 담는다', () => {
    // 도로명번호(뒤 7자리)는 갈라진 뒤에도 그대로다. 앞 5자리만 바뀐다.
    const index = new Map<string, Map<string, readonly [number, number]>>([
      ['28110', new Map([at('281100001234', 900000, 1900000)])],
    ]);

    const report = addSplitRegions(index);

    expect(report.filled).toContain('28155');
    expect(index.get('28155')?.get('281550001234|0|1|0')).toEqual([900000, 1900000]);
  });

  it('옛 구가 둘이면 양쪽에서 모은다', () => {
    // 제물포구는 옛 중구와 동구 양쪽에서 왔다. 실측으로도 그랬다.
    const index = new Map<string, Map<string, readonly [number, number]>>([
      ['28110', new Map([at('281100000001', 900000, 1900000)])],
      ['28140', new Map([at('281400000002', 900100, 1900100)])],
    ]);

    addSplitRegions(index);

    expect(index.get('28125')?.size).toBe(2);
  });

  // 도로명번호는 시군구 안에서만 유일하다. 옛 구가 둘이면 겹칠 수 있고,
  // 그때 아무거나 고르면 반반 확률로 옆 동네에 핀을 찍는다.
  it('옛 구 둘의 도로명번호가 겹치면 버린다 — 반반으로 찍지 않는다', () => {
    const index = new Map<string, Map<string, readonly [number, number]>>([
      ['28110', new Map([at('281100000001', 900000, 1900000)])],
      ['28140', new Map([at('281400000001', 950000, 1950000)])],
    ]);

    const report = addSplitRegions(index);

    expect(report.ambiguous).toBe(1);
    expect(index.get('28125')?.size).toBe(0);
  });

  it('같은 좌표가 두 번 오는 것은 겹침이 아니다', () => {
    const index = new Map<string, Map<string, readonly [number, number]>>([
      ['28110', new Map([at('281100000001', 900000, 1900000)])],
      ['28140', new Map([at('281400000001', 900000, 1900000)])],
    ]);

    expect(addSplitRegions(index).ambiguous).toBe(0);
    expect(index.get('28125')?.size).toBe(1);
  });

  // 같은 달의 위치정보요약DB를 받으면 이 상태가 된다. 그때는 아무 일도 하지 않아야 한다.
  it('새 코드로 이미 들어와 있으면 건드리지 않는다', () => {
    const mine = new Map([at('281550009999', 800000, 1800000)]);
    const index = new Map<string, Map<string, readonly [number, number]>>([
      ['28110', new Map([at('281100001234', 900000, 1900000)])],
      ['28155', mine],
    ]);

    addSplitRegions(index);

    expect(index.get('28155')).toBe(mine);
    expect(index.get('28155')?.size).toBe(1);
  });

  it('옛 구가 하나도 없으면 만들지 않는다', () => {
    const index = new Map<string, Map<string, readonly [number, number]>>();
    expect(addSplitRegions(index).filled).toEqual([]);
    expect(index.size).toBe(0);
  });
});
