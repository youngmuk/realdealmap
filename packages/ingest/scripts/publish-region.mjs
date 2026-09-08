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
import { appendFileSync } from 'node:fs';


import {
  buildChunk,
  configFromEnv,
  coverageByDataset,
  coverageMarkdown,
  comboKey,
  datasetKeys,
  evaluateG3,
  findObsoleteChunks,
  MolitClient,
  normalizeAll,
  publishRegion,
  updateRegionIndex,
  QuotaExceededError,
  readDictionary,
  recentPeriods,
  R2Client,
} from '../dist/index.js';

import { loadEnv } from './env.mjs';


const readServiceKey = () => {
  const key = process.env.DATA_GO_KR_SERVICE_KEY;
  if (!key) throw new Error('.env의 DATA_GO_KR_SERVICE_KEY가 비어 있습니다.');
  return key;
};

const pad = (v, w) => String(v).padStart(w);

/**
 * 좌표를 채우는 단계는 없다.
 *
 * 예전에는 카카오·VWorld 지오코딩 API로 사전을 채웠다. 두 곳 모두 **응답의
 * 저장**을 금지한다 — 카카오는 "기존 저장 데이터는 즉각 삭제해 주셔야 합니다",
 * VWorld는 약관 제12조. 이 앱은 좌표를 저장해 청크에 굽고 사용자에게 내보내므로
 * 그 경로를 통째로 걷어냈다.
 *
 * 좌표는 공공 주소 데이터 파일에서 만들어 사전에 넣는다. 여기서는 **이미 있는
 * 사전을 읽어 쓸 뿐** 새로 만들지 않는다.
 */
const topUpDictionary = async (_r2, _sggCd, dictionary) => dictionary;

/**
 * 종료 코드를 구분한다. CI가 "무엇 때문에 멈췄는지"를 로그를 읽지 않고 알아야 한다.
 * 보류(2)는 실패가 아니라 **의도한 중단**이지만, 사람이 봐야 하므로 0을 주지 않는다.
 */
const EXIT = { ok: 0, error: 1, held: 2, issues: 3 };

/** GitHub Actions에서 실행 중이면 잡 요약에 남긴다. 로컬에서는 아무것도 안 한다. */
const summarize = (markdown) => {
  const path = process.env.GITHUB_STEP_SUMMARY;
  if (!path) return;
  appendFileSync(path, `${markdown}
`, 'utf8');
};


