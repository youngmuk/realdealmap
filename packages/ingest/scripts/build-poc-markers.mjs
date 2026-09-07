/**
 * T1.3 지도 PoC용 마커 데이터셋을 굽는다.
 *
 *   node packages/ingest/scripts/build-poc-markers.mjs 11680 11650 11710
 *   node packages/ingest/scripts/build-poc-markers.mjs 11680 --out=../spike/map_poc/assets/markers.json
 *
 * R2에 배포된 지역의 거래를 **고유 주소로 접어** 카카오로 변환한 뒤,
 * 렌더러가 바로 먹을 수 있는 납작한 좌표 배열로 내보낸다.
 *
 * 세 렌더러가 **동일한 좌표 집합**을 받아야 비교가 성립하므로, 데이터셋은
 * 한 번 구워서 자산으로 고정한다. 실행할 때마다 다시 변환하면 카카오 응답 차이가
 * 측정에 섞인다.
 *
 * 자격증명은 .env에서 읽고 화면에 내지 않는다. 카카오 키는 헤더로만 나간다.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

import { findRegion } from '@realdealmap/shared';

import { configFromEnv, R2Client, readManifest } from '../dist/index.js';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const DEFAULT_OUT = resolve(ROOT, '../spike/map_poc/assets/markers.json');

/** 카카오 로컬 API 일간 한도. 넘길 일은 없지만 넘기려 하면 먼저 멈춘다. */
const KAKAO_DAILY_QUOTA = 100_000;
const CONCURRENCY = 8;

const loadEnv = () => {
  let raw;
  try {
    raw = readFileSync(resolve(ROOT, '.env'), 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return;
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].trim();
  }
};

const fetchRecords = async (r2, sggCd) => {
  const manifest = await readManifest(r2, sggCd);
  if (!manifest) throw new Error(`${sggCd}의 매니페스트가 없습니다. 먼저 배포하세요.`);

  const records = [];
  for (const file of manifest.files) {
    const bytes = await r2.get(file.path);
    if (bytes === null) throw new Error(`청크를 찾을 수 없습니다: ${file.path}`);
    const buf = Buffer.from(bytes);
    const json = buf[0] === 0x1f && buf[1] === 0x8b ? gunzipSync(buf) : buf;
    records.push(...JSON.parse(json.toString('utf8')).records);
  }
  return records;
};

/**
 * 카카오에 넘길 지번 주소.
 *
 * **마스킹된 지번은 그대로 보내지 않는다.** 카카오는 `*`를 조용히 버리고
 * `논현동 3*`을 `논현동 3`으로 매칭해 "지번 정확 일치"로 답한다(T1.5 실측 226~582m 오차).
 * 미매칭보다 나쁘다 — 오탐은 엉뚱한 건물에 정확한 마커를 찍는다.
 */
const addressOf = (record, regionName) => {
  const base = `${regionName} ${record.umdNm}`;
  if (!record.jibun || record.jibun.includes('*')) return base;
  return `${base} ${record.jibun}`;
};

/** 고유 주소로 접는다. 같은 주소의 거래는 좌표가 같으므로 한 번만 변환한다. */
const foldAddresses = (records, regionName, into) => {
  for (const r of records) {
    const address = addressOf(r, regionName);
    const hit = into.get(address);
    if (hit) {
      hit.deals += 1;
      continue;
    }
    into.set(address, { address, precision: r.precision, name: r.name ?? '', deals: 1 });
  }
  return into;
};

/**
 * 카카오 주소 검색 1건. 키는 헤더로만 나가고 URL에는 들어가지 않는다.
 *
 * **응답 본문을 버리지 않는다.** 처음엔 `http:400`만 남겼다가 실패 1,288건의 이유를
 * 알 수 없었다. 원천이 왜 거절했는지는 본문에만 있다 — client.ts에서 같은 실수를
 * 고친 직후에 또 저질렀다.
 */
const geocode = async (address, key) => {
  const url = `https://dapi.kakao.com/v2/local/search/address.json?query=${encodeURIComponent(address)}`;
  const res = await fetch(url, {
    headers: { Authorization: `KakaoAK ${key}` },
    signal: AbortSignal.timeout(10_000),
  });
  if (res.status === 429) return { ok: false, reason: 'quota', detail: '' };
  if (!res.ok) {
    return { ok: false, reason: `http:${res.status}`, detail: (await res.text()).slice(0, 200) };
  }

  const doc = (await res.json()).documents?.[0];
  if (!doc) return { ok: false, reason: 'nomatch', detail: '' };
  return { ok: true, lat: Number(doc.y), lng: Number(doc.x) };
};

/**
 * 일시적 실패는 다시 시도한다.
 *
 * 쿼터 소진과 미매칭은 다시 시도해도 같으므로 제외한다 — 헛돈 호출은 한도를 먹는다.
 */
