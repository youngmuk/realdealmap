/**
 * 이미 올라간 객체의 `cache-control`만 바꾼다.
 *
 *   node packages/ingest/scripts/set-cache-control.mjs <키> <content-type> [--dry-run]
 *
 * 본문은 다시 올리지 않는다 — R2 안에서 자기 자신으로 복사하며 메타데이터만
 * 갈아 끼운다. 729 MiB 배경지도의 헤더 하나를 고치자고 그 바이트를 다시 밀어
 * 넣을 이유가 없다.
 *
 * 이름에 날짜나 해시가 박힌 자산에만 쓴다. 내용이 바뀔 수 있는 키에 1년짜리
 * immutable을 붙이면 바뀐 것을 아무도 못 받는다.
 */
import { configFromEnv, R2Client } from '@realdealmap/ingest';

import { loadEnv } from './env.mjs';

const CACHE_CONTROL = 'public, max-age=31536000, immutable';

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const [key, contentType] = args.filter((a) => !a.startsWith('--'));
  if (!key || !contentType) {
    throw new Error('쓰임: set-cache-control.mjs <키> <content-type> [--dry-run]');
  }

  const r2 = new R2Client(configFromEnv());
  if (!(await r2.exists(key))) throw new Error(`${key}가 없습니다`);

  console.log(`${key} → ${CACHE_CONTROL}${dryRun ? ' (시험 실행)' : ''}`);
  if (!dryRun) await r2.setCacheControl(key, CACHE_CONTROL, contentType);
  console.log('완료');
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
