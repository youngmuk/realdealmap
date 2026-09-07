import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import type { DatasetKey, PropertyType, TradeType } from '@realdealmap/shared';
import { describe, expect, test } from 'vitest';

import { buildChunk, chunkObjectKey, type Chunk } from './chunk.js';
import { normalizeAll, type Transaction } from './normalize.js';
import { parseResponse } from './parse.js';
import {
  carryOver,
  comboKey,
  checkRecordDrop,
  findObsoleteChunks,
  findVanishedCombos,
  manifestKey,
  publishRegion,
  PublishError,
  readManifest,
  SCHEMA_VERSION,
  type Manifest,
  type ManifestFile,
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

/**
 * R2를 흉내내는 메모리 저장소. 실패를 원하는 키에 주입할 수 있다.
 *
 * `pageSize`를 주면 `list`가 실제로 여러 페이지로 쪼개져 `nextToken`을 돌려준다.
 * 이걸 안 하면 `findObsoleteChunks`의 `do...while(token)` 루프가 항상 1회만 돌아,
 * 2페이지째로 넘어가는 경로가 **한 번도 실행되지 않은 채** 테스트가 통과한다.
 */
const fakeR2 = (
  options: { failOn?: string; existing?: Set<string>; pageSize?: number } = {},
) => {
  const store = new Map<string, Uint8Array>();
  const puts: string[] = [];
  const listCalls: (string | undefined)[] = [];
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
    list: async (prefix: string, token?: string) => {
      const all = [...new Set([...store.keys(), ...existing])]
        .filter((k) => k.startsWith(prefix))
        .sort();
      listCalls.push(token);
      if (!options.pageSize) return { keys: all, nextToken: undefined };

      const from = token ? Number(token) : 0;
      const to = from + options.pageSize;
      return {
        keys: all.slice(from, to),
        nextToken: to < all.length ? String(to) : undefined,
      };
    },
  } as unknown as R2Client;

  return { client, store, puts, existing, listCalls };
};

