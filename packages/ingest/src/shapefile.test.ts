import { describe, expect, it } from 'vitest';

import {
  dbfRows,
  readDbfHeader,
  readShapefile,
  shapeRecords,
  ShapefileError,
  signedArea,
  type Ring,
} from './shapefile.js';

/**
 * 셰이프파일 리더.
 *
 * **실물 없이 짠다.** 건물 도형은 아직 승인 대기라 손에 없다. 그래서 바이트를
 * 직접 만들어 넣는다 &mdash; 규격이 정한 배치를 시험이 그대로 적어 두는 셈이라,
 * 실물이 오면 "이 배치가 맞나"만 확인하면 된다.
 *
 * 여기서 틀리면 건물이 **엉뚱한 자리에 그려지거나 조용히 사라진다.** 둘 다
 * 화면만 봐서는 "원래 그런가 보다"와 구별되지 않는다.
 *
 * **픽스처는 독립 구현으로 교차 검증했다.** 우리가 만든 바이트를 그대로
 * mbostock/shapefile에 물려 같은 결과가 나오는 것을 확인했다(2026-09-10) —
 * 사각형 하나, 구멍 있는 조각, 두 조각짜리 멀티폴리곤, 그리고 앞자리 0이 살아
 * 있는 `.dbf` 값. 그 과정에서 실제로 머리말 오프셋 오류를 하나 잡았다.
 */

type Point = readonly [number, number];

/** 시계 방향 사각형. 규격에서 바깥 링의 방향이다. */
const clockwise = (x: number, y: number, size = 1): Point[] => [
  [x, y],
  [x, y + size],
  [x + size, y + size],
  [x + size, y],
  [x, y],
];

/** 반시계 방향 사각형. 규격에서 구멍의 방향이다. */
const counterClockwise = (x: number, y: number, size = 1): Point[] =>
  clockwise(x, y, size).slice().reverse();

/** 폴리곤 레코드 하나를 바이트로 만든다. 배치는 ESRI 규격 그대로다. */
const polygonRecord = (rings: readonly Point[][], shapeType = 5): Uint8Array => {
  const numPoints = rings.reduce((sum, r) => sum + r.length, 0);
  const bytes = new Uint8Array(44 + rings.length * 4 + numPoints * 16);
  const dv = new DataView(bytes.buffer);

  dv.setInt32(0, shapeType, true);
  // bbox 를 제대로 채운다. 우리 리더는 건너뛰지만 다른 구현은 볼 수 있고,
  // 이 픽스처는 교차 검증에도 그대로 쓴다.
  const all = rings.flat();
  dv.setFloat64(4, Math.min(...all.map((p) => p[0])), true);
  dv.setFloat64(12, Math.min(...all.map((p) => p[1])), true);
  dv.setFloat64(20, Math.max(...all.map((p) => p[0])), true);
  dv.setFloat64(28, Math.max(...all.map((p) => p[1])), true);
  dv.setInt32(36, rings.length, true);
  dv.setInt32(40, numPoints, true);

  let at = 44;
  let start = 0;
  for (const ring of rings) {
    dv.setInt32(at, start, true);
    at += 4;
    start += ring.length;
  }
  for (const ring of rings) {
    for (const [x, y] of ring) {
      dv.setFloat64(at, x, true);
      dv.setFloat64(at + 8, y, true);
      at += 16;
    }
  }
  return bytes;
};

/** 도형이 없는 레코드. */
const nullRecord = (): Uint8Array => new Uint8Array(4);

