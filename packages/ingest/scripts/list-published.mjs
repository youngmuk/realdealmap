/**
 * R2에 매니페스트가 있는 시군구 코드를 한 줄에 하나씩 찍는다.
 *
 *   node packages/ingest/scripts/list-published.mjs
 *   node packages/ingest/scripts/list-published.mjs --need-first
 *
 * 예약 작업이 "어느 지역을 채워야 하는가"를 정하는 데 쓴다. 배포된 적 없는 지역은
 * 주소가 없어 지오코딩할 것도 없으므로, 목록의 출처는 지역 카탈로그가 아니라 R2다.
 *
 * `--need-first`는 **사전이 빈 지역을 앞으로 보낸다.** 코드 오름차순으로 돌면
 * 이미 다 채운 서울부터 훑는데, 지역 하나를 "채울 게 없다"고 판정하는 데도
 * 청크를 전부 내려받아야 해서 약 12초가 든다(실측). 256개면 그것만으로 50분이다.
 * 정작 미착수는 뒤쪽 코드대에 몰려 있어, 쿼터가 남아 있는 동안 손도 못 댄 채
 * 실행이 끝난다. 빈 사전부터 돌면 같은 시간에 실제로 채우는 양이 늘어난다.
 */
import { configFromEnv, manifestKey, R2Client, readDictionary } from '../dist/index.js';

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

  const sorted = [...codes].sort();
  if (!process.argv.includes('--need-first')) {
    for (const code of sorted) console.log(code);
    return;
  }

  // 사전은 지역당 파일 하나라 256개를 한꺼번에 읽어도 몇 초다.
  // 청크를 내려받는 것에 비하면 무시할 만한 값이고, 그 대가로 순서를 얻는다.
  const sized = await Promise.all(
    sorted.map(async (code) => ({
      code,
      filled: Object.keys((await readDictionary(r2, code)).entries).length,
    })),
  );
  sized.sort((a, b) => a.filled - b.filled || a.code.localeCompare(b.code));
  for (const { code } of sized) console.log(code);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
