/**
 * T1.5 지오코딩 스파이크 — 카카오 로컬 API의 등급별 커버리지 측정.
 *
 *   node packages/ingest/scripts/spike-geocode.mjs 11680          # 분포만 (호출 없음)
 *   node packages/ingest/scripts/spike-geocode.mjs 11680 --run    # 실제 변환
 *   node packages/ingest/scripts/spike-geocode.mjs 11680 --run --limit=1000
 *
 * 측정 대상은 **거래가 아니라 고유 주소**다. 같은 단지의 거래 수백 건이 주소 하나로
 * 접히므로, 이 비율이 곧 카카오 일간 10만 쿼터에 대한 여유분이다.
 *
 * 자격증명은 .env에서 읽고 화면에 내지 않는다. 카카오 키는 헤더로만 나간다.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

import { findRegion } from '@realdealmap/shared';

import { configFromEnv, R2Client, readManifest } from '../dist/index.js';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const OUT = resolve(ROOT, 'packages/ingest/spike-geocode.json');

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

/**
 * R2에서 매니페스트가 가리키는 청크를 전부 받아 레코드로 편다.
 *
 * `content-encoding: gzip`으로 올렸으므로 대개 런타임이 알아서 풀어 준다.
 * 다만 그건 보장이 아니라 관측이라, gzip 매직 바이트가 남아 있으면 직접 푼다.
 */
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
  return { manifest, records };
};

/**
 * 카카오에 넘길 지번 주소.
 *
 * **마스킹된 지번은 절대 그대로 보내지 않는다.** 카카오는 `*`를 조용히 버리고
 * `논현동 3*`을 `논현동 3`으로 매칭해 "지번 정확 일치"로 답한다. 실제 지번은 30~39인데
 * 전혀 다른 필지 좌표가 확신을 갖고 돌아온다 — 실측 226~582m 오차.
 *
 * 미매칭보다 나쁘다. 미매칭은 법정동 중심점으로 낮춰 "대략 위치"라고 표기할 수 있지만,
 * 오탐은 엉뚱한 건물에 정확한 마커를 찍는다. R-14와 같은 종류의 함정이다 —
 * 실패가 성공으로 위장된다.
 *
 * `naive`는 이 함정을 재현해 보기 위한 것이다. 운영 경로가 아니다.
 */
const addressOf = (record, regionName, naive = false) => {
  const base = `${regionName} ${record.umdNm}`;
  if (!record.jibun) return base;
  if (!naive && record.jibun.includes('*')) return base;
  return `${base} ${record.jibun}`;
};

/** 고유 주소로 접는다. 같은 주소의 거래는 좌표가 같으므로 한 번만 변환한다. */
const uniqueAddresses = (records, regionName, naive) => {
  const map = new Map();
  for (const r of records) {
    const address = addressOf(r, regionName, naive);
    const key = `${address}|${r.precision}`;
    const hit = map.get(key);
    if (hit) {
      hit.deals += 1;
      hit.datasets.add(r.datasetKey);
      continue;
    }
    map.set(key, {
      address,
      precision: r.precision,
      datasetKey: r.datasetKey,
      datasets: new Set([r.datasetKey]),
      jibun: r.jibun,
      name: r.name,
      deals: 1,
    });
  }
  return [...map.values()];
};

const GRADES = ['exact', 'jibun', 'partial', 'umd'];

const tally = (rows, pick) => {
  const out = new Map();
  for (const r of rows) {
    const k = pick(r);
    out.set(k, (out.get(k) ?? 0) + 1);
  }
  return out;
};

/** 카카오 주소 검색 1건. 키는 헤더로만 나가고 URL에는 들어가지 않는다. */
const geocode = async (address, key) => {
  const url = `https://dapi.kakao.com/v2/local/search/address.json?query=${encodeURIComponent(address)}`;
  const res = await fetch(url, {
    headers: { Authorization: `KakaoAK ${key}` },
    signal: AbortSignal.timeout(10_000),
  });
  if (res.status === 429) return { ok: false, reason: 'quota' };
  if (!res.ok) return { ok: false, reason: `http:${res.status}` };

  const body = await res.json();
  const doc = body.documents?.[0];
  if (!doc) return { ok: false, reason: 'nomatch' };
  return {
    ok: true,
    lat: Number(doc.y),
    lng: Number(doc.x),
    matched: doc.address_name,
    // 카카오가 지번을 정확히 맞췄는지, 아니면 동까지만 맞췄는지 구분한다.
    kind: doc.address?.main_address_no ? 'jibun' : 'region',
  };
};