const buildShp = (contents: readonly Uint8Array[], fileCode = 9994): Uint8Array => {
  const total = contents.reduce((sum, c) => sum + 8 + c.byteLength, 100);
  const bytes = new Uint8Array(total);
  const dv = new DataView(bytes.buffer);

  dv.setInt32(0, fileCode, false);
  dv.setInt32(24, total / 2, false); // 16비트 낱말 단위
  // 판은 28, 도형 종류는 32, bbox는 36부터다.
  //
  // **처음에 32·36으로 썼다가 틀렸다.** 리더가 이 자리를 읽지 않아 우리 시험은
  // 그대로 통과했고, 독립 구현(mbostock/shapefile)에 같은 바이트를 물려 보고서야
  // 드러났다("unsupported shape type: 1000" — 판 값을 도형 종류로 읽은 것이다).
  // 픽스처를 우리가 만들고 우리가 읽으면 같은 오해가 양쪽에 들어간다.
  dv.setInt32(28, 1000, true);
  dv.setInt32(32, 5, true);

  let at = 100;
  contents.forEach((content, i) => {
    dv.setInt32(at, i + 1, false);
    dv.setInt32(at + 4, content.byteLength / 2, false);
    bytes.set(content, at + 8);
    at += 8 + content.byteLength;
  });
  return bytes;
};

interface Field {
  readonly name: string;
  readonly type?: string;
  readonly length: number;
}

const buildDbf = (
  fields: readonly Field[],
  rows: readonly (readonly string[])[],
  deleted: readonly number[] = [],
  encoding = 'ascii',
): Uint8Array => {
  const headerLength = 32 + fields.length * 32 + 1;
  const recordLength = 1 + fields.reduce((sum, f) => sum + f.length, 0);
  const bytes = new Uint8Array(headerLength + rows.length * recordLength);
  const dv = new DataView(bytes.buffer);

  bytes[0] = 0x03;
  dv.setInt32(4, rows.length, true);
  dv.setInt16(8, headerLength, true);
  dv.setInt16(10, recordLength, true);

  fields.forEach((field, i) => {
    const at = 32 + i * 32;
    for (let c = 0; c < field.name.length && c < 11; c++) {
      bytes[at + c] = field.name.charCodeAt(c);
    }
    bytes[at + 11] = (field.type ?? 'C').charCodeAt(0);
    bytes[at + 16] = field.length;
  });
  bytes[32 + fields.length * 32] = 0x0d;

  rows.forEach((row, i) => {
    const at = headerLength + i * recordLength;
    bytes[at] = deleted.includes(i) ? 0x2a : 0x20;
    let cursor = at + 1;
    fields.forEach((field, c) => {
      // 값은 오른쪽을 공백으로 채운다 — 고정폭이라 그래야 다음 열이 안 밀린다.
      const raw = encode(row[c] ?? '', encoding);
      bytes.set(raw.subarray(0, field.length), cursor);
      for (let k = raw.byteLength; k < field.length; k++) bytes[cursor + k] = 0x20;
      cursor += field.length;
    });
  });
  return bytes;
};

/** 시험용 인코더. ascii는 그대로, euc-kr은 미리 뽑아 둔 바이트를 쓴다. */
const encode = (text: string, encoding: string): Uint8Array => {
  if (encoding !== 'euc-kr') return new Uint8Array([...text].map((c) => c.charCodeAt(0)));
  // '강남' = B0 AD B3 B2 (CP949). 다른 글자는 시험에 쓰지 않는다.
  const table: Record<string, number[]> = { 강: [0xb0, 0xad], 남: [0xb3, 0xb2] };
  return new Uint8Array([...text].flatMap((c) => table[c] ?? [c.charCodeAt(0)]));
};

const points = (ring: Ring): number[] => [...ring];

describe('링 방향', () => {
  // 셰이프파일은 어느 링이 구멍인지 따로 적지 않는다. 방향이 유일한 근거다.
  it('시계는 음수 · 반시계는 양수다', () => {
    expect(signedArea(new Float64Array(clockwise(0, 0).flat()))).toBeLessThan(0);
    expect(signedArea(new Float64Array(counterClockwise(0, 0).flat()))).toBeGreaterThan(0);
  });
});