const geocodeWithRetry = async (address, key, attempts = 3) => {
  let last;
  for (let i = 1; i <= attempts; i += 1) {
    try {
      last = await geocode(address, key);
    } catch (error) {
      last = { ok: false, reason: 'network', detail: String(error?.message ?? error) };
    }
    if (last.ok || last.reason === 'quota' || last.reason === 'nomatch') return last;
    if (i < attempts) await new Promise((r) => setTimeout(r, 300 * 2 ** (i - 1)));
  }
  return last;
};

/** 작업을 동시성 제한 아래 돌린다. 쿼터 소진은 즉시 전체를 멈춘다. */
const runAll = async (items, worker) => {
  let cursor = 0;
  let halted = false;
  const run = async () => {
    for (;;) {
      if (halted) return;
      const item = items[cursor];
      cursor += 1;
      if (!item) return;
      if ((await worker(item)) === 'halt') halted = true;
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, items.length) }, run));
  return halted;
};

const main = async () => {
  loadEnv();
  const key = process.env.KAKAO_REST_API_KEY;
  if (!key) throw new Error('.env의 KAKAO_REST_API_KEY가 비어 있습니다.');

  const args = process.argv.slice(2);
  const outArg = args.find((a) => a.startsWith('--out='));
  const out = outArg ? resolve(ROOT, outArg.slice('--out='.length)) : DEFAULT_OUT;
  const codes = args.filter((a) => !a.startsWith('--'));
  if (codes.length === 0) throw new Error('시군구 코드를 하나 이상 주세요.');

  const r2 = new R2Client(configFromEnv());
  const unique = new Map();
  const regions = [];

  for (const sggCd of codes) {
    const region = findRegion(sggCd);
    if (!region) throw new Error(`카탈로그에 없는 시군구 코드: ${sggCd}`);
    const records = await fetchRecords(r2, sggCd);
    const before = unique.size;
    foldAddresses(records, region.name, unique);
    console.log(
      `${sggCd} ${region.name.padEnd(12)} 거래 ${String(records.length).padStart(6)}건 → 고유 주소 +${unique.size - before}`,
    );
    regions.push({ sggCd, name: region.name, deals: records.length });
  }

  const rows = [...unique.values()];
  console.log(`\n고유 주소 ${rows.length}개 (일간 한도의 ${((rows.length / KAKAO_DAILY_QUOTA) * 100).toFixed(1)}%)`);
  if (rows.length > KAKAO_DAILY_QUOTA) throw new Error('고유 주소가 일간 한도를 넘습니다.');

  console.log('변환');
  const markers = [];
  const failed = [];
  let done = 0;

  const halted = await runAll(rows, async (row) => {
    const r = await geocodeWithRetry(row.address, key);
    done += 1;
    if (done % 500 === 0) console.log(`  ${done}/${rows.length}`);
    if (!r.ok) {
      failed.push({ address: row.address, reason: r.reason, detail: r.detail ?? '' });
      return r.reason === 'quota' ? 'halt' : undefined;
    }
    markers.push({
      lat: Number(r.lat.toFixed(6)),
      lng: Number(r.lng.toFixed(6)),
      n: row.deals,
      p: row.precision,
      t: row.name,
    });
    return undefined;
  });

  if (halted) throw new Error('카카오 일간 쿼터를 소진했습니다. 부분 결과는 쓰지 않습니다.');

  // 좌표 순으로 정렬해 결과를 결정적으로 만든다. 동시 실행 순서가 파일에 남으면
  // 같은 입력에 다른 파일이 나와 세 렌더러가 다른 자산을 받을 수 있다.
  markers.sort((a, b) => a.lat - b.lat || a.lng - b.lng);

  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(
    out,
    JSON.stringify({ generatedAt: new Date().toISOString(), regions, markers }, null, 0),
    'utf8',
  );

  const total = markers.reduce((a, m) => a + m.n, 0);
  console.log(`\n마커 ${markers.length}개 · 거래 ${total}건 · 실패 ${failed.length}건`);

  // 실패를 뭉뚱그리면 "왜 26%가 빠졌는지"를 알 수 없다. 이유별로 세고 표본을 남긴다.
  if (failed.length > 0) {
    const byReason = new Map();
    for (const f of failed) byReason.set(f.reason, (byReason.get(f.reason) ?? 0) + 1);
    for (const [reason, count] of [...byReason].sort((a, b) => b[1] - a[1])) {
      const sample = failed.find((f) => f.reason === reason);
      console.log(`  ${reason.padEnd(12)} ${String(count).padStart(5)}건  예) ${sample.address}`);
      if (sample.detail) console.log(`               ${sample.detail}`);
    }
    writeFileSync(`${out}.failed.json`, JSON.stringify(failed, null, 2), 'utf8');
    console.log(`  실패 목록 ${out}.failed.json`);
  }
  console.log(`저장 ${out}`);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
