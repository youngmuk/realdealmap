import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';

import { describe, expect, it } from 'vitest';

import { buildBundle, BundleError, bundleObjectKey, type BundleEntry } from './bundle.js';
import type { ChunkPayload } from './chunk.js';

/**
 * 묶음이 지켜야 하는 것.
 *
 * 앱은 **묶음 하나의 해시만 보고** 안에 든 청크 전부를 믿는다. 낱개로 받을 때
 * 청크마다 하던 검증을 한 번으로 줄인 것이라, 그 해시가 실제 바이트를 덮지
 * 못하면 검증이 통째로 사라진다. 그래서 "무엇을 해시했는가"를 센다.
 */

const payload = (period: string, datasetKey = 'apartment/sale', sggCd = '11215'): ChunkPayload =>
  ({
    sggCd,
    datasetKey,
    period,
    count: 1,
    records: [
      {
        id: `${sggCd}-${period}-1`,
        datasetKey,
        sggCd,
        umdNm: '중곡동',
        contractedOn: `${period.slice(0, 4)}-${period.slice(4)}-01`,
        cancelled: false,
        precision: 'exact',
      },
    ],
  }) as unknown as ChunkPayload;

const entry = (period: string, datasetKey?: string): BundleEntry => ({
  path: `v1/data/11215/${period}/${(datasetKey ?? 'apartment/sale').replace('/', '-')}.abc.json.gz`,
  body: payload(period, datasetKey),
});

describe('묶음 굽기', () => {
  it('압축을 풀면 정규 JSON이 그대로 나온다', () => {
    const bundle = buildBundle('11215', [entry('202601'), entry('202602')]);
    const json = gunzipSync(bundle.gzip);
    const parsed = JSON.parse(json.toString('utf8'));

    expect(parsed.schemaVersion).toBe(1);
    expect(parsed.sggCd).toBe('11215');
    expect(parsed.chunks).toHaveLength(2);
    expect(bundle.ref.chunks).toBe(2);
  });

  // 앱이 이 해시 하나로 안에 든 전부를 믿는다. 압축 전 바이트를 덮어야 한다 —
  // gzip 바이트는 zlib 판에 따라 달라져 같은 자료가 다른 값이 된다.
  it('해시는 압축 전 바이트를 덮는다', () => {
    const bundle = buildBundle('11215', [entry('202601')]);
    const raw = gunzipSync(bundle.gzip);

    expect(createHash('sha256').update(raw).digest('hex')).toBe(bundle.ref.sha256);
  });

  it('경로에 내용 해시가 박힌다', () => {
    const bundle = buildBundle('11215', [entry('202601')]);

    expect(bundle.ref.path).toBe(bundleObjectKey('11215', bundle.ref.sha256));
    expect(bundle.ref.path).toContain(bundle.ref.sha256.slice(0, 16));
  });

  // 같은 자료가 같은 경로를 내야 이미 올라간 것을 다시 올리지 않는다.
  it('넣은 순서가 달라도 같은 바이트가 나온다', () => {
    const a = buildBundle('11215', [entry('202601'), entry('202602')]);
    const b = buildBundle('11215', [entry('202602'), entry('202601')]);

    expect(b.ref.sha256).toBe(a.ref.sha256);
    expect(b.gzip.equals(a.gzip)).toBe(true);
  });

  it('바이트 수는 압축 후 크기다 — 앱이 받을 양이 그것이다', () => {
    const bundle = buildBundle('11215', [entry('202601')]);

    expect(bundle.ref.bytes).toBe(bundle.gzip.byteLength);
  });

  // 지역이 섞이면 남의 동네 거래가 이 지역 것으로 반영된다.
  it('다른 지역이 섞이면 던진다', () => {
    const alien: BundleEntry = {
      path: 'v1/data/26350/202601/x.abc.json.gz',
      body: payload('202601', 'apartment/sale', '26350'),
    };

    expect(() => buildBundle('11215', [entry('202601'), alien])).toThrow(BundleError);
  });

  // 같은 경로가 둘이면 앱이 어느 쪽을 반영할지가 순서에 달린다.
  it('경로가 겹치면 던진다', () => {
    expect(() => buildBundle('11215', [entry('202601'), entry('202601')])).toThrow(BundleError);
  });

  it('빈 묶음은 만들지 않는다', () => {
    expect(() => buildBundle('11215', [])).toThrow(BundleError);
  });
});
