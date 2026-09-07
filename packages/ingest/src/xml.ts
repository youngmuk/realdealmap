/**
 * 국토부 실거래가 응답 전용의 최소 XML 리더.
 *
 * 범용 파서가 아니다. 원천 응답은 속성이 없고 네임스페이스도 쓰지 않는
 * 얕은 트리라서, 의존성을 하나 더 들이는 대신 필요한 만큼만 직접 읽는다.
 * 지원: 프롤로그 · 주석 · 자기닫기 태그 · 기본 엔티티 · CDATA.
 */

export interface XmlElement {
  readonly name: string;
  /** 자식이 없는 원소의 텍스트. 자식이 있으면 빈 문자열이다. */
  readonly text: string;
  readonly children: readonly XmlElement[];
}

export class XmlParseError extends Error {
  constructor(message: string, readonly offset: number) {
    super(`${message} (offset ${offset})`);
    this.name = 'XmlParseError';
  }
}

const ENTITIES: Readonly<Record<string, string>> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
};

/** 기본 엔티티와 수치 참조를 되돌린다. 알 수 없는 참조는 원문 그대로 둔다. */
export const decodeEntities = (raw: string): string =>
  raw.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (whole, body: string) => {
    if (body.startsWith('#')) {
      const hex = body[1] === 'x' || body[1] === 'X';
      const code = Number.parseInt(hex ? body.slice(2) : body.slice(1), hex ? 16 : 10);
      return Number.isFinite(code) && code > 0 ? String.fromCodePoint(code) : whole;
    }
    return ENTITIES[body] ?? whole;
  });

/** `<?...?>`와 `<!--...-->`를 건너뛴 다음 위치를 돌려준다. */
const skipNonElement = (xml: string, from: number): number => {
  let i = from;
  for (;;) {
    const next = xml.indexOf('<', i);
    if (next === -1) return xml.length;
    if (xml.startsWith('<?', next)) {
      const end = xml.indexOf('?>', next);
      if (end === -1) throw new XmlParseError('닫히지 않은 프롤로그', next);
      i = end + 2;
    } else if (xml.startsWith('<!--', next)) {
      const end = xml.indexOf('-->', next);
      if (end === -1) throw new XmlParseError('닫히지 않은 주석', next);
      i = end + 3;
    } else {
      return next;
    }
  }
};

interface Frame {
  readonly name: string;
  readonly children: XmlElement[];
  text: string;
}

const closeFrame = (frame: Frame): XmlElement => ({
  name: frame.name,
  // 자식이 있으면 원소 사이의 공백은 의미가 없으므로 버린다.
  text: frame.children.length > 0 ? '' : decodeEntities(frame.text),
  children: frame.children,
});

/**
 * 루트 원소 하나를 읽는다. 루트가 없거나 태그가 어긋나면 {@link XmlParseError}.
 */
export const parseXml = (xml: string): XmlElement => {
  let i = skipNonElement(xml, 0);
  if (i >= xml.length) throw new XmlParseError('루트 원소가 없습니다', 0);

  const stack: Frame[] = [];
  let root: XmlElement | undefined;

  while (i < xml.length) {
    if (xml[i] !== '<') {
      const next = xml.indexOf('<', i);
      const stop = next === -1 ? xml.length : next;
      const top = stack[stack.length - 1];
      if (top) top.text += xml.slice(i, stop);
      i = stop;
      continue;
    }

    if (xml.startsWith('<?', i) || xml.startsWith('<!--', i)) {
      i = skipNonElement(xml, i);
      continue;
    }
    if (xml.startsWith('<![CDATA[', i)) {
      const end = xml.indexOf(']]>', i);
      if (end === -1) throw new XmlParseError('닫히지 않은 CDATA', i);
      const top = stack[stack.length - 1];
      // CDATA 안은 엔티티를 해석하지 않으므로 미리 이스케이프해 둔다.
      if (top) top.text += xml.slice(i + 9, end).replace(/&/g, '&amp;');
      i = end + 3;
      continue;
    }

    const end = xml.indexOf('>', i);
    if (end === -1) throw new XmlParseError('닫히지 않은 태그', i);
    const inner = xml.slice(i + 1, end);
    i = end + 1;

    if (inner.startsWith('/')) {
      const frame = stack.pop();
      if (!frame) throw new XmlParseError(`짝 없는 닫는 태그 </${inner.slice(1)}>`, end);
      const name = inner.slice(1).trim();
      if (name !== frame.name) {
        throw new XmlParseError(`태그 불일치: <${frame.name}> vs </${name}>`, end);
      }
      const element = closeFrame(frame);
      const parent = stack[stack.length - 1];
      if (parent) parent.children.push(element);
      else root = element;
      continue;
    }

    const selfClosing = inner.endsWith('/');
    const name = (selfClosing ? inner.slice(0, -1) : inner).trim().split(/\s/)[0] ?? '';
    if (name === '') throw new XmlParseError('이름 없는 태그', end);

    if (selfClosing) {
      const element: XmlElement = { name, text: '', children: [] };
      const parent = stack[stack.length - 1];
      if (parent) parent.children.push(element);
      else root = element;
      continue;
    }
    stack.push({ name, children: [], text: '' });
  }

  if (stack.length > 0) {
    throw new XmlParseError(`닫히지 않은 <${stack[stack.length - 1]?.name}>`, xml.length);
  }
  if (!root) throw new XmlParseError('루트 원소가 없습니다', 0);
  return root;
};

/** 직계 자식 중 이름이 같은 첫 원소. */
export const child = (element: XmlElement, name: string): XmlElement | undefined =>
  element.children.find((c) => c.name === name);

/** 직계 자식 중 이름이 같은 모든 원소. */
export const children = (element: XmlElement, name: string): readonly XmlElement[] =>
  element.children.filter((c) => c.name === name);

/**
 * 직계 자식의 텍스트를 trim해서 돌려준다.
 *
 * 원천은 빈 값을 빈 문자열이 아니라 **공백 한 칸**으로 준다
 * (`<preDeposit> </preDeposit>`). trim하지 않으면 "값이 있다"로 오인한다.
 */
export const textOf = (element: XmlElement, name: string): string =>
  child(element, name)?.text.trim() ?? '';
