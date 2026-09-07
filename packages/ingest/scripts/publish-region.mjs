/**
 * 한 지역을 수집해 R2까지 배포한다 (T2.2~T2.8 관통).
 *
 *   node packages/ingest/scripts/publish-region.mjs 11680
 *   node packages/ingest/scripts/publish-region.mjs 11680 --months=3 --dry-run
 *
 * **최근 N개월을 한 번에 올린다.** 매니페스트는 그 지역에서 살아 있는 파일의
 * 전체 목록이므로(§5.2), 한 달치만 넘기면 나머지 달이 목록에서 사라진다.
 * 갱신 단위가 지역인 이유이기도 하다.
 *
 * 자격증명은 .env에서 읽고 화면에 내지 않는다.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  buildChunk,
  configFromEnv,
  datasetKeys,
  findObsoleteChunks,
  MolitClient,
  normalizeAll,
  publishRegion,
  recentPeriods,
  R2Client,
} from '../dist/index.js';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');

const loadEnv = () => {
  const raw = readFileSync(resolve(ROOT, '.env'), 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
  }
};

const readServiceKey = () => {
  const key = process.env.DATA_GO_KR_SERVICE_KEY;
  if (!key) throw new Error('.env의 DATA_GO_KR_SERVICE_KEY가 비어 있습니다.');
  return key;
};

const pad = (v, w) => String(v).padStart(w);

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const monthsArg = args.find((a) => a.startsWith('--months='));
  const months = monthsArg ? Number(monthsArg.slice('--months='.length)) : 3;
  if (!Number.isInteger(months) || months < 1) throw new Error(`--months 값이 잘못됨: ${monthsArg}`);
  const [sggCd = '11680'] = args.filter((a) => !a.startsWith('--'));

  const molit = new MolitClient({ serviceKey: readServiceKey() });
  const r2 = new R2Client(configFromEnv());
  const resolved = molit.resolveSggCd(sggCd);
  if (resolved !== sggCd) console.log(`시군구 코드 보정: ${sggCd} → ${resolved}`);
  const periods = recentPeriods(new Date(), months);
  console.log(
    `지역=${resolved} 계약월=${periods.join(',')} 버킷=${r2.bucket}${dryRun ? ' (시험 실행)' : ''}
`,
  );

  console.log('수집');
  const chunks = [];
  let issues = 0;
  let calls = 0;
  for (const period of periods) {
    for (const key of datasetKeys()) {
      const fetched = await molit.fetchAll(key, resolved, period);
      calls += fetched.calls;
      const { transactions, failures } = normalizeAll(key, fetched.items);
      const chunk = buildChunk(resolved, key, period, transactions);
      chunks.push(chunk);

      console.log(
        `  ${period}  ${key.padEnd(16)} ${pad(chunk.payload.count, 5)}건  ${pad(chunk.bytes.byteLength, 6)}B`,
      );
      if (failures.length > 0) {
        issues += 1;
        console.log(`    ! 정규화 실패 ${failures.length}건 — ${failures[0].message}`);
      }
      if (fetched.drift.unknown.length || fetched.drift.missing.length) {
        issues += 1;
        console.log(
          `    ! 스키마 변화 추가=[${fetched.drift.unknown}] 누락=[${fetched.drift.missing}]`,
        );
      }
    }
  }

  console.log('\n배포');
  const result = await publishRegion(r2, resolved, chunks, { dryRun });

  if (result.hold) {
    const h = result.hold;
    console.log(
      h.kind === 'recordDrop'
        ? `  보류 — 건수 급락 ${h.before} → ${h.after} (${(h.ratio * 100).toFixed(1)}%). 매니페스트를 바꾸지 않았다.`
        : `  보류 — 업로드 상한 초과 ${h.needed} > ${h.cap}. 매니페스트를 바꾸지 않았다.`,
    );
    process.exitCode = 1;
    return;
  }

  console.log(`  업로드 ${result.uploaded.length}건 · 건너뜀 ${result.skipped.length}건`);
  console.log(`  매니페스트 ${result.manifestReplaced ? '교체됨' : '유지(시험 실행)'}`);
  console.log(`  총 ${result.totalRecords}건 · 파일 ${result.manifest.files.length}개`);

  if (!dryRun) {
    const obsolete = await findObsoleteChunks(r2, resolved, result.manifest);
    if (obsolete.length > 0) {
      console.log(`  낡은 청크 ${obsolete.length}건 (삭제하지 않음 — 보관 기간 후 별도 정리)`);
    }
  }

  console.log(`
호출 ${calls}회 · 수집 이슈 ${issues}건`);
  process.exitCode = issues > 0 ? 1 : 0;
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
