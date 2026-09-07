/**
 * 아직 12개월이 채워지지 않은 시군구를 골라낸다 (T6.1).
 *
 *   node packages/ingest/scripts/backfill-plan.mjs --months=12 --limit=60
 *
 * **진행 상태를 따로 저장하지 않는다.** R2에 있는 매니페스트가 곧 진행 상태다.
 * 어디까지 했는지를 별도 파일이나 커밋으로 들고 있으면, 적재가 중간에 끊겼을 때
 * 그 파일과 실제 R2가 어긋나고 그때부터는 무엇을 믿을지 알 수 없게 된다.
 * 매번 R2에 물어보면 몇 번을 끊고 다시 시작해도 같은 답이 나온다.
 *
 * 표준출력으로 시군구 코드를 한 줄에 하나씩 찍는다. 진행 상황은 표준오류로 낸다 —
 * 워크플로가 표준출력을 그대로 목록으로 읽기 때문이다.
 */
import { queryableRegions } from '@realdealmap/shared';

import { configFromEnv, manifestKey, R2Client, recentPeriods } from '../dist/index.js';

import { loadEnv } from './env.mjs';

const argOf = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};

const positive = (raw, name) => {
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) throw new Error(`${name}이(가) 1 이상의 정수가 아닙니다: ${raw}`);
  return n;
};

/** 이 지역이 이번 달 기준으로 필요한 달을 다 갖고 있는가. */
const coveredMonths = (manifest) => {
  const months = new Set();
  for (const file of manifest.files ?? []) {
    if (typeof file.month === 'string') months.add(file.month);
  }
  return months;
};

const main = async () => {
  loadEnv();

  const months = positive(argOf('months', '12'), '개월 수');
  const limit = positive(argOf('limit', '60'), '지역 수');
  const needed = recentPeriods(new Date(), months);

  const r2 = new R2Client(configFromEnv());
  const regions = queryableRegions();

  const todo = [];
  let complete = 0;
  let partial = 0;
  let absent = 0;

  for (const region of regions) {
    // 이미 채운 지역을 찾으면 더 볼 것이 없다. 남은 목록만 필요하므로
    // 상한에 닿는 즉시 멈춘다 — 256개 매니페스트를 매번 다 읽을 이유가 없다.
    if (todo.length >= limit) break;

    const raw = await r2.get(manifestKey(region.sggCd));
    if (raw === null) {
      absent += 1;
      todo.push(region.sggCd);
      continue;
    }

    let manifest;
    try {
      manifest = JSON.parse(new TextDecoder().decode(raw));
    } catch {
      // 읽을 수 없는 매니페스트는 없는 것과 같다. 다시 만든다.
      absent += 1;
      todo.push(region.sggCd);
      continue;
    }

    const have = coveredMonths(manifest);
    const missing = needed.filter((m) => !have.has(m));
    if (missing.length === 0) {
      complete += 1;
      continue;
    }

    partial += 1;
    todo.push(region.sggCd);
    console.error(`  ${region.sggCd} ${region.name} — ${missing.length}개월 부족`);
  }

  console.error(
    `전체 ${regions.length}개 중 완료 ${complete} · 부분 ${partial} · 없음 ${absent}` +
      ` → 이번 실행 대상 ${todo.length}개 (상한 ${limit})`,
  );

  for (const code of todo) console.log(code);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
