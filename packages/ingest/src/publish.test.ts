import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { DatasetKey } from '@realdealmap/shared';
import { describe, expect, test } from 'vitest';

import { buildChunk, chunkObjectKey, type Chunk } from './chunk.js';
import { normalizeAll, type Transaction } from './normalize.js';
import { parseResponse } from './parse.js';
import {
  checkRecordDrop,
  findObsoleteChunks,
  manifestKey,
  publishRegion,
  PublishError,
  readManifest,
  SCHEMA_VERSION,
  type Manifest,
} from './publish.js';
import type { R2Client } from './r2.js';

const FIXTURE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../test/fixtures');

const load = (key: string): readonly Transaction[] => {
  const name = key.replace('/', '-');
  const parsed = parseResponse(key as never, readFileSync(resolve(FIXTURE_DIR, name + '.xml'), 'utf8'));
  if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
  return normalizeAll(key as never, parsed.items).transactions;
};

const chunkFor = (key: DatasetKey, sggCd = '11680', period = '202608'): Chunk =>
  buildChunk(sggCd, key, period, load(key));

/** R2를 흉내내는 메모리 저장소. 실패를 원하는 키에 주입할 수 있다. */
const fakeR2 = (options: { failOn?: string; existing?: Set<string> } = {}) => {
  const store = new Map<string, Uint8Array>();
  const puts: string[] = [];
  const existing = options.existing ?? new Set<string>();

  const client = {
    bucket: 'test',
    put: async (key: string, body: Uint8Array) => {
      if (options.failOn && key.includes(options.failOn)) {
        throw new Error(`주입된 실패: ${key}`);
      }
      puts.push(key);
      store.set(key, body);
    },
    get: async (key: string) => store.get(key) ?? null,
    exists: async (key: string) => existing.has(key) || store.has(key),
    delete: async (key: string) => void store.delete(key),
    list: async (prefix: string) => ({
      keys: [...new Set([...store.keys(), ...existing])].filter((k) => k.startsWith(prefix)).sort(),
      nextToken: undefined,
    }),
  } as unknown as R2Client;

  return { client, store, puts, existing };
};

const seedManifest = (store: Map<string, Uint8Array>, sggCd: string, records: number): void => {
  const manifest: Manifest = {
    schemaVersion: SCHEMA_VERSION,
    sggCd,
    refreshedAt: '2026-09-01T00:00:00.000Z',
    ttlSeconds: 3600,
    files: [
      {
        propertyType: 'apartment',
        tradeType: 'sale',
        month: '202608',
        path: 'v1/data/11680/202608/apartment-sale.oldhash00000000.json.gz',
        sha256: 'old',
        bytes: 1,
        records,
      },
    ],
  };
  store.set(manifestKey(sggCd), new TextEncoder().encode(JSON.stringify(manifest)));
};

describe('오브젝트 키', () => {
  test('시군구가 유형보다 앞에 온다 — 지역 단위로 나열할 수 있어야 한다', () => {
    const key = chunkObjectKey(chunkFor('apartment/sale'));
    expect(key).toMatch(/^v1\/data\/11680\/202608\/apartment-sale\.[0-9a-f]{16}\.json\.gz$/);
    expect(key.startsWith('v1/data/11680/')).toBe(true);
  });

  test('매니페스트 경로가 계약과 같다', () => {
    expect(manifestKey('11680')).toBe('v1/regions/11680/manifest.json');
  });
});