/** 색인 갱신 한 줄 보고. 규칙과 경합 이야기는 updateRegionIndex 쪽에 있다. */
const updateIndex = async (r2, sggCd, chunks, manifest) => {
  const summary = await updateRegionIndex(r2, sggCd, chunks, manifest);
  if (!summary) {
    console.log('  색인 그대로');
    return;
  }
  const box = summary.bbox
    ? `(${summary.bbox.south}~${summary.bbox.north}, ${summary.bbox.west}~${summary.bbox.east})`
    : '(좌표 없음)';
  console.log(
    `  색인 갱신 — 전체 ${summary.records}건 · 이번 회차 좌표 ` +
      `${summary.located}/${summary.sampled}건 ${box}`,
  );
};

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const monthsArg = args.find((a) => a.startsWith('--months='));
  const months = monthsArg ? Number(monthsArg.slice('--months='.length)) : 3;
  // 상한은 `recentPeriods`가 MAX_MONTHS로 강제한다. 여기서는 형식만 본다 —
  // 두 곳에 숫자를 적어 두면 언젠가 어긋난다.
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
  // 청크를 바로 굽지 않고 거래를 모아 둔다. 좌표 사전을 먼저 채워야 하기 때문이다 —
  // 구운 뒤에 사전을 채우면 그 회차 좌표는 다음 실행까지 비어 있다.
  const batches = [];
  let issues = 0;
  let calls = 0;
  // 쿼터가 바닥난 유형. 그 유형은 이 회차에 한 건도 못 받으므로 남은 달도 시도하지 않는다.
  const exhausted = new Set();
  // 손도 못 댄 (유형 · 월) 조합. 배포에서 이전 매니페스트로 이어받게 한다.
  const unattempted = [];

  for (const period of periods) {
    for (const key of datasetKeys()) {
      if (exhausted.has(key)) {
        unattempted.push(comboKey(key, period));
        continue;
      }

      let fetched;
      try {
        fetched = await molit.fetchAll(key, resolved, period);
      } catch (error) {
        // 쿼터 소진은 이 유형만의 문제다. 여기서 지역 전체를 멈추면 이미 받은
        // 나머지 여덟 유형을 버리게 되고, 내일 그것들을 다시 받느라 쿼터를 또 쓴다.
        // 전국 적재에서 토지 매매 하나 때문에 지역 174곳이 그렇게 됐다.
        if (!(error instanceof QuotaExceededError)) throw error;
        exhausted.add(key);
        unattempted.push(comboKey(key, period));
        console.log(`  ${period}  ${key.padEnd(16)} 쿼터 소진 — 이 유형은 다음 회차로 미룬다`);
        continue;
      }
      calls += fetched.calls;
      const { transactions, failures } = normalizeAll(key, fetched.items);
      batches.push({ period, key, transactions });

      console.log(`  ${period}  ${key.padEnd(16)} ${pad(transactions.length, 5)}건`);
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

  const allTransactions = batches.flatMap((b) => b.transactions);

  console.log('\n좌표');
  // 여기서는 사전을 **읽기만 한다.** 만드는 경로는 없다 (topUpDictionary 주석 참고).
  const dictionary = await topUpDictionary(r2, resolved, await readDictionary(r2, resolved));
  console.log(`  사전 ${Object.keys(dictionary.entries).length}개 항목`);

  // 사전이 채워진 뒤에 굽는다. 순서를 뒤집으면 이번 회차 좌표가 통째로 비어 나간다.
  const chunks = batches.map((b) =>
    buildChunk(resolved, b.key, b.period, b.transactions, dictionary),
  );
  for (const chunk of chunks) {
    console.log(
      `  ${chunk.payload.period}  ${chunk.payload.datasetKey.padEnd(16)} ${pad(chunk.bytes.byteLength, 6)}B`,
    );
  }

  const coverage = coverageByDataset(allTransactions, dictionary);
  const gate = evaluateG3(coverage);
  const located = coverage.reduce((a, r) => a + r.located, 0);
  const totalTx = coverage.reduce((a, r) => a + r.total, 0);
  console.log(
    `  좌표 있음 ${located}/${totalTx}건 · G3 ${gate === null ? '미판정' : gate.passed ? '통과' : `실패 ${(gate.ratio * 100).toFixed(1)}%`}`,
  );

  console.log('\n배포');
  // 이번에 시도한 달을 넘긴다. 그래야 나머지 달을 이전 매니페스트에서
  // 이어받는다 — 안 넘기면 최근 3개월 갱신 한 번이 12개월 적재를 지운다.
  const result = await publishRegion(r2, resolved, chunks, {
    dryRun,
    periods,
    unattempted,
  });

  if (result.hold) {
    const h = result.hold;
    const why =
      h.kind === 'recordDrop'
        ? `건수 급락 ${h.before} → ${h.after} (${(h.ratio * 100).toFixed(1)}%)`
        : h.kind === 'datasetDrop'
          ? `유형 실종 ${h.vanished.length}건 — ${h.vanished.join(', ')}`
          : `업로드 상한 초과 ${h.needed} > ${h.cap}`;

    console.log(`  보류 — ${why}. 매니페스트를 바꾸지 않았다.`);
    summarize(`### ⛔ ${resolved} 배포 보류\n${why}. 매니페스트를 바꾸지 않았다.`);
    process.exitCode = EXIT.held;
    return;
  }

  console.log(`  업로드 ${result.uploaded.length}건 · 건너뜀 ${result.skipped.length}건`);
  console.log(`  매니페스트 ${result.manifestReplaced ? '교체됨' : '유지(시험 실행)'}`);
  console.log(`  총 ${result.totalRecords}건 · 파일 ${result.manifest.files.length}개`);

  if (!dryRun) {
    await updateIndex(r2, resolved, chunks, result.manifest);
    const obsolete = await findObsoleteChunks(r2, resolved, result.manifest);
    if (obsolete.length > 0) {
      console.log(`  낡은 청크 ${obsolete.length}건 (삭제하지 않음 — 보관 기간 후 별도 정리)`);
    }
  }

  console.log(`
호출 ${calls}회 · 수집 이슈 ${issues}건${
    unattempted.length > 0
      ? ` · 쿼터로 미룬 조합 ${unattempted.length}개 (${[...exhausted].join(', ')})`
      : ''
  }`);
  summarize(
    [
      `### ${issues > 0 ? '⚠️' : '✅'} ${resolved} ${dryRun ? '(시험 실행)' : ''}`,
      '',
      '| 항목 | 값 |',
      '| --- | --- |',
      `| 계약월 | ${periods.join(', ')} |`,
      `| 총 건수 | ${result.totalRecords.toLocaleString()} |`,
      `| 청크 | ${result.manifest.files.length}개 |`,
      `| 업로드 | ${result.uploaded.length}건 (건너뜀 ${result.skipped.length}) |`,
      `| 매니페스트 | ${result.manifestReplaced ? '교체됨' : '유지'} |`,
      `| 원천 호출 | ${calls}회 |`,
      `| 수집 이슈 | ${issues}건 |`,
      `| 쿼터로 미룬 조합 | ${unattempted.length}개${
        unattempted.length > 0 ? ` (${[...exhausted].join(', ')})` : ''
      } |`,
      '',
      coverageMarkdown(resolved, coverage, gate),
    ].join('\n'),
  );
  process.exitCode = issues > 0 ? EXIT.issues : EXIT.ok;
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = EXIT.error;
});
