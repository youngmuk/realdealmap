/**
 * 갱신할 지역을 골라 한 줄에 하나씩 찍는다 (T4.7).
 *
 *   node packages/ingest/scripts/pick-regions.mjs --mode=hot  --limit=24
 *   node packages/ingest/scripts/pick-regions.mjs --mode=cold --limit=40
 *
 * 고르는 규칙은 region-pick.ts에 있고 여기서는 색인을 읽어 넘기기만 한다.
 * 규칙이 순수 함수라야 "왜 이 지역이 뽑혔는가"를 테스트로 고정할 수 있다.
 *
 * **코드만 찍는다.** 사람이 볼 설명은 stderr로 낸다 — 워크플로가 stdout을
 * 그대로 목록으로 먹기 때문이다.
 */
import { configFromEnv, pickCold, pickHot, readIndex, R2Client } from '../dist/index.js';

import { loadEnv } from './env.mjs';

const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};

const main = async () => {
  loadEnv();

  const mode = arg('mode', 'hot');
  if (mode !== 'hot' && mode !== 'cold') {
    console.error(`mode는 hot 또는 cold여야 합니다: ${mode}`);
    process.exitCode = 1;
    return;
  }

  // 상한을 여기서 한 번 더 막는다. 워크플로 입력 검증이 뚫려도 한 실행이
  // 전국을 돌지 못하게 한다 — 쿼터를 넘기는 것은 되돌릴 수 없다.
  const limit = Number.parseInt(arg('limit', mode === 'hot' ? '24' : '40'), 10);
  if (!Number.isInteger(limit) || limit < 1 || limit > 60) {
    console.error(`limit은 1~60이어야 합니다: ${arg('limit', '')}`);
    process.exitCode = 1;
    return;
  }

  const index = await readIndex(new R2Client(configFromEnv()));
  const picked = mode === 'hot' ? pickHot(index, limit) : pickCold(index, limit);

  console.error(
    `색인 ${index.regions.length}개 중 ${mode} ${picked.length}개를 골랐다 (상한 ${limit})`,
  );
  for (const code of picked) console.log(code);
};

await main();
