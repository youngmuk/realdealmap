/**
 * 도로명주소 건물DB에서 `법정동명|지번 → 건물키` 색인을 만든다.
 *
 *   node --max-old-space-size=6144 packages/ingest/scripts/build-juso-index.mjs \
 *     <건물DB 폴더> <출력 폴더>
 *
 * **좌표는 아직 붙이지 않는다.** 좌표는 위치정보요약DB에 있고 그쪽은 신청·승인이
 * 필요하다. 이 색인은 그 파일이 오기 전에 만들 수 있는 절반이며, 오고 나면
 * `건물키 → 좌표`만 이어 붙이면 사전이 된다.
 *
 * **왜 시도 파일 하나씩 비우나.** 전국 800만 행을 한 Map에 담으면 몇 GB가 된다.
 * 시군구는 시도를 넘지 않으므로 시도 파일 한 쌍을 처리하고 바로 내보내면
 * 최대 사용량이 가장 큰 시도(경기) 하나로 묶인다.
 *
 * **다만 시도 파일에는 남의 시군구가 몇 줄씩 섞여 있다.** 그냥 덮어쓰면 나중에
 * 처리한 시도의 유령 한 줄이 앞서 만든 시군구 파일을 통째로 지운다 — 실제로
 * 하남시 14,072개가 1개로 줄었고, 건수 집계는 멀쩡해서 **로그만 봐서는 알 수 없었다.**
 * 그래서 이번 실행에서 이미 쓴 시군구는 읽어서 합친다.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { addJusoRows } from '@realdealmap/ingest';

/** 도로명주소 배포본은 CP949다. 실제 파일로 확인했다(202608 전체분). */
const decoder = new TextDecoder('euc-kr');

const readLines = (path) => decoder.decode(readFileSync(path)).split('\r\n');

/** `build_seoul.txt` → `seoul` */
const regionOf = (file) => file.replace(/^(build|jibun)_/, '').replace(/\.txt$/, '');

const main = () => {
  const [src, out] = process.argv.slice(2);
  if (!src || !out) throw new Error('쓰임: build-juso-index.mjs <건물DB 폴더> <출력 폴더>');
  mkdirSync(out, { recursive: true });

  const files = readdirSync(src);
  const regions = [...new Set(files.filter((f) => f.startsWith('build_')).map(regionOf))].sort();
  if (regions.length === 0) throw new Error(`${src}에 build_*.txt가 없습니다`);

  const totals = { keys: 0, skipped: 0, collisions: 0, regions: 0 };
  /** 이번 실행에서 이미 파일을 쓴 시군구. 두 번째부터는 합친다 */
  const written = new Set();

  for (const region of regions) {
    const index = new Map();
    let report = { keys: 0, skipped: 0, collisions: 0 };

    for (const [prefix, table] of [
      ['build', 'building'],
      // 관련지번은 한 건물에 딸린 **나머지 지번**이다. 이것이 없으면 대표지번이
      // 아닌 지번으로 거래된 건이 통째로 빠진다.
      ['jibun', 'jibun'],
    ]) {
      const file = `${prefix}_${region}.txt`;
      if (!files.includes(file)) continue;
      const r = addJusoRows(index, readLines(join(src, file)), table);
      report = {
        keys: report.keys + r.keys,
        skipped: report.skipped + r.skipped,
        collisions: report.collisions + r.collisions,
      };
    }

    for (const [sggCd, bucket] of index) {
      const path = join(out, `${sggCd}.json`);
      // 이번 실행에서 쓴 적이 있으면 합친다. 없으면 덮어쓴다 —
      // 지난 실행의 낡은 파일을 물고 가지 않기 위해서다.
      const merged = written.has(sggCd) && existsSync(path)
        ? { ...JSON.parse(readFileSync(path, 'utf8')), ...Object.fromEntries(bucket) }
        : Object.fromEntries(bucket);
      writeFileSync(path, JSON.stringify(merged));
      if (!written.has(sggCd)) totals.regions += 1;
      written.add(sggCd);
    }

    console.log(
      `${region.padEnd(18)} 시군구 ${String(index.size).padStart(3)} · ` +
        `열쇠 ${report.keys.toLocaleString().padStart(9)} · ` +
        `건너뜀 ${report.skipped} · 같은지번 다른건물 ${report.collisions.toLocaleString()}`,
    );
    totals.keys += report.keys;
    totals.skipped += report.skipped;
    totals.collisions += report.collisions;
  }

  console.log(
    `\n합계 — 시군구 ${totals.regions} · 열쇠 ${totals.keys.toLocaleString()} · ` +
      `건너뜀 ${totals.skipped.toLocaleString()} · ` +
      `같은지번 다른건물 ${totals.collisions.toLocaleString()}`,
  );
  // 건너뛴 줄이 많으면 형식이 바뀐 것이다. 조용히 지나가면 다음 달에 좌표가 준다.
  if (totals.skipped > totals.keys * 0.01) {
    throw new Error(`건너뛴 줄이 1%를 넘습니다 (${totals.skipped}). 형식이 바뀌었는지 보세요.`);
  }
};

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
