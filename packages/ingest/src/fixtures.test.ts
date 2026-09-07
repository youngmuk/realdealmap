import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import { DATASETS, datasetKeys } from './datasets.js';

/**
 * T1.1 골든 픽스처 대조.
 *
 * `datasets.ts`는 원래 Swagger 모델에서 만들었는데, 실호출 결과 4종이 달랐다.
 * 명세가 실응답과 어긋나면 파서가 필드를 조용히 흘리므로 여기서 잠근다.
 * 픽스처 갱신: `node packages/ingest/scripts/probe-api.mjs all`
 */
const FIXTURE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../test/fixtures');

/** 응답 봉투(envelope) 태그. item 내부 항목이 아니므로 비교에서 제외한다. */
const ENVELOPE = new Set([
  'response', 'header', 'body', 'items', 'item',
  'resultCode', 'resultMsg', 'numOfRows', 'pageNo', 'totalCount',
]);

const fixturePath = (key: string): string =>
  resolve(FIXTURE_DIR, `${key.replace('/', '-')}.xml`);

/** 첫 `<item>`에 등장하는 항목명을 순서 없이 수집한다. */
const fieldsInFixture = (xml: string): readonly string[] => {
  const item = /<item>([\s\S]*?)<\/item>/.exec(xml);
  if (!item?.[1]) throw new Error('픽스처에 <item>이 없습니다.');
  return [...item[1].matchAll(/<([a-zA-Z][a-zA-Z0-9]*)>/g)]
    .map((m) => m[1] as string)
    .filter((name) => !ENVELOPE.has(name));
};

const available = datasetKeys().filter((key) => existsSync(fixturePath(key)));

/**
 * 픽스처 확보 검사는 **`skipIf` 바깥에 둔다.**
 *
 * 안에 두면 픽스처를 전부 지웠을 때 `skipIf`가 이 검사까지 건너뛰어 조용히 통과한다.
 * 하나만 지우면 잡히는데 전부 지우면 통과하는, 게이트처럼 보이기만 하는 게이트가 된다.
 * 픽스처는 git이 추적하므로 "없을 수도 있다"는 전제 자체가 틀렸다 —
 * 없으면 그것이 곧 결함이다(G1 조건).
 */
test('9종 픽스처가 모두 확보되어 있다 (G1)', () => {
  expect(available).toHaveLength(9);
});

describe.skipIf(available.length === 0)('실응답 픽스처 대조', () => {
  test.each(available)('%s 명세가 실응답 필드와 정확히 일치한다', (key) => {
    const actual = fieldsInFixture(readFileSync(fixturePath(key), 'utf8'));
    expect([...actual].sort()).toEqual([...DATASETS[key].fields].sort());
  });

  test('마스킹 등급이 실제 지번 값과 일치한다', () => {
    // partial은 "2**"처럼 별표가 섞이고, exact/jibun은 별표가 없어야 한다.
    for (const key of available) {
      const spec = DATASETS[key];
      if (spec.geocode === 'umd') continue;

      const xml = readFileSync(fixturePath(key), 'utf8');
      const values = [...xml.matchAll(/<jibun>([^<]*)<\/jibun>/g)].map((m) => m[1] ?? '');
      expect(values.length, `${key}에 지번 값이 없다`).toBeGreaterThan(0);

      const masked = values.some((v) => v.includes('*'));
      expect(masked, `${key}의 마스킹 여부`).toBe(spec.geocode === 'partial');
    }
  });
});
