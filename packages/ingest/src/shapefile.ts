/**
 * 셰이프파일(.shp + .dbf)을 읽는다.
 *
 * **무엇에 쓰나.** 행정안전부 **도로명주소 건물 도형**이 SHP으로 온다
 * (`Doc/전자지도-신청.html`). 거래가 일어난 건물의 외곽선을 지도에 그리려면
 * 그 도형이 필요하다 &mdash; 지금 쓰는 OSM 건물은 실측으로 거래 건물의
 * **13.5%**만 덮는다.
 *
 * **왜 직접 읽나.** SHP은 이 저장소가 이미 손으로 뜯고 있는 것들(PMTiles 디렉터리,
 * MVT protobuf)보다 단순하다. 100바이트 헤더에 이어 레코드가 늘어서 있고,
 * 폴리곤은 `bbox · numParts · numPoints · parts · points`가 전부다.
 * 적재 전용이라 앱 크기와도 무관하다.
 *
 * **읽어 들이지 않고 흘려보낸다.** 전국 건물은 수백만 개다. 배열로 다 만들면
 * 그 자체로 기가바이트가 되므로 제너레이터로 한 건씩 넘긴다.
 *
 * 좌표는 UTM-K(EPSG:5179)로 본다 &mdash; 옮기는 일은 `utmk.ts`가 한다.
 * 다만 그것은 **이 파일이 보장하는 것이 아니다.** 받은 `.prj`로 확인해야 한다.
 */

export class ShapefileError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ShapefileError';
  }
}

/** 링 하나. `[x, y, x, y, ...]`로 평평하다. 점마다 객체를 만들지 않기 위해서다. */
export type Ring = Float64Array;

/** 조각 하나. 바깥 링 하나와 그 안의 구멍들. */
export interface Polygon {
  readonly outer: Ring;
  readonly holes: readonly Ring[];
}

export interface ShapeRecord {
  /** 파일 안 순번(1부터). `.dbf`의 같은 순번 행과 짝이다. */
  readonly recordNumber: number;
  /** 조각들. 빈 배열이면 도형이 없는 레코드다(Null Shape). */
  readonly polygons: readonly Polygon[];
}

/** `.shp` 머리말. 앞 100바이트다. */
const HEADER_BYTES = 100;

/** 파일 코드 9994. 빅엔디안으로 맨 앞에 있다. */
const FILE_CODE = 9994;

/**
 * 다룰 수 있는 도형 종류.
 *
 * Z·M이 붙은 것도 **X·Y 부분의 배치가 같다** &mdash; z와 m 배열이 뒤에 더 붙을 뿐이라
 * 읽는 자리는 달라지지 않는다. 우리는 평면만 쓰므로 뒤는 보지 않는다.
 */
const POLYGON_TYPES: ReadonlySet<number> = new Set([5, 15, 25]);

/** 도형이 없는 레코드. 속성만 있고 그린 것이 없는 줄이다. */
const NULL_SHAPE = 0;

const view = (bytes: Uint8Array): DataView =>
  new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

/**
 * 링의 부호 있는 넓이 (신발끈 공식).
 *
 * **구멍을 가려내는 유일한 근거다.** 셰이프파일은 어느 링이 구멍인지 따로 적지
 * 않는다. 규격이 정한 것은 방향뿐이다 &mdash; 바깥은 시계, 구멍은 반시계.
 * y가 위로 자라는 좌표계에서 반시계는 넓이가 양수다.
 *
 * GeoJSON의 &lsquo;첫 링이 바깥&rsquo; 규칙은 여기서 통하지 않는다.
 */
export const signedArea = (ring: Ring): number => {
  let sum = 0;
  const n = ring.length;
  for (let i = 0; i < n; i += 2) {
    const j = (i + 2) % n;
    sum += ring[i]! * ring[j + 1]! - ring[j]! * ring[i + 1]!;
  }
  return sum / 2;
};

/** 링 하나를 떼어 낸다. 점은 `x`(f64) `y`(f64) 차례로 붙어 있다. */
const readRing = (dv: DataView, at: number, from: number, to: number): Ring => {
  const ring = new Float64Array((to - from) * 2);
  for (let i = from; i < to; i++) {
    const p = at + i * 16;
    ring[(i - from) * 2] = dv.getFloat64(p, true);
    ring[(i - from) * 2 + 1] = dv.getFloat64(p + 8, true);
  }
  return ring;
};

/**
 * 링들을 조각으로 묶는다.
 *
 * 시계 방향 링이 나오면 새 조각을 시작하고, 반시계는 방금 시작한 조각의 구멍으로
 * 붙인다. **첫 링이 반시계여도 조각을 시작한다** &mdash; 방향이 뒤집힌 자료가
 * 실제로 있고, 그때 그 링을 구멍으로 취급하면 건물이 통째로 사라진다.
 * 사라진 건물은 화면에서 &ldquo;원래 없는 건물&rdquo;과 구별되지 않는다.
 */
