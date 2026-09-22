/**
 * 이미 올라가 있는 지역들에 첫 설치용 묶음을 달아 준다 (일회성).
 *
 * **왜 일회성인가.** 앞으로는 `publish.ts`가 12개월을 통째로 다시 굽는 배포
 * (`resync-cold` · `backfill`)에서 묶음을 같이 만든다. 하지만 그것이 256개
 * 지역을 한 바퀴 도는 데 한 주가 걸리고, 그동안 앱을 깐 사람은 여전히 청크를
 * 108번 받는다. 출시 전에 한 번만 밀어 둔다.
 *
 * **어떻게.** 지역마다 매니페스트를 읽고, 그것이 가리키는 청크를 R2에서 받아
 * 묶은 뒤, 매니페스트에 `bundle`만 덧붙여 다시 쓴다.
 *
 *   node packages/ingest/scripts/backfill-bundles.mjs [--dry] [--only 11215,11680]
 *
 * 주의: `refreshedAt`을 **건드리지 않는다.** 그 값은 앱이 신선도를 판정하는
 * 기준이라, 여기서 새로 찍으면 전국의 앱이 "방금 갱신된 자료"로 잘못 읽는다.
 */
import { gunzipSync } from 'node:zlib';

import { buildBundle, configFromEnv, R2Client } from '@realdealmap/ingest';

import { loadEnv } from './env.mjs';

const CONCURRENCY = 8;

const args = process.argv.slice(2);
const dryRun = args.includes('--dry');
const onlyAt = args.indexOf('--only');
const only = onlyAt >= 0 ? new Set((args[onlyAt + 1] ?? '').split(',').filter(Boolean)) : null;

loadEnv();
const r2 = new R2Client(configFromEnv(process.env));

const manifestKey = (sggCd) => `v1/regions/${sggCd}/manifest.json`;

/** 지역 목록은 배포된 색인에서 가져온다 — 카탈로그가 아니라 실제로 올라간 것. */
const regionCodes = async () => {
  const bytes = await r2.get('v1/regions/index.json');
  if (!bytes) throw new Error('v1/regions/index.json이 없다');
  const parsed = JSON.parse(Buffer.from(bytes).toString('utf8'));
  const list = Array.isArray(parsed) ? parsed : (parsed.regions ?? []);
  return list.map((r) => (typeof r === 'string' ? r : r.sggCd)).filter(Boolean);
};

const readJsonGz = (bytes) => {
  const buf = Buffer.from(bytes);
  const raw = buf[0] === 0x1f && buf[1] === 0x8b ? gunzipSync(buf) : buf;
  return JSON.parse(raw.toString('utf8'));
};

/** 한 지역. 이미 완전한 묶음이 달려 있으면 건드리지 않는다. */
const backfill = async (sggCd) => {
  const raw = await r2.get(manifestKey(sggCd));
  if (!raw) return { sggCd, status: 'no-manifest' };

  const manifest = JSON.parse(Buffer.from(raw).toString('utf8'));
  const files = manifest.files ?? [];
  if (files.length === 0) return { sggCd, status: 'empty' };
  if (manifest.bundle?.chunks === files.length) return { sggCd, status: 'already' };

  const entries = [];
  for (const file of files) {
    const body = await r2.get(file.path);
    // 매니페스트가 가리키는데 없다. 정리 작업이 앞질렀을 수 있다 — 건드리지 않고 넘긴다.
    if (!body) return { sggCd, status: 'missing-chunk', detail: file.path };
    entries.push({ path: file.path, body: readJsonGz(body) });
  }

  const bundle = buildBundle(sggCd, entries);
  if (dryRun) {
    return {
      sggCd,
      status: 'dry',
      chunks: bundle.ref.chunks,
      bytes: bundle.ref.bytes,
    };
  }

  // 묶음을 **먼저** 올린다. 매니페스트가 가리키는 것은 이미 거기 있어야 한다.
  if (!(await r2.exists(bundle.ref.path))) {
    await r2.put(bundle.ref.path, bundle.gzip, {
      contentType: 'application/json',
      contentEncoding: 'gzip',
      cacheControl: 'public, max-age=31536000, immutable',
    });
  }

  // refreshedAt을 포함해 나머지는 그대로 두고 bundle만 덧붙인다.
  const next = { ...manifest, bundle: bundle.ref };
  await r2.put(manifestKey(sggCd), new TextEncoder().encode(JSON.stringify(next, null, 2)), {
    contentType: 'application/json',
    cacheControl: 'public, max-age=60, must-revalidate',
  });

  return {
    sggCd,
    status: 'done',
    chunks: bundle.ref.chunks,
    bytes: bundle.ref.bytes,
  };
};

const codes = (await regionCodes()).filter((c) => !only || only.has(c));
console.log(`지역 ${codes.length}개${dryRun ? ' · 시험 실행' : ''}`);

const tally = {};
let bytes = 0;
let chunks = 0;
for (let i = 0; i < codes.length; i += CONCURRENCY) {
  const slice = codes.slice(i, i + CONCURRENCY);
  const results = await Promise.all(slice.map((c) => backfill(c)));
  for (const r of results) {
    tally[r.status] = (tally[r.status] ?? 0) + 1;
    if (r.bytes) bytes += r.bytes;
    if (r.chunks) chunks += r.chunks;
    if (r.status === 'missing-chunk') console.log(`  ${r.sggCd} 청크 없음: ${r.detail}`);
  }
  process.stdout.write(`\r  ${Math.min(i + CONCURRENCY, codes.length)}/${codes.length}`);
}

console.log(
  '\n' +
    Object.entries(tally)
      .map(([k, v]) => `${k} ${v}`)
      .join(' · '),
);
console.log(`묶은 청크 ${chunks.toLocaleString()}개 · ${(bytes / 1e6).toFixed(1)}MB`);