describe('매니페스트 작성', () => {
  test('계약대로 된 매니페스트를 만든다', async () => {
    const { client, store } = fakeR2();
    const chunks = [chunkFor('apartment/sale'), chunkFor('land/sale')];
    const result = await publishRegion(client, '11680', chunks, {
      now: () => new Date('2026-09-07T05:00:00.000Z'),
    });

    expect(result.manifestReplaced).toBe(true);
    const written = JSON.parse(
      new TextDecoder().decode(store.get(manifestKey('11680')) ?? new Uint8Array()),
    ) as Manifest;

    expect(written.schemaVersion).toBe(1);
    expect(written.sggCd).toBe('11680');
    expect(written.refreshedAt).toBe('2026-09-07T05:00:00.000Z');
    expect(written.ttlSeconds).toBe(3600);
    expect(written.files).toHaveLength(2);

    const [file] = written.files;
    expect(file).toMatchObject({ month: '202608' });
    expect(typeof file?.records).toBe('number');
    expect(typeof file?.bytes).toBe('number');
    expect(file?.sha256).toMatch(/^[0-9a-f]{64}$/);
  });

  test('유형과 거래를 나눠 담는다', async () => {
    const { client, store } = fakeR2();
    await publishRegion(client, '11680', [chunkFor('apartment/rent')], {});
    const written = JSON.parse(
      new TextDecoder().decode(store.get(manifestKey('11680')) ?? new Uint8Array()),
    ) as Manifest;
    expect(written.files[0]).toMatchObject({ propertyType: 'apartment', tradeType: 'rent' });
  });

  test('파일 순서가 결정적이다', async () => {
    const chunks = [chunkFor('land/sale'), chunkFor('apartment/sale'), chunkFor('officetel/sale')];
    const a = await publishRegion(fakeR2().client, '11680', chunks, {});
    const b = await publishRegion(fakeR2().client, '11680', [...chunks].reverse(), {});
    expect(b.manifest.files.map((f) => f.path)).toEqual(a.manifest.files.map((f) => f.path));
  });

  test('다른 지역의 청크가 섞이면 거부한다', async () => {
    const mixed = [chunkFor('apartment/sale', '11680'), chunkFor('land/sale', '11110')];
    await expect(publishRegion(fakeR2().client, '11680', mixed, {})).rejects.toThrow(PublishError);
  });

  test('깨진 기존 매니페스트를 조용히 넘기지 않는다', async () => {
    const { client, store } = fakeR2();
    store.set(manifestKey('11680'), new TextEncoder().encode('{not json'));
    await expect(readManifest(client, '11680')).rejects.toThrow(PublishError);
  });

  test('첫 배포는 기존 매니페스트가 없다', async () => {
    expect(await readManifest(fakeR2().client, '11680')).toBeUndefined();
  });
});

describe('전량 성공 후에만 교체', () => {
  test('청크를 모두 올린 뒤 매니페스트를 마지막에 쓴다', async () => {
    const { client, puts } = fakeR2();
    const chunks = [chunkFor('apartment/sale'), chunkFor('land/sale')];
    await publishRegion(client, '11680', chunks, {});

    expect(puts).toHaveLength(3);
    expect(puts[puts.length - 1]).toBe(manifestKey('11680'));
    expect(puts.slice(0, 2).every((k) => k.startsWith('v1/data/'))).toBe(true);
  });

  test('청크 하나가 실패하면 매니페스트를 바꾸지 않는다', async () => {
    // 매니페스트가 없는 청크를 가리키면 앱은 빈 화면을 보고 다음 갱신까지 그대로다.
    const { client, store } = fakeR2({ failOn: 'land-sale' });
    const chunks = [chunkFor('apartment/sale'), chunkFor('land/sale')];

    await expect(publishRegion(client, '11680', chunks, {})).rejects.toThrow(/주입된 실패/);
    expect(store.has(manifestKey('11680'))).toBe(false);
  });

  test('실패해도 이전 매니페스트는 그대로 남는다', async () => {
    const { client, store } = fakeR2({ failOn: 'apartment-sale' });
    seedManifest(store, '11680', 100);
    const before = store.get(manifestKey('11680'));

    await expect(publishRegion(client, '11680', [chunkFor('apartment/sale')], { minRecordRatio: 0 }))
      .rejects.toThrow();
    expect(store.get(manifestKey('11680'))).toBe(before);
  });
});

describe('중복 업로드 회피', () => {
  test('이미 같은 해시로 있으면 올리지 않는다', async () => {
    const chunk = chunkFor('apartment/sale');
    const { client, puts } = fakeR2({ existing: new Set([chunkObjectKey(chunk)]) });

    const result = await publishRegion(client, '11680', [chunk], {});
    expect(result.skipped).toEqual([chunkObjectKey(chunk)]);
    expect(result.uploaded).toEqual([]);
    // 매니페스트만 쓴다.
    expect(puts).toEqual([manifestKey('11680')]);
  });

  test('건너뛴 청크도 매니페스트에는 들어간다', async () => {
    const chunk = chunkFor('apartment/sale');
    const { client } = fakeR2({ existing: new Set([chunkObjectKey(chunk)]) });
    const result = await publishRegion(client, '11680', [chunk], {});
    expect(result.manifest.files).toHaveLength(1);
    expect(result.manifestReplaced).toBe(true);
  });
});

