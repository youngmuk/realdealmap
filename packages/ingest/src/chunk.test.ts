import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

import { describe, expect, test } from 'vitest';

import {
  buildChunk,
  ChunkError,
  chunkObjectKey,
  isDeterministic,
  KEY_PREFIX,
  regionPrefix,
} from './chunk.js';
import { normalizeAll, type Transaction } from './normalize.js';
import { parseResponse } from './parse.js';

const FIXTURE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../test/fixtures');

const load = (key: string): readonly Transaction[] => {
  const name = key.replace('/', '-');
  const parsed = parseResponse(key as never, readFileSync(resolve(FIXTURE_DIR, name + '.xml'), 'utf8'));
  if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
  return normalizeAll(key as never, parsed.items).transactions;
};

const apt = load('apartment/sale');
const build = (txs: readonly Transaction[] = apt) =>
  buildChunk('11110', 'apartment/sale', '202608', txs);

describe('결정적 출력', () => {
  test('같은 입력을 두 번 처리하면 바이트가 같다', () => {
    expect(build().bytes.equals(build().bytes)).toBe(true);
    expect(build().sha256).toBe(build().sha256);
  });

  test('입력 순서가 달라도 같은 해시가 나온다', () => {
    expect(isDeterministic(apt, [...apt].reverse())).toBe(true);
  });

  test('gzip 헤더가 플랫폼에 무관하게 고정된다', () => {
    const header = build().bytes;
    // MTIME이 들어가면 실행 시각마다, OS 바이트가 들어가면 빌드 플랫폼마다 달라진다.
    expect([...header.subarray(4, 8)]).toEqual([0, 0, 0, 0]);
    expect(header[9]).toBe(255);
  });

  test('해시는 압축 결과가 아니라 내용을 대상으로 한다', () => {
    // 압축 구현이 바뀌어도 같은 데이터면 같은 경로여야 한다.
    const chunk = build();
    const json = gunzipSync(chunk.bytes);
    expect(createHash('sha256').update(json).digest('hex')).toBe(chunk.sha256);
  });

  test('내용이 바뀌면 해시가 바뀐다', () => {
    const changed = apt.map((t, i) => (i === 0 ? { ...t, amount: 1 } : t));
    expect(build(changed).sha256).not.toBe(build().sha256);
  });

  test('키 순서가 달라도 같은 해시가 나온다', () => {
    // raw 객체의 키 삽입 순서가 뒤집혀도 정규 JSON이 흡수한다.
    const reordered = apt.map((t) => ({
      ...t,
      raw: Object.fromEntries(Object.entries(t.raw).reverse()),
    }));
    expect(build(reordered).sha256).toBe(build().sha256);
  });
});

describe('청크 내용', () => {
  test('gzip을 풀면 정규 JSON이 나온다', () => {
    const chunk = build();
    const payload = JSON.parse(gunzipSync(chunk.bytes).toString('utf8')) as Record<string, unknown>;
    expect(payload['sggCd']).toBe('11110');
    expect(payload['datasetKey']).toBe('apartment/sale');
    expect(payload['period']).toBe('202608');
    expect(payload['count']).toBe(apt.length);
  });

  test('count와 실제 레코드 수가 일치한다', () => {
    const chunk = build();
    expect(chunk.payload.count).toBe(chunk.payload.records.length);
  });

  test('레코드마다 고유 id가 있다', () => {
    const ids = build().payload.records.map((r) => r.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  test('상세화면용 원문이 보존된다 (FR-3)', () => {
    const [record] = build().payload.records;
    expect(record?.raw['aptNm']).toBeDefined();
    expect(record?.raw['bonbun']).toBeDefined();
  });

  test('좌표 정밀도가 레코드에 실린다', () => {
    expect(build().payload.records.every((r) => r.precision === 'exact')).toBe(true);
    const land = buildChunk('11110', 'land/sale', '202608', load('land/sale'));
    expect(land.payload.records.some((r) => r.precision === 'partial')).toBe(true);
  });

  test('압축이 실제로 효과가 있다', () => {
    const chunk = build();
    expect(chunk.bytes.byteLength).toBeLessThan(chunk.rawSize);
  });

  test('빈 청크도 만들 수 있다', () => {
    const empty = build([]);
    expect(empty.payload.count).toBe(0);
    expect(empty.sha256).toHaveLength(64);
  });
});

describe('입력 검증', () => {
  test.each(['2026-08', '20268', '', 'abcdef', '202600', '202613'])('연월 %s는 거부한다', (period) => {
    expect(() => buildChunk('11110', 'apartment/sale', period, apt)).toThrow(ChunkError);
  });

  // 이 값들이 통과하면 그대로 R2 오브젝트 키가 된다. `..`는 경로를 거슬러 올라가고,
  // 나머지는 예상 밖 접두사를 만들어 지역 단위 나열·정리를 조용히 어긋나게 한다.
  test.each(['1111', '111100', '', '1111a', '../11110', '11/10', '11 10'])(
    '시군구 코드 %s는 거부한다',
    (sggCd) => {
      expect(() => buildChunk(sggCd, 'apartment/sale', '202608', [])).toThrow(ChunkError);
    },
  );

  test('거부된 코드는 오브젝트 키까지 가지 못한다', () => {
    expect(() => buildChunk('../etc', 'apartment/sale', '202608', [])).toThrow(
      /시군구 코드 형식이 아님/,
    );
  });

  test('다른 유형이 섞이면 거부한다', () => {
    const mixed = [...apt, ...load('land/sale')];
    expect(() => build(mixed)).toThrow(ChunkError);
  });
});

describe('오브젝트 키', () => {
  test('콘텐츠 해시가 경로에 박힌다', () => {
    const chunk = build();
    const key = chunkObjectKey(chunk);
    expect(key).toBe(
      `${KEY_PREFIX}/11110/202608/apartment-sale.${chunk.sha256.slice(0, 16)}.json.gz`,
    );
  });

  test('내용이 바뀌면 경로가 바뀐다 — 캐시 무효화가 필요 없다', () => {
    const changed = apt.map((t, i) => (i === 0 ? { ...t, amount: 1 } : t));
    expect(chunkObjectKey(build(changed))).not.toBe(chunkObjectKey(build()));
  });

  test('유형의 슬래시가 경로를 쪼개지 않는다', () => {
    const chunk = buildChunk('11110', 'apartment/rent', '202608', load('apartment/rent'));
    expect(chunkObjectKey(chunk)).toContain('apartment-rent.');
    expect(chunkObjectKey(chunk).split('/')).toHaveLength(5);
  });

  test('스키마 버전이 앞에 온다 — 구조가 바뀌면 구·신이 공존한다', () => {
    expect(chunkObjectKey(build()).startsWith('v1/')).toBe(true);
  });

  test('한 지역의 청크는 시군구 접두사 하나로 전부 잡힌다', () => {
    const keys = (['apartment/sale', 'apartment/rent', 'land/sale'] as const).map((k) =>
      chunkObjectKey(buildChunk('11110', k, '202608', load(k))),
    );
    expect(keys.every((k) => k.startsWith(regionPrefix('11110')))).toBe(true);
    expect(keys.some((k) => k.startsWith(regionPrefix('11680')))).toBe(false);
  });
});