const groupRings = (rings: readonly Ring[]): Polygon[] => {
  const polygons: { outer: Ring; holes: Ring[] }[] = [];
  for (const ring of rings) {
    const isOuter = signedArea(ring) < 0;
    const current = polygons[polygons.length - 1];
    if (isOuter || current === undefined) polygons.push({ outer: ring, holes: [] });
    else current.holes.push(ring);
  }
  return polygons;
};

/** 레코드 하나의 내용에서 조각들을 읽는다. */
const readPolygons = (dv: DataView, start: number, length: number): Polygon[] => {
  const type = dv.getInt32(start, true);
  if (type === NULL_SHAPE) return [];
  if (!POLYGON_TYPES.has(type)) {
    throw new ShapefileError(`폴리곤이 아닙니다: 도형 종류 ${type}`);
  }
  // 종류(4) + bbox(32) 다음이 링 개수와 점 개수다.
  let at = start + 36;
  const numParts = dv.getInt32(at, true);
  const numPoints = dv.getInt32(at + 4, true);
  if (numParts < 0 || numPoints < 0) {
    throw new ShapefileError(`링/점 개수가 음수입니다: ${numParts}, ${numPoints}`);
  }
  at += 8;

  const starts: number[] = [];
  for (let i = 0; i < numParts; i++) starts.push(dv.getInt32(at + i * 4, true));
  at += numParts * 4;

  // 여기서 넘치면 뒤 레코드를 통째로 잘못 읽는다. 그런 파일은 조용히 이상한
  // 좌표를 뱉으므로 여기서 끊는다.
  if (at + numPoints * 16 > start + length) {
    throw new ShapefileError('레코드가 선언한 길이를 넘습니다');
  }

  const rings: Ring[] = [];
  for (let i = 0; i < numParts; i++) {
    const from = starts[i]!;
    const to = i + 1 < numParts ? starts[i + 1]! : numPoints;
    // 삼각형도 못 되는 링은 넓이가 없다. 방향도 정해지지 않아 구멍 판정이 흔들린다.
    if (to - from >= 4) rings.push(readRing(dv, at, from, to));
  }
  return groupRings(rings);
};

/**
 * `.shp`의 레코드를 차례로 넘긴다.
 *
 * 머리말의 파일 길이를 믿지 않고 **바이트 배열의 실제 길이까지만** 읽는다.
 * 잘린 파일(내려받다 끊긴 것)이 흔한데, 머리말만 믿으면 배열 밖을 읽다가
 * 무슨 일인지 알 수 없는 오류로 죽는다.
 */
export function* shapeRecords(shp: Uint8Array): Generator<ShapeRecord> {
  if (shp.byteLength < HEADER_BYTES) {
    throw new ShapefileError(`.shp가 너무 짧습니다: ${shp.byteLength}바이트`);
  }
  const dv = view(shp);
  if (dv.getInt32(0, false) !== FILE_CODE) {
    throw new ShapefileError('.shp 파일이 아닙니다 (파일 코드가 9994가 아님)');
  }

  // 머리말이 말하는 길이는 16비트 낱말 단위다.
  const declared = dv.getInt32(24, false) * 2;
  const end = Math.min(declared, shp.byteLength);

  let at = HEADER_BYTES;
  while (at + 8 <= end) {
    const recordNumber = dv.getInt32(at, false);
    const contentLength = dv.getInt32(at + 4, false) * 2;
    if (contentLength <= 0 || at + 8 + contentLength > end) break;
    yield { recordNumber, polygons: readPolygons(dv, at + 8, contentLength) };
    at += 8 + contentLength;
  }
}

// ------------------------------------------------------------------ .dbf

export interface DbfField {
  readonly name: string;
  /** `C` 문자 · `N` 숫자 · `F` 실수 · `D` 날짜 · `L` 참거짓. 값은 늘 문자열로 준다 */
  readonly type: string;
  readonly length: number;
}

export interface DbfHeader {
  readonly fields: readonly DbfField[];
  readonly recordCount: number;
  readonly headerLength: number;
  readonly recordLength: number;
}

/** 필드 서술자 하나의 크기. 0x0D가 나올 때까지 이어진다. */
const FIELD_BYTES = 32;
const FIELD_TERMINATOR = 0x0d;

/** 지워진 줄 표시. 그 줄은 자리를 차지한 채로 남아 있다. */
const DELETED = 0x2a;

/** 이름은 아스키다. 널 패딩을 잘라 낸다. */
const fieldName = (bytes: Uint8Array): string => {
  let end = 0;
  while (end < 11 && bytes[end] !== 0) end++;
  return new TextDecoder('ascii').decode(bytes.subarray(0, end)).trim();
};

