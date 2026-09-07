/**
 * 한 지역의 좌표 사전을 채운다 (T3.3·T3.6).
 *
 *   node packages/ingest/scripts/geocode-region.mjs 11680
 *   node packages/ingest/scripts/geocode-region.mjs 11680 --budget=20000
 *   node packages/ingest/scripts/geocode-region.mjs 11680 --plan   # 호출 없이 대상만
 *
 * **주소는 R2에 이미 배포된 청크에서 읽는다.** 원천을 다시 부르면 국토부 호출을
 * 두 배로 쓰는데, 필요한 것은 좌표뿐이고 주소는 청크에 그대로 들어 있다.
 * 그래서 이 작업은 국토부 호출을 한 번도 하지 않는다.
 *
 * 사전만 채우고 청크는 다시 굽지 않는다. 다음 갱신이 사전을 읽어 좌표를 굽는다 —
 * 예약 작업이 배포까지 하면 갱신 경로가 둘이 되어 매니페스트 교체가 경합한다.
 *
 * 자격증명은 .env에서 읽고 화면에 내지 않는다. 카카오 키는 헤더로만 나간다.
 */
import { appendFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

import { findRegion } from '@realdealmap/shared';

import {
  configFromEnv,
  coverageByDataset,
  coverageMarkdown,
  evaluateG3,
  findMissing,
  Geocoder,
  KAKAO_DAILY_QUOTA,
  readDictionary,
  readManifest,
  R2Client,
  withEntries,
  writeDictionary,
} from '../dist/index.js';

import { loadEnv, requireEnv } from './env.mjs';

const EXIT = { ok: 0, error: 1, quota: 2 };

const summarize = (markdown) => {
  const path = process.env.GITHUB_STEP_SUMMARY;
  if (!path) return;
  appendFileSync(path, `${markdown}\n`, 'utf8');
};

/**
 * 배포된 청크를 전부 받아 레코드로 편다.
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
  return records;
};

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const plan = args.includes('--plan');
  const budgetArg = args.find((a) => a.startsWith('--budget='));
  const budget = budgetArg ? Number(budgetArg.slice('--budget='.length)) : KAKAO_DAILY_QUOTA;
  if (!Number.isInteger(budget) || budget < 1) throw new Error(`--budget 값이 잘못됨: ${budgetArg}`);
  const [sggCd = '11680'] = args.filter((a) => !a.startsWith('--'));

  const region = findRegion(sggCd);
  if (!region) throw new Error(`시군구 코드를 카탈로그에서 찾을 수 없습니다: ${sggCd}`);
  const regionName = region.name ?? `${region.sidoName} ${region.sggName}`;

  const r2 = new R2Client(configFromEnv());
  const records = await fetchRecords(r2, sggCd);
  const dictionary = await readDictionary(r2, sggCd);
  const today = new Date().toISOString().slice(0, 10);
  const missing = findMissing(records, dictionary, today);

  console.log(`지역=${sggCd} ${regionName}`);
  console.log(`  거래 ${records.length}건 · 사전 ${Object.keys(dictionary.entries).length}항목`);
  console.log(`  변환 대상 ${missing.length}건 (예산 ${budget})`);

  if (plan || missing.length === 0) {
    const gate = evaluateG3(coverageByDataset(records, dictionary));
    console.log(plan ? '  계획만 세우고 끝낸다.' : '  사전이 최신이다.');
    summarize(coverageMarkdown(sggCd, coverageByDataset(records, dictionary), gate));
    return;
  }

  const geocoder = new Geocoder({
    apiKey: requireEnv('KAKAO_REST_API_KEY'),
    regionName,
    budget,
    today,
  });
  const result = await geocoder.run(missing);

  console.log(
    `  호출 ${result.calls}회 → 성공 ${result.found} · 미매칭 ${result.nomatch} · 이월 ${result.deferred.length}`,
  );
  if (result.errors.length > 0) {
    console.log(`  ! 오류 ${result.errors.length}건 — ${result.errors[0]}`);
  }

  const updated =
    Object.keys(result.entries).length > 0
      ? withEntries(dictionary, result.entries, new Date())
      : dictionary;
  if (updated !== dictionary) await writeDictionary(r2, updated);

  const coverage = coverageByDataset(records, updated);
  const gate = evaluateG3(coverage);
  console.log(`  G3 ${gate === null ? '미판정' : gate.passed ? '통과' : `실패 ${(gate.ratio * 100).toFixed(1)}%`}`);
  summarize(coverageMarkdown(sggCd, coverage, gate));

  // 쿼터에 막힌 것은 실패가 아니라 **다음 실행으로 넘긴 것**이다. 다만 사람이 봐야 한다.
  if (result.quotaExhausted) {
    console.log('  ! 카카오 쿼터에 막혔다. 나머지는 다음 실행으로.');
    process.exitCode = EXIT.quota;
  }
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = EXIT.error;
});