describe('건수 급락 게이트 (R-14)', () => {
  test('첫 배포는 비교 대상이 없어 통과한다', () => {
    expect(checkRecordDrop(undefined, 0, 0.5)).toBeUndefined();
  });

  test('이전이 0건이면 비교하지 않는다', () => {
    const empty = { files: [] } as unknown as Manifest;
    expect(checkRecordDrop(empty, 0, 0.5)).toBeUndefined();
  });

  test('절반 이상이면 통과한다', () => {
    const prev = { files: [{ records: 100 }] } as unknown as Manifest;
    expect(checkRecordDrop(prev, 60, 0.5)).toBeUndefined();
    expect(checkRecordDrop(prev, 50, 0.5)).toBeUndefined();
  });

  test('급락하면 보류 사유를 돌려준다', () => {
    const prev = { files: [{ records: 100 }] } as unknown as Manifest;
    expect(checkRecordDrop(prev, 10, 0.5)).toEqual({
      kind: 'recordDrop',
      before: 100,
      after: 10,
      ratio: 0.1,
    });
  });

  test('비율 0이면 게이트를 끈다', () => {
    const prev = { files: [{ records: 100 }] } as unknown as Manifest;
    expect(checkRecordDrop(prev, 0, 0)).toBeUndefined();
  });

  test('전량 소실이면 매니페스트를 바꾸지 않고 청크도 올리지 않는다', async () => {
    // 원천이 조용히 0건을 준 경우. 배포하면 앱이 빈 지도를 본다.
    const { client, store, puts } = fakeR2();
    seedManifest(store, '11680', 2139);
    const before = store.get(manifestKey('11680'));

    const result = await publishRegion(client, '11680', [], {});

    expect(result.hold).toMatchObject({ kind: 'recordDrop', after: 0 });
    expect(result.manifestReplaced).toBe(false);
    expect(puts).toEqual([]);
    expect(store.get(manifestKey('11680'))).toBe(before);
  });

  test('정상 갱신은 게이트를 통과한다', async () => {
    const { client, store } = fakeR2();
    const chunk = chunkFor('apartment/sale');
    seedManifest(store, '11680', chunk.payload.count);

    const result = await publishRegion(client, '11680', [chunk], {});
    expect(result.hold).toBeUndefined();
    expect(result.manifestReplaced).toBe(true);
  });
});

describe('업로드 상한', () => {
  test('상한을 넘으면 아무것도 올리지 않고 보류한다', async () => {
    const { client, puts } = fakeR2();
    const chunks = [chunkFor('apartment/sale'), chunkFor('land/sale'), chunkFor('officetel/sale')];

    const result = await publishRegion(client, '11680', chunks, { maxUploads: 2 });
    expect(result.hold).toEqual({ kind: 'uploadCap', needed: 3, cap: 2 });
    expect(result.manifestReplaced).toBe(false);
    expect(puts).toEqual([]);
  });

  test('상한 이내면 정상 배포한다', async () => {
    const { client } = fakeR2();
    const result = await publishRegion(client, '11680', [chunkFor('land/sale')], { maxUploads: 2 });
    expect(result.hold).toBeUndefined();
    expect(result.manifestReplaced).toBe(true);
  });
});

describe('시험 실행', () => {
  test('dryRun은 계획만 만들고 아무것도 쓰지 않는다', async () => {
    const { client, puts } = fakeR2();
    const result = await publishRegion(client, '11680', [chunkFor('apartment/sale')], {
      dryRun: true,
    });

    expect(result.uploaded).toHaveLength(1);
    expect(result.manifestReplaced).toBe(false);
    expect(puts).toEqual([]);
  });
});

describe('낡은 청크 탐색', () => {
  test('매니페스트가 가리키지 않는 키를 찾아낸다', async () => {
    const chunk = chunkFor('apartment/sale');
    const stale = 'v1/data/11680/202607/apartment-sale.deadbeefdeadbeef.json.gz';
    const { client } = fakeR2({ existing: new Set([chunkObjectKey(chunk), stale]) });

    const result = await publishRegion(client, '11680', [chunk], {});
    expect(await findObsoleteChunks(client, '11680', result.manifest)).toEqual([stale]);
  });

  test('다른 지역의 키는 건드리지 않는다', async () => {
    const chunk = chunkFor('apartment/sale');
    const other = 'v1/data/11110/202608/land-sale.aaaaaaaaaaaaaaaa.json.gz';
    const { client } = fakeR2({ existing: new Set([chunkObjectKey(chunk), other]) });

    const result = await publishRegion(client, '11680', [chunk], {});
    expect(await findObsoleteChunks(client, '11680', result.manifest)).toEqual([]);
  });

  test('찾기만 하고 지우지 않는다', async () => {
    // 앱이 이전 매니페스트를 캐시하고 있을 수 있어 즉시 삭제는 404를 만든다.
    const stale = 'v1/data/11680/202607/x.aaaaaaaaaaaaaaaa.json.gz';
    const { client, store } = fakeR2();
    store.set(stale, new Uint8Array([1]));

    const result = await publishRegion(client, '11680', [chunkFor('apartment/sale')], {});
    await findObsoleteChunks(client, '11680', result.manifest);
    expect(store.has(stale)).toBe(true);
  });
});
