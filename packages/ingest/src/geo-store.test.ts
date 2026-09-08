import { describe, expect, test } from 'vitest';

import { GEO_VERSION, geoObjectKey, type GeoDictionary, type GeoEntry } from './geo.js';
import { dictionaryBytes, readDictionary, writeDictionary } from './geo-store.js';
import type { R2Client } from './r2.js';

const fakeR2 = () => {
  const store = new Map<string, Uint8Array>();
  const client = {
    put: async (key: string, body: Uint8Array) => void store.set(key, body),
    get: async (key: string) => store.get(key) ?? null,
  } as unknown as R2Client;
  return { client, store };
};

const entry = (lat: number): GeoEntry => ({
  lat,
  lng: 127,
  source: 'address',
  checkedOn: '2026-09-07',
});

const dict = (entries: Record<string, GeoEntry>): GeoDictionary => ({
  version: GEO_VERSION,
  sggCd: '11680',
  generatedAt: '2026-09-07T00:00:00.000Z',
  entries,
});

const text = (store: Map<string, Uint8Array>): string =>
  new TextDecoder().decode(store.get(geoObjectKey('11680')) ?? new Uint8Array());

describe('사전 저장', () => {
  test('올린 것을 그대로 읽는다', async () => {
    const { client, store } = fakeR2();
    await writeDictionary(client, dict({ '논현동|1': entry(37.5) }));

    expect(store.has(geoObjectKey('11680'))).toBe(true);
    expect((await readDictionary(client, '11680')).entries['논현동|1']?.lat).toBe(37.5);
  });

  // 항목 순서가 삽입 순서를 따르면 내용이 같아도 바이트가 달라져 무엇이 바뀌었는지 못 본다.
  test('항목 순서와 무관하게 같은 바이트가 된다', async () => {
    const a = dict({ '가동|1': entry(1), '나동|2': entry(2) });
    const b = dict({ '나동|2': entry(2), '가동|1': entry(1) });

    const first = fakeR2();
    const second = fakeR2();
    await writeDictionary(first.client, a);
    await writeDictionary(second.client, b);

    expect(text(first.store)).toBe(text(second.store));
  });

  // 사전이 없는 것은 첫 실행의 정상 상태다. 여기서 던지면 수집·배포가 통째로 멈춘다.
  test('없으면 빈 사전을 준다', async () => {
    const { client } = fakeR2();
    expect((await readDictionary(client, '11680')).entries).toEqual({});
  });

  test('깨져 있어도 빈 사전으로 이어간다', async () => {
    const { client, store } = fakeR2();
    store.set(geoObjectKey('11680'), new TextEncoder().encode('{ not json'));
    expect((await readDictionary(client, '11680')).entries).toEqual({});
  });

  test('판이 다르면 읽지 않는다', async () => {
    const { client, store } = fakeR2();
    const old = JSON.stringify({ version: GEO_VERSION + 1, entries: { a: entry(1) } });
    store.set(geoObjectKey('11680'), new TextEncoder().encode(old));
    expect((await readDictionary(client, '11680')).entries).toEqual({});
  });

  test('크기를 미리 잴 수 있다', () => {
    expect(dictionaryBytes(dict({ '논현동|1': entry(37.5) }))).toBeGreaterThan(0);
  });
});