describe('.shp 읽기', () => {
  it('사각형 하나를 좌표까지 그대로 읽는다', () => {
    const shp = buildShp([polygonRecord([clockwise(10, 20)])]);
    const [record, ...rest] = [...shapeRecords(shp)];

    expect(rest).toEqual([]);
    expect(record?.recordNumber).toBe(1);
    expect(record?.polygons).toHaveLength(1);
    expect(points(record!.polygons[0]!.outer)).toEqual([
      10, 20, 10, 21, 11, 21, 11, 20, 10, 20,
    ]);
  });

  it('반시계 링은 방금 시작한 조각의 구멍이 된다', () => {
    const shp = buildShp([
      polygonRecord([clockwise(0, 0, 10), counterClockwise(3, 3, 2)]),
    ]);
    const [record] = [...shapeRecords(shp)];

    expect(record?.polygons).toHaveLength(1);
    expect(record?.polygons[0]?.holes).toHaveLength(1);
    expect(signedArea(record!.polygons[0]!.holes[0]!)).toBeGreaterThan(0);
  });

  it('시계 링이 또 나오면 새 조각이다', () => {
    const shp = buildShp([polygonRecord([clockwise(0, 0), clockwise(5, 5)])]);
    const [record] = [...shapeRecords(shp)];

    expect(record?.polygons).toHaveLength(2);
    expect(record?.polygons[0]?.holes).toEqual([]);
    expect(record?.polygons[1]?.holes).toEqual([]);
  });

  // 방향이 뒤집힌 자료가 실제로 있다. 그때 첫 링을 구멍으로 보면 건물이
  // 통째로 사라지는데, 사라진 건물은 "원래 없는 건물"과 구별되지 않는다.
  it('첫 링이 반시계여도 건물을 잃지 않는다', () => {
    const shp = buildShp([polygonRecord([counterClockwise(0, 0)])]);
    const [record] = [...shapeRecords(shp)];

    expect(record?.polygons).toHaveLength(1);
    expect(record?.polygons[0]?.holes).toEqual([]);
  });

  it('삼각형도 못 되는 링은 버린다', () => {
    const sliver: Point[] = [
      [0, 0],
      [1, 1],
      [0, 0],
    ];
    const shp = buildShp([polygonRecord([clockwise(0, 0), sliver])]);
    const [record] = [...shapeRecords(shp)];

    expect(record?.polygons).toHaveLength(1);
    expect(record?.polygons[0]?.holes).toEqual([]);
  });

  it('도형이 없는 레코드도 자리를 지킨다', () => {
    const shp = buildShp([nullRecord(), polygonRecord([clockwise(0, 0)])]);
    const records = [...shapeRecords(shp)];

    expect(records).toHaveLength(2);
    expect(records[0]?.polygons).toEqual([]);
    expect(records[1]?.polygons).toHaveLength(1);
  });

  it('Z가 붙은 폴리곤도 x·y 배치가 같아 그대로 읽힌다', () => {
    const shp = buildShp([polygonRecord([clockwise(1, 2)], 15)]);
    const [record] = [...shapeRecords(shp)];

    expect(points(record!.polygons[0]!.outer).slice(0, 2)).toEqual([1, 2]);
  });

  describe('깨진 파일', () => {
    it('파일 코드가 다르면 던진다', () => {
      const shp = buildShp([polygonRecord([clockwise(0, 0)])], 1234);
      expect(() => [...shapeRecords(shp)]).toThrow(ShapefileError);
    });

    it('너무 짧으면 던진다', () => {
      expect(() => [...shapeRecords(new Uint8Array(10))]).toThrow(ShapefileError);
    });

    it('폴리곤이 아니면 던진다 — 조용히 건너뛰지 않는다', () => {
      // 도형 종류 3 = PolyLine.
      const shp = buildShp([polygonRecord([clockwise(0, 0)], 3)]);
      expect(() => [...shapeRecords(shp)]).toThrow(/도형 종류 3/);
    });

    // 내려받다 끊긴 파일이 흔하다. 머리말의 길이만 믿으면 배열 밖을 읽는다.
    it('뒤가 잘렸으면 읽은 데까지만 준다', () => {
      const whole = buildShp([
        polygonRecord([clockwise(0, 0)]),
        polygonRecord([clockwise(5, 5)]),
      ]);
      const cut = whole.subarray(0, whole.byteLength - 40);

      expect([...shapeRecords(cut)]).toHaveLength(1);
    });
  });
});

