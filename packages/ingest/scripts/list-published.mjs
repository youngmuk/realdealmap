/**
 * R2에 매니페스트가 있는 시군구 코드를 한 줄에 하나씩 찍는다.
 *
 *   node packages/ingest/scripts/list-published.mjs
 *
 * 예약 작업이 "어느 지역을 채워야 하는가"를 정하는 데 쓴다. 배포된 적 없는 지역은
 * 주소가 없어 지오코딩할 것도 없으므로, 목록의 출처는 지역 카탈로그가 아니라 R2다.
 */
import { configFromEnv, manifestKey, R2Client } from '../dist/index.js';

import { loadEnv } from './env.mjs';

const PREFIX = 'v1/regions/';

const main = async () => {
  loadEnv();
  const r2 = new R2Client(configFromEnv());

  const codes = new Set();
  let token;
  do {
    const page = await r2.list(PREFIX, token);
    for (const key of page.keys) {
      const code = key.slice(PREFIX.length).split('/')[0];
      // 매니페스트가 있는 것만 센다. 청크만 남은 잔해를 지역으로 세지 않는다.
      if (/^\d{5}$/.test(code) && key === manifestKey(code)) codes.add(code);
    }
    token = page.nextToken;
  } while (token);

  for (const code of [...codes].sort()) console.log(code);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
