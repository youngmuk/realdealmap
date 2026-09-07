/**
 * 이미 배포된 청크에 좌표를 붙여 다시 굽는다 (T3.3 후속).
 *
 *   node packages/ingest/scripts/rebake-region.mjs 31110
 *   node packages/ingest/scripts/rebake-region.mjs 31110 --plan      # 굽지 않고 이득만
 *   node packages/ingest/scripts/rebake-region.mjs 31110 --dry-run
 *
 * **왜 필요한가.** 적재는 좌표 없이 12개월을 굽는다(`--geocode=0`). 카카오가 느리고
 * 계정 전체가 하루 10만이라 국토부 수집을 거기에 묶을 이유가 없기 때문이다. 그 뒤
 * geocode-queue가 사전을 채운다. 그런데 매 시간 갱신은 **최근 3개월만** 다시 굽는다.
 * 나머지 아홉 달은 사전이 채워진 뒤에도 영영 좌표 없는 청크로 남는다 —
 * 목록에는 나오지만 지도에는 한 점도 찍히지 않는다.
 *
 * `buildChunk`의 주석이 "좌표는 나중에 사전이 채워진 뒤 다시 구우면 붙는다"고
 * 적어 둔 그 '다시 굽기'가 이 스크립트다.
 *
 * **원천을 부르지 않는다.** 청크 레코드가 원본 항목(`raw`)을 그대로 들고 있으므로
 * 거기서 다시 정규화한다. 좌표만 붙이자고 국토부 호출을 108번 더 쓸 이유가 없다.
 *
 * 배포는 publish-region과 같은 경로(`publishRegion`)를 쓴다 — 게이트도 그대로 걸린다.
 */
import { appendFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

import { findRegion } from '@realdealmap/shared';

import {
  buildChunk,
  configFromEnv,
  coverageByDataset,
  normalizeAll,
  publishRegion,
  R2Client,
  readDictionary,
  readManifest,
} from '@realdealmap/ingest';

import { loadEnv } from './env.mjs';

const EXIT = { ok: 0, error: 1, held: 2 };

const summarize = (markdown) => {
  const path = process.env.GITHUB_STEP_SUMMARY;
  if (!path) return;
  appendFileSync(path, `${markdown}\n`, 'utf8');
};

/** 올릴 때 gzip으로 올렸으므로 대개 런타임이 풀어 준다. 보장은 아니라서 직접도 푼다. */
const inflate = (bytes) => {
  const buf = Buffer.from(bytes);
  return buf[0] === 0x1f && buf[1] === 0x8b ? gunzipSync(buf) : buf;
};

const located = (records) => records.filter((r) => r.lat !== null && r.lat !== undefined).length;

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const plan = args.includes('--plan');
  const dryRun = args.includes('--dry-run');
  const [sggCd = '11680'] = args.filter((a) => !a.startsWith('--'));

  const region = findRegion(sggCd);
  if (!region) throw new Error(`시군구 코드를 카탈로그에서 찾을 수 없습니다: ${sggCd}`);

  const r2 = new R2Client(configFromEnv());
  const manifest = await readManifest(r2, sggCd);
  if (!manifest) throw new Error(`${sggCd}의 매니페스트가 없습니다. 먼저 배포하세요.`);
  const dictionary = await readDictionary(r2, sggCd);

  console.log(`지역=${sggCd} ${region.name ?? `${region.sidoName} ${region.sggName}`}`);
  console.log(
    `  파일 ${manifest.files.length}개 · 사전 ${Object.keys(dictionary.entries).length}항목`,
  );

  const chunks = [];
  const periods = new Set();
  let before = 0;
  let after = 0;
  const allRecords = [];

  for (const file of manifest.files) {
    const bytes = await r2.get(file.path);
    if (bytes === null) throw new Error(`청크를 찾을 수 없습니다: ${file.path}`);
    const payload = JSON.parse(inflate(bytes).toString('utf8'));

    before += located(payload.records);
    periods.add(payload.period);

    // 원본 항목에서 다시 정규화한다. 청크는 raw를 그대로 들고 있다.
    const { transactions } = normalizeAll(
      payload.datasetKey,
      payload.records.map((r) => r.raw),
    );
    const chunk = buildChunk(sggCd, payload.datasetKey, payload.period, transactions, dictionary);
    after += located(chunk.payload.records);
    allRecords.push(...chunk.payload.records);
    chunks.push(chunk);
  }

  const gain = after - before;
  console.log(`  좌표 ${before} → ${after}건 (${gain >= 0 ? '+' : ''}${gain})`);

  // 이득이 없으면 올리지 않는다. 같은 내용을 다시 올리면 매니페스트의 refreshedAt만
  // 바뀌어 앱이 108개 청크를 통째로 다시 받는다 — 아무것도 달라지지 않은 채로.
  if (gain <= 0) {
    console.log('  붙일 좌표가 없다. 그대로 둔다.');
    summarize(`### ${sggCd} 다시 굽기 — 변화 없음 (좌표 ${after}건)`);
    return;
  }
  if (plan) {
    console.log('  계획만 세우고 끝낸다.');
    return;
  }

  const result = await publishRegion(r2, sggCd, chunks, {
    dryRun,
    periods: [...periods],
  });

  if (result.hold) {
    console.log(`  보류 — ${result.hold.kind}`);
    summarize(`### ⛔ ${sggCd} 다시 굽기 보류 — ${result.hold.kind}`);
    process.exitCode = EXIT.held;
    return;
  }

  const coverage = coverageByDataset(allRecords, dictionary);
  const total = coverage.reduce((a, r) => a + r.total, 0);
  console.log(`  업로드 ${result.uploaded.length}건 · 건너뜀 ${result.skipped.length}건`);
  summarize(
    `### ${sggCd} 다시 굽기\n\n` +
      `| 항목 | 값 |\n| --- | --- |\n` +
      `| 좌표 | ${before} → ${after}건 (+${gain}) |\n` +
      `| 전체 거래 | ${total}건 |\n` +
      `| 업로드 | ${result.uploaded.length}개 |\n`,
  );
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = EXIT.error;
});