describe('.dbf 읽기', () => {
  const fields: Field[] = [
    { name: 'RN_CD', length: 12 },
    { name: 'UDRGD_YN', length: 1 },
    { name: 'BULD_MNNM', length: 5, type: 'N' },
  ];

  it('필드 이름과 개수를 읽는다', () => {
    const header = readDbfHeader(buildDbf(fields, [['1', '0', '1']]));

    expect(header.fields.map((f) => f.name)).toEqual(['RN_CD', 'UDRGD_YN', 'BULD_MNNM']);
    expect(header.fields[2]?.type).toBe('N');
    expect(header.recordCount).toBe(1);
  });

  // 열쇠는 자릿수를 맞춘 숫자 문자열이다. 숫자로 바꾸면 앞의 0이 사라져
  // 위치정보요약DB와 이어 붙지 않는다.
  it('값은 문자열로 주고 앞의 0을 지키지 않는다', () => {
    const dbf = buildDbf(fields, [['116804166051', '0', '00011']]);
    const [row] = [...dbfRows(dbf, readDbfHeader(dbf), 'ascii')];

    expect(row).toEqual({
      RN_CD: '116804166051',
      UDRGD_YN: '0',
      BULD_MNNM: '00011',
    });
  });

  it('지워진 줄은 건너뛴다', () => {
    const dbf = buildDbf(fields, [['a', '0', '1'], ['b', '0', '2'], ['c', '0', '3']], [1]);
    const rows = [...dbfRows(dbf, readDbfHeader(dbf), 'ascii')];

    expect(rows.map((r) => r.RN_CD)).toEqual(['a', 'c']);
  });

  it('CP949 한글도 읽는다', () => {
    const dbf = buildDbf([{ name: 'NM', length: 4 }], [['강남']], [], 'euc-kr');
    const [row] = [...dbfRows(dbf, readDbfHeader(dbf), 'euc-kr')];

    expect(row?.NM).toBe('강남');
  });

  it('필드가 없으면 던진다', () => {
    expect(() => readDbfHeader(new Uint8Array(40))).toThrow(ShapefileError);
  });
});

describe('.shp과 .dbf 잇기', () => {
  const fields: Field[] = [{ name: 'RN_CD', length: 3 }];

  it('순번으로 짝지어 준다', () => {
    const shp = buildShp([
      polygonRecord([clockwise(0, 0)]),
      polygonRecord([clockwise(9, 9)]),
    ]);
    const dbf = buildDbf(fields, [['aaa'], ['bbb']]);
    const features = [...readShapefile(shp, dbf, 'ascii')];

    expect(features).toHaveLength(2);
    expect(features[0]?.attributes.RN_CD).toBe('aaa');
    expect(points(features[1]!.polygons[0]!.outer).slice(0, 2)).toEqual([9, 9]);
  });

  it('지워진 줄은 도형까지 함께 버린다', () => {
    const shp = buildShp([
      polygonRecord([clockwise(0, 0)]),
      polygonRecord([clockwise(9, 9)]),
    ]);
    const dbf = buildDbf(fields, [['aaa'], ['bbb']], [0]);
    const features = [...readShapefile(shp, dbf, 'ascii')];

    expect(features).toHaveLength(1);
    expect(features[0]?.attributes.RN_CD).toBe('bbb');
    expect(points(features[0]!.polygons[0]!.outer).slice(0, 2)).toEqual([9, 9]);
  });

  // 개수가 어긋나면 그때부터 모든 건물이 남의 주소를 단다. 좌표도 주소도
  // 각각은 멀쩡해 보여서 눈으로는 절대 못 잡는다.
  it('.dbf가 짧으면 던진다', () => {
    const shp = buildShp([
      polygonRecord([clockwise(0, 0)]),
      polygonRecord([clockwise(9, 9)]),
    ]);
    expect(() => [...readShapefile(shp, buildDbf(fields, [['aaa']]), 'ascii')]).toThrow(
      ShapefileError,
    );
  });

  it('.shp이 짧으면 던진다', () => {
    const shp = buildShp([polygonRecord([clockwise(0, 0)])]);
    const dbf = buildDbf(fields, [['aaa'], ['bbb']]);

    expect(() => [...readShapefile(shp, dbf, 'ascii')]).toThrow(/속성 2개/);
  });
});