const pad = (v, w) => String(v).padEnd(w);
const pct = (n, d) => (d === 0 ? '  -  ' : `${((n / d) * 100).toFixed(1)}%`);

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const run = args.includes('--run');
  const naive = args.includes('--naive');
  const limitArg = args.find((a) => a.startsWith('--limit='));
  const limit = limitArg ? Number(limitArg.slice('--limit='.length)) : 1000;
  const [sggCd = '11680'] = args.filter((a) => !a.startsWith('--'));

  const region = findRegion(sggCd);
  if (!region) throw new Error(`알 수 없는 시군구: ${sggCd}`);

  const r2 = new R2Client(configFromEnv());
  const { manifest, records } = await fetchRecords(r2, sggCd);
  const addresses = uniqueAddresses(records, region.name, naive);

  if (naive) console.log('!! --naive: 마스킹 지번을 그대로 보낸다 (함정 재현용)\n');
  console.log(`지역 ${region.name} · 계약월 ${[...new Set(manifest.files.map((f) => f.month))].sort().join(', ')}\n`);

  console.log('거래 → 고유 주소');
  console.log(`  거래       ${records.length.toLocaleString()}건`);
  console.log(`  고유 주소  ${addresses.length.toLocaleString()}개`);
  console.log(`  압축비     ${(records.length / addresses.length).toFixed(1)}배\n`);

  const byGrade = tally(addresses, (a) => a.precision);
  const dealsByGrade = new Map();
  for (const a of addresses) {
    dealsByGrade.set(a.precision, (dealsByGrade.get(a.precision) ?? 0) + a.deals);
  }

  console.log('등급별 분포');
  console.log(`  ${pad('등급', 10)}${pad('고유 주소', 12)}${pad('거래', 10)}압축비`);
  for (const g of GRADES) {
    const u = byGrade.get(g) ?? 0;
    const d = dealsByGrade.get(g) ?? 0;
    if (u === 0) continue;
    console.log(`  ${pad(g, 10)}${pad(u.toLocaleString(), 12)}${pad(d.toLocaleString(), 10)}${(d / u).toFixed(1)}배`);
  }

  if (!run) {
    console.log('\n--run 을 붙이면 실제로 변환한다.');
    return;
  }

  // 등급별로 고르게 뽑는다. 합계만 맞추면 exact가 표본을 다 먹어
  // 정작 궁금한 partial·umd가 몇 건 안 잡힌다.
  const perGrade = Math.ceil(limit / GRADES.filter((g) => (byGrade.get(g) ?? 0) > 0).length);
  const sample = [];
  for (const g of GRADES) {
    const pool = addresses.filter((a) => a.precision === g);
    sample.push(...pool.slice(0, perGrade));
  }

  console.log(`\n표본 ${sample.length}건 변환 (등급당 최대 ${perGrade})`);
  const key = process.env.KAKAO_REST_API_KEY;
  if (!key) throw new Error('.env의 KAKAO_REST_API_KEY가 비어 있습니다.');

  const results = [];
  let done = 0;
  for (const item of sample) {
    const r = await geocode(item.address, key);
    results.push({ ...item, datasets: [...item.datasets], result: r });
    done += 1;
    if (done % 100 === 0) process.stdout.write(`  ${done}/${sample.length}\r`);
    if (r.reason === 'quota') {
      console.log('\n  쿼터 소진 — 중단한다.');
      break;
    }
  }
  console.log(`  ${done}/${sample.length} 완료\n`);

  console.log('등급별 성공률');
  console.log(`  ${pad('등급', 10)}${pad('시도', 8)}${pad('성공', 8)}${pad('성공률', 9)}${pad('지번일치', 10)}미매칭`);
  for (const g of GRADES) {
    const rows = results.filter((r) => r.precision === g);
    if (rows.length === 0) continue;
    const ok = rows.filter((r) => r.result.ok);
    const exactHit = ok.filter((r) => r.result.kind === 'jibun');
    const nomatch = rows.filter((r) => r.result.reason === 'nomatch');
    console.log(
      `  ${pad(g, 10)}${pad(rows.length, 8)}${pad(ok.length, 8)}${pad(pct(ok.length, rows.length), 9)}${pad(pct(exactHit.length, rows.length), 10)}${nomatch.length}`,
    );
  }

  console.log('\n유형별 성공률');
  const keys = [...new Set(results.map((r) => r.datasetKey))].sort();
  for (const k of keys) {
    const rows = results.filter((r) => r.datasetKey === k);
    const ok = rows.filter((r) => r.result.ok);
    console.log(`  ${pad(k, 18)}${pad(rows.length, 7)}${pct(ok.length, rows.length)}`);
  }

  const failures = results.filter((r) => !r.result.ok);
  if (failures.length > 0) {
    console.log(`\n실패 표본 (${failures.length}건 중 최대 8)`);
    for (const f of failures.slice(0, 8)) {
      console.log(`  [${f.precision}] ${f.address}  → ${f.result.reason}`);
    }
  }

  writeFileSync(OUT, JSON.stringify({ sggCd, region: region.name, results }, null, 2), 'utf8');
  console.log(`\n원자료 ${OUT}`);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
