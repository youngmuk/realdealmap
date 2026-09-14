/**
 * 전국 법정동 검색 색인을 굽는다.
 *
 *   node packages/ingest/scripts/build-umd-index.mjs <좌표사전 폴더> <출력 폴더> [--source=20260901]
 *
 * 좌표 사전(`build-geo-dict.mjs`)이 시군구마다 만들어 둔 `법정동명|` 항목이
 * 재료다 — 그 동에 속한 건물 좌표의 중앙값이다. **새로 계산하지 않는다.**
 * 같은 값을 두 곳에서 따로 구하면 언젠가 어긋나고, 어긋나도 아무 일도 일어나지
 * 않아서 모른 채로 남는다.
 *
 * 결과는 파일 하나(`umd.json.gz`)다. 전국 18,696개에 gzip 260KB라 쪼갤 이유가
 * 없고, 쪼개면 "ㅈㄱㄷ"을 칠 때마다 어느 조각을 받을지 앱이 먼저 알아야 한다 —
 * 그것이 곧 색인이 하나 더 필요하다는 뜻이다.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { umdIndex, umdRowsOf } from '@realdealmap/ingest';

/** `11215.json` → `11215` */
const sggOf = (file) => file.replace(/\.json$/, '');

const main = () => {
  const args = process.argv.slice(2);
  const [src, out] = args.filter((a) => !a.startsWith('--'));
  if (!src || !out) {
    throw new Error('쓰임: build-umd-index.mjs <좌표사전 폴더> <출력 폴더> [--source=YYYYMMDD]');
  }
  const source = (args.find((a) => a.startsWith('--source=')) ?? '').slice('--source='.length);

  const files = readdirSync(src).filter((f) => f.endsWith('.json'));
  if (files.length === 0) throw new Error(`${src}에 좌표 사전이 없습니다`);

  const rows = [];
  const stat = { regions: 0, skipped: 0 };
  for (const file of files.sort()) {
    const sggCd = sggOf(file);
    // 사전은 시군구 코드로 이름이 붙는다. 다른 것이 섞여 있으면 그 파일의
    // 항목이 통째로 엉뚱한 지역에 붙으므로 여기서 걸러 낸다.
    if (!/^\d{5}$/.test(sggCd)) {
      stat.skipped += 1;
      continue;
    }
    const dict = JSON.parse(readFileSync(join(src, file), 'utf8'));
    // 사전 안의 시군구 코드가 파일 이름과 다르면 둘 중 하나가 틀린 것이다.
    // 어느 쪽인지 모르는 채로 좌표를 붙이느니 멈춘다.
    if (dict.sggCd && dict.sggCd !== sggCd) {
      throw new Error(`${file}이 ${dict.sggCd}라고 적혀 있습니다`);
    }
    rows.push(...umdRowsOf(sggCd, dict.entries ?? {}));
    stat.regions += 1;
  }

  const index = umdIndex(source, rows);
  if (index.umds.length === 0) throw new Error('법정동을 하나도 찾지 못했습니다');

  if (!existsSync(out)) mkdirSync(out, { recursive: true });
  const path = join(out, 'umd.json.gz');
  writeFileSync(path, gzipSync(Buffer.from(JSON.stringify(index)), { level: 9 }));

  const names = new Set(index.umds.map((r) => r[0]));
  const bytes = statSync(path).size;
  console.log(
    `시군구 ${stat.regions} · 법정동 ${index.umds.length.toLocaleString()}개 ` +
      `(고유 이름 ${names.size.toLocaleString()}개)`,
  );
  if (stat.skipped > 0) console.log(`시군구 코드가 아닌 파일 ${stat.skipped}개는 건너뛰었습니다`);
  console.log(`${path} · ${(bytes / 1024).toFixed(0)}KB`);
  if (!source) console.log('※ --source를 주지 않아 자료 시점이 비어 있습니다.');
};

main();
