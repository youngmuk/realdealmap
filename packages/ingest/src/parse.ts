import type { DatasetKey } from '@realdealmap/shared';

import { DATASETS } from './datasets.js';
import { child, children, parseXml, textOf, type XmlElement } from './xml.js';

/** item 하나의 원문. 값은 trim만 거친 문자열이며 정규화는 다음 단계에서 한다. */
export type RawItem = Readonly<Record<string, string>>;

/**
 * 성공 응답(`<response>` 봉투).
 *
 * `unknownFields`·`missingFields`는 R-14 대응이다. 원천이 스키마를 바꿔도
 * 오류를 주지 않으므로, 파서가 차이를 드러내지 않으면 필드가 조용히 사라진다.
 */
export interface ParsedResponse {
  readonly kind: 'data';
  readonly resultCode: string;
  readonly resultMsg: string;
  readonly totalCount: number;
  readonly pageNo: number;
  readonly numOfRows: number;
  readonly items: readonly RawItem[];
  /** 명세에 없는데 응답에 나타난 필드 (원천 확장) */
  readonly unknownFields: readonly string[];
  /** 명세에 있는데 어떤 item에도 없던 필드 (원천 축소) */
  readonly missingFields: readonly string[];
}

/** 인증·권한 오류 봉투(`<OpenAPI_ServiceResponse>`). HTTP 4xx와 함께 온다. */
export interface ParsedFault {
  readonly kind: 'fault';
  /** `returnReasonCode`. §3.1 에러코드 표와 같은 체계다 */
  readonly code: string;
  /** `errMsg` — 기계 판독용 (예: SERVICE_KEY_IS_NOT_REGISTERED_ERROR) */
  readonly errMsg: string;
  /** `returnAuthMsg` — 사람이 읽는 설명 */
  readonly authMsg: string;
}

export type ParseResult = ParsedResponse | ParsedFault;

export class ResponseShapeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ResponseShapeError';
  }
}

/** 숫자 봉투 항목. 없거나 숫자가 아니면 오류다 — 조용히 0으로 두면 안 된다. */
const intOf = (element: XmlElement, name: string): number => {
  const raw = textOf(element, name);
  if (raw === '') throw new ResponseShapeError(`<${name}>이 없습니다`);
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 0) {
    throw new ResponseShapeError(`<${name}>이 음이 아닌 정수가 아닙니다: ${raw}`);
  }
  return value;
};

const toRawItem = (item: XmlElement): RawItem =>
  Object.fromEntries(item.children.map((f) => [f.name, f.text.trim()]));

const parseFault = (root: XmlElement): ParsedFault => {
  const header = child(root, 'cmmMsgHeader');
  if (!header) throw new ResponseShapeError('<cmmMsgHeader>가 없습니다');
  return {
    kind: 'fault',
    code: textOf(header, 'returnReasonCode'),
    errMsg: textOf(header, 'errMsg'),
    authMsg: textOf(header, 'returnAuthMsg'),
  };
};

/**
 * 명세 대비 실제 필드 차이를 계산한다. item이 없으면 비교할 근거가 없다.
 *
 * 여러 페이지에 걸친 응답은 **전 페이지의 item을 모아 한 번에** 넘겨야 한다.
 * 페이지별로 계산해 합치면, 어떤 필드가 1페이지 항목에는 없고 2페이지에만 있을 때
 * 실제로는 존재하는 필드가 "누락"으로 보고된다.
 */
export const fieldDiff = (
  key: DatasetKey,
  items: readonly RawItem[],
): { unknownFields: readonly string[]; missingFields: readonly string[] } => {
  if (items.length === 0) return { unknownFields: [], missingFields: [] };

  const expected = new Set<string>(DATASETS[key].fields);
  const seen = new Set<string>();
  for (const item of items) for (const name of Object.keys(item)) seen.add(name);

  return {
    unknownFields: [...seen].filter((n) => !expected.has(n)).sort(),
    missingFields: [...expected].filter((n) => !seen.has(n)).sort(),
  };
};

const parseData = (key: DatasetKey, root: XmlElement): ParsedResponse => {
  const header = child(root, 'header');
  const body = child(root, 'body');
  if (!header) throw new ResponseShapeError('<header>가 없습니다');
  if (!body) throw new ResponseShapeError('<body>가 없습니다');

  const itemsNode = child(body, 'items');
  const items = itemsNode ? children(itemsNode, 'item').map(toRawItem) : [];

  return {
    kind: 'data',
    resultCode: textOf(header, 'resultCode'),
    resultMsg: textOf(header, 'resultMsg'),
    totalCount: intOf(body, 'totalCount'),
    pageNo: intOf(body, 'pageNo'),
    numOfRows: intOf(body, 'numOfRows'),
    items,
    ...fieldDiff(key, items),
  };
};

/**
 * 응답 XML 한 건을 읽는다.
 *
 * 두 가지 봉투가 온다. 정상 경로는 `<response>`(HTTP 200)이고,
 * 인증·권한 오류는 `<OpenAPI_ServiceResponse>`(HTTP 4xx)로 **구조 자체가 다르다.**
 * 둘 다 실호출로 확인한 형태다(`test/fixtures/fault-*.xml`).
 */
export const parseResponse = (key: DatasetKey, xml: string): ParseResult => {
  const root = parseXml(xml);
  if (root.name === 'OpenAPI_ServiceResponse') return parseFault(root);
  if (root.name === 'response') return parseData(key, root);
  throw new ResponseShapeError(`알 수 없는 봉투: <${root.name}>`);
};

/** 응답이 스키마 변화를 드러냈는가. 참이면 수집을 멈추고 사람이 봐야 한다. */
export const hasSchemaDrift = (parsed: ParsedResponse): boolean =>
  parsed.unknownFields.length > 0 || parsed.missingFields.length > 0;
