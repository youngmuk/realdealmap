import { describe, expect, it } from 'vitest';

import {
  addJusoRows,
  jusoBuildingKey,
  jusoGeoKey,
  jusoJibun,
  jusoUmdName,
  parseJusoRow,
} from './juso.js';

/** 실제 배포본(202608 전체분)에서 그대로 가져온 줄이다. 손으로 만든 것이 아니다. */
const BUILDING_ROW =
  '1111010100|서울특별시|종로구|청운동||0|144|3|111103100012|자하문로|0|94|0|||' +
  '1111010100101440003031291|01|1111051500|청운효자동|03047|||||||0|03047|0||';

const JIBUN_ROW = '1111012000|서울특별시|종로구|신문로1가||0|150|0|111102005001|0|149|0|1114|';

describe('법정동명 잇기', () => {
  it('리가 없으면 읍면동명 그대로다', () => {
    expect(jusoUmdName('개포동', '')).toBe('개포동');
  });

  it('리가 있으면 공백으로 잇는다', () => {
    // 국토부 실거래가가 "부안읍 봉덕리"로 준다. 실응답으로 확인했다.
    expect(jusoUmdName('부안읍', '봉덕리')).toBe('부안읍 봉덕리');
  });
});

describe('지번 표기', () => {
  it('부번이 0이면 붙이지 않는다', () => {
    expect(jusoJibun(false, 144, 0)).toBe('144');
  });

  it('부번이 있으면 하이픈으로 잇는다', () => {
    expect(jusoJibun(false, 144, 3)).toBe('144-3');
  });

  it('산 지번은 접두를 단다', () => {
    expect(jusoJibun(true, 12, 0)).toBe('산 12');
  });
});

describe('건물키', () => {
  it('숫자의 자릿수를 지운다', () => {
    // 실거래가는 `00011`, 건물DB는 `11`로 준다. 문자열로 비교하면 안 맞는다.
    expect(jusoBuildingKey('116803122005', '0', 11, 0)).toBe('116803122005|0|11|0');
  });
});

describe('건물DB 한 줄 읽기', () => {
  it('건물정보 줄을 읽는다', () => {
    const row = parseJusoRow(BUILDING_ROW, 'building');
    expect(row).toEqual({
      bjdCd: '1111010100',
      umdNm: '청운동',
      jibun: '144-3',
      buildingKey: '111103100012|0|94|0',
    });
  });

  it('관련지번 줄은 열 배치가 달라도 읽는다', () => {
    // 관련지번에는 도로명·건물명 열이 없어 지하여부부터 한 칸씩 앞이다.
    const row = parseJusoRow(JIBUN_ROW, 'jibun');
    expect(row).toEqual({
      bjdCd: '1111012000',
      umdNm: '신문로1가',
      jibun: '150',
      buildingKey: '111102005001|0|149|0',
    });
  });

  it('열 배치를 잘못 지정하면 엉뚱한 값이 나오지 않고 걸린다', () => {
    // 관련지번 줄을 건물정보로 읽으면 열 수가 모자라 null이다.
    expect(parseJusoRow(JIBUN_ROW, 'building')).toBeNull();
  });

  it('법정동코드가 10자리가 아니면 버린다', () => {
    expect(parseJusoRow(BUILDING_ROW.replace('1111010100|', '11110|'), 'building')).toBeNull();
  });

  it('도로명코드가 12자리가 아니면 버린다', () => {
    expect(parseJusoRow(BUILDING_ROW.replace('111103100012', '1111031'), 'building')).toBeNull();
  });

  it('지번이 비어 있으면 버린다 — 0으로 눙치지 않는다', () => {
    // `|144|3|`을 `||3|`으로 만든다. 0으로 읽으면 있지도 않은 0번지가 생긴다.
    expect(parseJusoRow(BUILDING_ROW.replace('|144|3|', '||3|'), 'building')).toBeNull();
  });

  it('빈 줄은 버린다', () => {
    expect(parseJusoRow('', 'building')).toBeNull();
  });
});

describe('색인 쌓기', () => {
  it('시군구별로 나눠 담는다', () => {
    const index = new Map<string, Map<string, string>>();
    const report = addJusoRows(index, [BUILDING_ROW], 'building');

    expect(report).toEqual({ keys: 1, skipped: 0, collisions: 0 });
    expect(index.get('11110')?.get(jusoGeoKey('청운동', '144-3'))).toBe('111103100012|0|94|0');
  });

  it('같은 지번에 다른 건물이 오면 먼저 온 것을 남기고 센다', () => {
    // 단지형 아파트가 이렇다. 어느 동인지는 실거래가만으로 알 수 없고,
    // 같은 지번 안이라 수십 미터 차이다.
    const other = BUILDING_ROW.replace('|94|0|', '|95|0|');
    const index = new Map<string, Map<string, string>>();
    const report = addJusoRows(index, [BUILDING_ROW, other], 'building');

    expect(report.keys).toBe(1);
    expect(report.collisions).toBe(1);
    expect(index.get('11110')?.get(jusoGeoKey('청운동', '144-3'))).toBe('111103100012|0|94|0');
  });

  it('같은 줄이 두 번 와도 충돌로 세지 않는다', () => {
    const index = new Map<string, Map<string, string>>();
    const report = addJusoRows(index, [BUILDING_ROW, BUILDING_ROW], 'building');
    expect(report).toEqual({ keys: 1, skipped: 0, collisions: 0 });
  });

  it('깨진 줄은 세어서 밖으로 낸다', () => {
    const index = new Map<string, Map<string, string>>();
    const report = addJusoRows(index, [BUILDING_ROW, '이건|줄이|아니다'], 'building');
    expect(report.keys).toBe(1);
    expect(report.skipped).toBe(1);
  });
});
