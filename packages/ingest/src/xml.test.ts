import { describe, expect, test } from 'vitest';

import { child, children, decodeEntities, parseXml, textOf, XmlParseError } from './xml.js';

describe('XML 리더', () => {
  test('프롤로그를 건너뛰고 루트를 읽는다', () => {
    const root = parseXml('<?xml version="1.0" encoding="utf-8"?><response><a>1</a></response>');
    expect(root.name).toBe('response');
    expect(textOf(root, 'a')).toBe('1');
  });

  test('중첩된 원소를 트리로 만든다', () => {
    const root = parseXml('<r><body><items><item><x>1</x></item><item><x>2</x></item></items></body></r>');
    const items = children(child(child(root, 'body')!, 'items')!, 'item');
    expect(items.map((i) => textOf(i, 'x'))).toEqual(['1', '2']);
  });

  test('원소 사이 공백은 텍스트로 취급하지 않는다', () => {
    // 오류 봉투가 실제로 이 형태다: <OpenAPI_ServiceResponse> <cmmMsgHeader> ...
    const root = parseXml('<a> <b>v</b> </a>');
    expect(root.text).toBe('');
    expect(textOf(root, 'b')).toBe('v');
  });

  test('빈 값이 공백 한 칸으로 와도 textOf가 빈 문자열로 만든다', () => {
    // 원천은 <preDeposit> </preDeposit>처럼 준다. trim하지 않으면 값이 있는 것으로 오인한다.
    const root = parseXml('<item><preDeposit> </preDeposit></item>');
    expect(textOf(root, 'preDeposit')).toBe('');
  });

  test('자기닫기 태그를 빈 원소로 읽는다', () => {
    const root = parseXml('<item><jibun/><x>1</x></item>');
    expect(textOf(root, 'jibun')).toBe('');
    expect(textOf(root, 'x')).toBe('1');
  });

  test('주석을 건너뛴다', () => {
    expect(textOf(parseXml('<a><!-- 주석 --><b>1</b></a>'), 'b')).toBe('1');
  });

  test('CDATA 안의 마크업을 텍스트로 보존한다', () => {
    expect(textOf(parseXml('<a><b><![CDATA[<x>&y]]></b></a>'), 'b')).toBe('<x>&y');
  });

  test('없는 자식은 빈 문자열이다', () => {
    expect(textOf(parseXml('<a><b>1</b></a>'), 'zzz')).toBe('');
    expect(child(parseXml('<a/>'), 'zzz')).toBeUndefined();
  });
});

describe('엔티티 해석', () => {
  test.each([
    ['&amp;', '&'],
    ['&lt;&gt;', '<>'],
    ['&quot;&apos;', '"\''],
    ['&#65;', 'A'],
    ['&#x41;', 'A'],
  ])('%s → %s', (input, expected) => {
    expect(decodeEntities(input)).toBe(expected);
  });

  test('알 수 없는 참조는 원문을 유지한다', () => {
    expect(decodeEntities('&nosuch;')).toBe('&nosuch;');
    expect(decodeEntities('&#0;')).toBe('&#0;');
  });

  test('단지명에 섞인 앰퍼샌드를 되돌린다', () => {
    // 아파트 단지명에 실제로 &가 들어간다.
    expect(textOf(parseXml('<i><aptNm>A&amp;B타워</aptNm></i>'), 'aptNm')).toBe('A&B타워');
  });
});

describe('깨진 XML', () => {
  test.each([
    ['닫히지 않은 태그', '<a><b>1</b>'],
    ['태그 불일치', '<a><b>1</c></a>'],
    ['짝 없는 닫는 태그', '<a></a></b>'],
    ['루트 없음', '   '],
    ['닫히지 않은 주석', '<a><!-- x</a>'],
    ['닫히지 않은 CDATA', '<a><![CDATA[x</a>'],
    ['닫히지 않은 프롤로그', '<?xml version="1.0"'],
    ['이름 없는 태그', '<a>< >1</a>'],
  ])('%s은 XmlParseError다', (_label, xml) => {
    expect(() => parseXml(xml)).toThrow(XmlParseError);
  });

  test('오류에 위치가 담긴다', () => {
    try {
      parseXml('<a><b>1</c></a>');
      expect.unreachable('던져야 한다');
    } catch (error) {
      expect(error).toBeInstanceOf(XmlParseError);
      expect((error as XmlParseError).offset).toBeGreaterThan(0);
      expect((error as XmlParseError).message).toContain('offset');
    }
  });
});