const seedManifest = (
  store: Map<string, Uint8Array>,
  sggCd: string,
  records: number,
  months: readonly string[] = ['202608'],
): void => {
  const manifest: Manifest = {
    schemaVersion: SCHEMA_VERSION,
    sggCd,
    refreshedAt: '2026-09-01T00:00:00.000Z',
    ttlSeconds: 3600,
    files: months.map((month) => ({
      propertyType: 'apartment' as const,
      tradeType: 'sale' as const,
      month,
      path: `v1/data/11680/${month}/apartment-sale.oldhash00000000.json.gz`,
      sha256: 'old',
      bytes: 1,
      records,
    })),
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

/** 임의의 (유형 · 월 · 건수) 조합으로 이전 매니페스트를 깐다. */
const seedFiles = (
  store: Map<string, Uint8Array>,
  sggCd: string,
  combos: readonly [PropertyType, TradeType, string, number][],
): void => {
  const manifest: Manifest = {
    schemaVersion: SCHEMA_VERSION,
    sggCd,
    refreshedAt: '2026-09-01T00:00:00.000Z',
    ttlSeconds: 3600,
    files: combos.map(([propertyType, tradeType, month, records]) => ({
      propertyType,
      tradeType,
      month,
      path: `v1/data/${sggCd}/${month}/${propertyType}-${tradeType}.old0000000000000.json.gz`,
      sha256: 'old',
      bytes: 1,
      records,
    })),
  };
  store.set(manifestKey(sggCd), new TextEncoder().encode(JSON.stringify(manifest)));
};

const file = (
  propertyType: PropertyType,
  tradeType: TradeType,
  month: string,
  records: number,
): ManifestFile => ({
  propertyType,
  tradeType,
  month,
  path: `v1/data/11680/${month}/${propertyType}-${tradeType}.x.json.gz`,
  sha256: 'x',
  bytes: 1,
  records,
});

describe('유형 실종 게이트 (R-14)', () => {
  test('있던 조합이 0건이 되면 잡는다', () => {
    const prev = [file('apartment', 'sale', '202608', 100), file('land', 'sale', '202608', 88)];
    const next = [file('apartment', 'sale', '202608', 100), file('land', 'sale', '202608', 0)];
    expect(findVanishedCombos(prev, next)).toEqual(['land/sale 202608']);
  });

  test('조합이 통째로 빠져도 잡는다', () => {
    const prev = [file('apartment', 'sale', '202608', 100), file('land', 'sale', '202608', 88)];
    const next = [file('apartment', 'sale', '202608', 100)];
    expect(findVanishedCombos(prev, next)).toEqual(['land/sale 202608']);
  });

  test('이번 배치의 월 범위 밖은 정상 소멸로 본다', () => {
    // 최근 N개월만 올리므로 창이 밀리면 옛 달이 빠지는 것은 당연하다.
    const prev = [file('apartment', 'sale', '202605', 100)];
    const next = [file('apartment', 'sale', '202608', 100)];
    expect(findVanishedCombos(prev, next)).toEqual([]);
  });

  test('원래 0건이던 조합은 실종이 아니다', () => {
    const prev = [file('land', 'sale', '202608', 0)];
    const next = [file('land', 'sale', '202608', 0)];
    expect(findVanishedCombos(prev, next)).toEqual([]);
  });

  test('합계 게이트를 통과하는 실종을 잡아낸다 — 이게 이 게이트의 존재 이유다', async () => {
    // 토지 매매만 조용히 사라진 상황. 합계 비율은 여유롭게 통과한다.
    //
    // 건수는 픽스처 크기에서 끌어온다. 숫자를 박아 두면 픽스처가 바뀔 때
    // 급락 게이트가 먼저 걸려 이 테스트가 "다른 이유로" 실패한다.
    const { client, store, puts } = fakeR2();
    const apt = chunkFor('apartment/sale');
    const aptCount = apt.payload.count;
    const landCount = 5;

    seedFiles(store, '11680', [
      ['apartment', 'sale', '202608', aptCount],
      ['land', 'sale', '202608', landCount],
    ]);
    const before = store.get(manifestKey('11680'));
    const empty = buildChunk('11680', 'land/sale', '202608', []);

    // 합계만 보면 토지가 통째로 빠져도 절반을 훌쩍 넘어 급락 게이트를 통과한다.
    const ratio = aptCount / (aptCount + landCount);
    expect(ratio).toBeGreaterThan(0.5);
    expect(checkRecordDrop(await readManifest(client, '11680'), aptCount, 0.5)).toBeUndefined();

    const result = await publishRegion(client, '11680', [apt, empty], {});
    expect(result.hold).toEqual({ kind: 'datasetDrop', vanished: ['land/sale 202608'] });
    expect(result.manifestReplaced).toBe(false);
    expect(puts).toEqual([]);
    expect(store.get(manifestKey('11680'))).toBe(before);
  });

  test('비율 0이면 이 게이트도 함께 꺼진다', async () => {
    const { client, store } = fakeR2();
    seedFiles(store, '11680', [['land', 'sale', '202608', 10]]);

    const result = await publishRegion(
      client,
      '11680',
      [buildChunk('11680', 'land/sale', '202608', [])],
      { minRecordRatio: 0 },
    );
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

  test('여러 페이지에 걸쳐 있어도 전부 찾는다', async () => {
    // 페이지네이션이 실제로 두 번 이상 돌게 만든다. 이 경로가 없으면
    // 2페이지째의 키가 통째로 누락돼도 테스트가 초록으로 통과한다.
    const chunk = chunkFor('apartment/sale');
    const stale = Array.from(
      { length: 5 },
      (_, i) => `v1/data/11680/20260${i + 1}/land-sale.${String(i).repeat(16)}.json.gz`,
    );
    const { client, listCalls } = fakeR2({
      existing: new Set([chunkObjectKey(chunk), ...stale]),
      pageSize: 2,
    });

    const result = await publishRegion(client, '11680', [chunk], {});
    const obsolete = await findObsoleteChunks(client, '11680', result.manifest);

    expect([...obsolete].sort()).toEqual([...stale].sort());
    // 실제로 여러 페이지를 넘겼는지 — 이어받은 토큰이 있어야 한다.
    expect(listCalls.filter((t) => t !== undefined).length).toBeGreaterThan(0);
  });

  test('매니페스트가 가리키는 키는 몇 페이지에 있든 살아남는다', async () => {
    const chunks = (['apartment/sale', 'apartment/rent', 'land/sale'] as const).map((k) =>
      chunkFor(k),
    );
    const { client } = fakeR2({
      existing: new Set(chunks.map(chunkObjectKey)),
      pageSize: 1,
    });

    const result = await publishRegion(client, '11680', chunks, {});
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

/**
 * 최근 N개월 갱신이 12개월 적재를 지우지 않는가 (T6.1).
 *
 * 매니페스트는 그 지역에서 살아 있는 파일의 전체 목록이다. 이번에 만든 것만
 * 담으면 최근 3개월 갱신 한 번이 나머지 9개월을 목록에서 지운다. 청크는 R2에
 * 그대로 남아 있으므로 손실은 아니지만, 앱에서는 없어진 것과 같다.
 *
 * 실제로는 지워지기 전에 건수 게이트가 보류를 건다. 그래서 이어받기가 없으면
 * 12개월을 채운 지역은 매 시간 갱신이 보류로 끝난다.
 */
describe('carryOver', () => {
  const now = new Date('2026-09-08T00:00:00.000Z');
  const file = (month: string, records = 10): ManifestFile => ({
    propertyType: 'apartment',
    tradeType: 'sale',
    month,
    path: `v1/data/11680/${month}/apartment-sale.hash.json.gz`,
    sha256: 'h',
    bytes: 1,
    records,
  });
  const manifest = (files: ManifestFile[]): Manifest => ({
    schemaVersion: SCHEMA_VERSION,
    sggCd: '11680',
    refreshedAt: '2026-09-01T00:00:00.000Z',
    ttlSeconds: 3600,
    files,
  });

  test('이번에 시도하지 않은 달만 이어받는다', () => {
    const previous = manifest([file('202609'), file('202608'), file('202605')]);

    const kept = carryOver(previous, ['202609', '202608'], 12, now);

    expect(kept.map((f) => f.month)).toEqual(['202605']);
  });

  // 시도한 달이 0건으로 돌아온 것을 이어받아 메우면 R-14 실종이 완벽히 감춰진다.
  test('시도한 달이 0건이어도 이전 것으로 메우지 않는다', () => {
    const previous = manifest([file('202609', 500)]);

    const kept = carryOver(previous, ['202609'], 12, now);

    expect(kept).toEqual([]);
  });

  test('무엇을 시도했는지 모르면 이어받지 않는다', () => {
    const previous = manifest([file('202605')]);

    expect(carryOver(previous, undefined, 12, now)).toEqual([]);
  });

  // 이어받기를 끝없이 하면 매니페스트가 영원히 자라고, 앱은 볼 일 없는 달을 받는다.
  test('보관 창 밖은 이어받지 않는다', () => {
    // 2026-09 기준 12개월 창은 202510~202609다. 202509는 하루 차이로 밖이다.
    const previous = manifest([file('202510'), file('202509')]);

    const kept = carryOver(previous, ['202609'], 12, now);

    expect(kept.map((f) => f.month)).toEqual(['202510']);
  });

  test('이전 매니페스트가 없으면 빈 목록', () => {
    expect(carryOver(undefined, ['202609'], 12, now)).toEqual([]);
  });

  // 전국 적재에서 실제로 겪은 것: 토지 매매만 일일 쿼터가 바닥났는데 나머지
  // 여덟 유형이 멀쩡한 지역 174곳이 아무것도 배포하지 못했다.
  describe('쿼터로 손도 못 댄 조합', () => {
    const land = (month: string, records = 10): ManifestFile => ({
      propertyType: 'land',
      tradeType: 'sale',
      month,
      path: `v1/data/11680/${month}/land-sale.hash.json.gz`,
      sha256: 'h',
      bytes: 1,
      records,
    });

    test('못 댄 유형은 이전 것을 이어받는다', () => {
      const previous = manifest([file('202609'), land('202609', 40)]);

      const kept = carryOver(previous, ['202609'], 12, now, [
        comboKey('land/sale', '202609'),
      ]);

      // 아파트는 이번에 다시 만들었으니 빠지고, 토지는 손도 못 댔으니 남는다
      expect(kept.map((f) => `${f.propertyType}/${f.tradeType}`)).toEqual(['land/sale']);
    });

    test('달이 다르면 이어받지 않는다', () => {
      const previous = manifest([land('202609', 40)]);

      const kept = carryOver(previous, ['202609'], 12, now, [
        comboKey('land/sale', '202608'),
      ]);

      expect(kept).toEqual([]);
    });

    // 이것이 무너지면 R-14 방어가 통째로 사라진다. 쿼터로 못 댄 것과 원천이
    // 조용히 0건을 준 것은 겉보기가 같고, 뒤엣것은 반드시 게이트에 걸려야 한다.
    test('시도한 유형은 0건이어도 여전히 이어받지 않는다', () => {
      const previous = manifest([file('202609', 500), land('202609', 40)]);

      const kept = carryOver(previous, ['202609'], 12, now, [
        comboKey('land/sale', '202609'),
      ]);

      expect(kept.map((f) => f.propertyType)).not.toContain('apartment');
    });
  });
});

describe('publishRegion 이어받기', () => {
  test('3개월 갱신이 나머지 달을 목록에 남긴다', async () => {
    const { client, store } = fakeR2();
    const chunk = chunkFor('apartment/sale');
    // 12개월이 채워져 있고 각 달 2,139건 — 3개월만 다시 만들면 비율은 25%다
    const months = Array.from({ length: 12 }, (_, i) => {
      const d = new Date(Date.UTC(2026, 8 - i, 1));
      return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
    });
    seedManifest(store, '11680', chunk.payload.count, months);

    const result = await publishRegion(client, '11680', [chunk], {
      periods: ['202608'],
      now: () => new Date('2026-09-08T00:00:00.000Z'),
    });

    expect(result.hold).toBeUndefined();
    expect(result.manifestReplaced).toBe(true);
    expect(new Set(result.manifest.files.map((f) => f.month)).size).toBe(12);
  });

  test('이어받기를 끄면 옛 동작 그대로 보류된다', async () => {
    const { client, store } = fakeR2();
    const chunk = chunkFor('apartment/sale');
    const months = Array.from({ length: 12 }, (_, i) => {
      const d = new Date(Date.UTC(2026, 8 - i, 1));
      return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
    });
    seedManifest(store, '11680', chunk.payload.count, months);

    const result = await publishRegion(client, '11680', [chunk], {
      periods: ['202608'],
      retainMonths: 0,
      now: () => new Date('2026-09-08T00:00:00.000Z'),
    });

    expect(result.hold).toMatchObject({ kind: 'recordDrop' });
  });
});