export const readDbfHeader = (dbf: Uint8Array): DbfHeader => {
  if (dbf.byteLength < FIELD_BYTES) {
    throw new ShapefileError(`.dbf가 너무 짧습니다: ${dbf.byteLength}바이트`);
  }
  const dv = view(dbf);
  const recordCount = dv.getInt32(4, true);
  const headerLength = dv.getInt16(8, true);
  const recordLength = dv.getInt16(10, true);
  if (headerLength <= 0 || recordLength <= 0) {
    throw new ShapefileError('.dbf 머리말이 깨졌습니다');
  }

  const fields: DbfField[] = [];
  for (let at = FIELD_BYTES; at + FIELD_BYTES <= headerLength; at += FIELD_BYTES) {
    if (dbf[at] === FIELD_TERMINATOR) break;
    fields.push({
      name: fieldName(dbf.subarray(at, at + 11)),
      type: String.fromCharCode(dbf[at + 11] ?? 0),
      length: dbf[at + 16] ?? 0,
    });
  }
  if (fields.length === 0) throw new ShapefileError('.dbf에 필드가 없습니다');
  return { fields, recordCount, headerLength, recordLength };
};

/**
 * `.dbf`의 행을 차례로 넘긴다. 값은 **전부 문자열**이다.
 *
 * 숫자로 바꾸지 않는 이유: 우리가 쓰는 열쇠(도로명코드·건물본번)는 자릿수를
 * 맞춘 숫자 문자열이라, 숫자로 바꾸면 앞의 0이 사라져 열쇠가 어긋난다.
 * 필요한 쪽에서 골라서 바꾼다.
 *
 * [encoding]의 기본값이 `euc-kr`인 것은 행안부 배포본이 CP949이기 때문이다.
 * 다만 우리가 읽는 열은 전부 숫자라 실제로는 인코딩을 타지 않는다.
 */
export function* dbfRows(
  dbf: Uint8Array,
  header: DbfHeader = readDbfHeader(dbf),
  encoding = 'euc-kr',
): Generator<Record<string, string>> {
  const decoder = new TextDecoder(encoding);
  const { fields, headerLength, recordLength, recordCount } = header;

  for (let i = 0; i < recordCount; i++) {
    const at = headerLength + i * recordLength;
    // 잘린 파일이면 여기서 멈춘다. 반쪽 행을 읽으면 값이 옆으로 밀린다.
    if (at + recordLength > dbf.byteLength) break;
    if (dbf[at] === DELETED) continue;

    const row: Record<string, string> = {};
    let cursor = at + 1;
    for (const field of fields) {
      row[field.name] = decoder.decode(dbf.subarray(cursor, cursor + field.length)).trim();
      cursor += field.length;
    }
    yield row;
  }
}

// ------------------------------------------------------------------ 둘을 잇기

export interface ShapeFeature {
  readonly attributes: Record<string, string>;
  readonly polygons: readonly Polygon[];
}

/**
 * `.shp`과 `.dbf`를 순번으로 짝지어 넘긴다.
 *
 * 두 파일은 **순서로만** 이어져 있다 &mdash; 공통 열쇠가 없다. 한쪽이 잘려
 * 개수가 어긋나면 그때부터 **모든 건물이 남의 주소를 달게 되는데**, 좌표도
 * 주소도 각각은 멀쩡해 보여서 눈으로는 잡히지 않는다. 그래서 개수가 맞지
 * 않으면 던진다.
 *
 * 지워진 행은 `.dbf`에서 건너뛰므로 그 짝인 도형도 함께 버린다.
 */
export function* readShapefile(
  shp: Uint8Array,
  dbf: Uint8Array,
  encoding = 'euc-kr',
): Generator<ShapeFeature> {
  const header = readDbfHeader(dbf);
  const decoder = new TextDecoder(encoding);
  const { fields, headerLength, recordLength } = header;

  let index = 0;
  for (const record of shapeRecords(shp)) {
    const at = headerLength + index * recordLength;
    if (at + recordLength > dbf.byteLength) {
      throw new ShapefileError(
        `.dbf가 .shp보다 짧습니다: 도형 ${record.recordNumber}번의 속성이 없습니다`,
      );
    }
    index++;
    if (dbf[at] === DELETED) continue;

    const attributes: Record<string, string> = {};
    let cursor = at + 1;
    for (const field of fields) {
      attributes[field.name] = decoder
        .decode(dbf.subarray(cursor, cursor + field.length))
        .trim();
      cursor += field.length;
    }
    yield { attributes, polygons: record.polygons };
  }

  if (index < header.recordCount) {
    throw new ShapefileError(
      `.shp가 .dbf보다 짧습니다: 도형 ${index}개 · 속성 ${header.recordCount}개`,
    );
  }
}
