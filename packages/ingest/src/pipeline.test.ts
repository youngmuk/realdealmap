import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

import { describe, expect, test } from 'vitest';

import { buildChunk, chunkObjectKey } from './chunk.js';
import { datasetKeys } from './datasets.js';
import { diffSnapshots } from './identity.js';
import { normalizeAll, type Transaction } from './normalize.js';
import { hasSchemaDrift, parseResponse } from './parse.js';

/**
 * 수집 파이프라인 통합 테스트.
 *
 * 개별 단계는 각자의 테스트가 있다. 여기서는 실응답 → 청크까지 **이어 붙였을 때**
 * 데이터가 새지 않는지를 본다. 단계 사이의 계약이 어긋나는 것을 잡는 자리다.
 */

const FIXTURE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../test/fixtures');

/** 원천 XML 한 건을 청크까지 통과시킨다. 실제 수집기가 하는 일과 같은 순서다. */
const run = (key: string, period = '202608') => {
  const name = key.replace('/', '-');
  const xml = readFileSync(resolve(FIXTURE_DIR, name + '.xml'), 'utf8');

  const parsed = parseResponse(key as never, xml);
  if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');

  const normalized = normalizeAll(key as never, parsed.items);
  const chunk = buildChunk('11110', key as never, period, normalized.transactions);
  return { parsed, normalized, chunk };
};

describe('원천에서 청크까지', () => {
  test.each(datasetKeys())('%s가 한 건도 잃지 않고 통과한다', (key) => {
    const { parsed, normalized, chunk } = run(key);

    expect(hasSchemaDrift(parsed), '스키마 변화').toBe(false);
    expect(normalized.failures, '정규화 실패').toEqual([]);
    // 파싱된 건수 = 정규화된 건수 = 청크 레코드 수. 어디서도 새지 않는다.
    expect(normalized.transactions).toHaveLength(parsed.items.length);
    expect(chunk.payload.records).toHaveLength(parsed.items.length);
    expect(chunk.payload.count).toBe(parsed.items.length);
  });

  test('압축을 풀면 원천 값이 그대로 나온다', () => {
    const { parsed, chunk } = run('apartment/sale');
    const payload = JSON.parse(gunzipSync(chunk.bytes).toString('utf8')) as {
      records: { raw: Record<string, string> }[];
    };

    const sourceNames = parsed.items.map((i) => i['aptNm']).sort();
    const chunkNames = payload.records.map((r) => r.raw['aptNm']).sort();
    expect(chunkNames).toEqual(sourceNames);
  });

  test('상세화면이 쓸 원문이 끝까지 살아 있다 (FR-3)', () => {
    // 토지의 지목·용도지역은 정규화 모델에 자리가 없지만 raw로 전달된다.
    const { chunk } = run('land/sale');
    for (const record of chunk.payload.records) {
      expect(record.raw['jimok']).toBeDefined();
      expect(record.raw['landUse']).toBeDefined();
      expect(record.raw['shareDealingType']).toBeDefined();
    }
  });

  test('9종을 모두 처리해도 오브젝트 키가 겹치지 않는다', () => {
    const keys = datasetKeys().map((k) => chunkObjectKey(run(k).chunk));
    expect(new Set(keys).size).toBe(9);
  });
});

describe('재수집 시나리오', () => {
  const baseline = (): readonly Transaction[] => run('apartment/sale').normalized.transactions;

  test('같은 데이터를 다시 수집하면 변화가 없고 경로도 그대로다', () => {
    const before = baseline();
    const after = baseline();

    const diff = diffSnapshots(before, after);
    expect(diff.unchangedCount).toBe(before.length);
    expect([diff.added, diff.changed, diff.removed]).toEqual([[], [], []]);

    // 변화가 없으면 R2에 새 객체를 올릴 이유가 없다.
    const a = buildChunk('11110', 'apartment/sale', '202608', before);
    const b = buildChunk('11110', 'apartment/sale', '202608', after);
    expect(chunkObjectKey(b)).toBe(chunkObjectKey(a));
  });

  test('가격 정정은 변경으로 잡히고 경로가 바뀐다', () => {
    const before = baseline();
    const [head, ...rest] = before;
    if (!head) throw new Error('픽스처가 비었다');
    const after = [{ ...head, amount: (head.amount ?? 0) + 3000 }, ...rest];

    const diff = diffSnapshots(before, after);
    expect(diff.changed).toHaveLength(1);
    expect(diff.added).toEqual([]);
    expect(diff.removed).toEqual([]);

    const a = buildChunk('11110', 'apartment/sale', '202608', before);
    const b = buildChunk('11110', 'apartment/sale', '202608', after);
    expect(chunkObjectKey(b)).not.toBe(chunkObjectKey(a));
  });

  test('전량 소실이 removed로 드러난다 — 배포 게이트의 입력', () => {
    // R-14: 원천이 조용히 0건을 주면 여기서만 알아챌 수 있다.
    const before = baseline();
    const diff = diffSnapshots(before, []);
    expect(diff.removed).toHaveLength(before.length);
    expect(diff.added).toEqual([]);
  });

  test('해제 전환이 삭제로 오인되지 않는다', () => {
    const before = baseline();
    const [head, ...rest] = before;
    if (!head) throw new Error('픽스처가 비었다');
    const after = [{ ...head, cancelled: true, cancelledOn: '2026-09-01' }, ...rest];

    const diff = diffSnapshots(before, after);
    expect(diff.cancelled).toHaveLength(1);
    expect(diff.removed).toEqual([]);
    // 청크에도 삭제가 아니라 상태로 남는다.
    const chunk = buildChunk('11110', 'apartment/sale', '202608', after);
    expect(chunk.payload.count).toBe(before.length);
    expect(chunk.payload.records.filter((r) => r.cancelled)).toHaveLength(1);
  });
});
