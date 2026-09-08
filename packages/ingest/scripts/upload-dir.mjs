/**
 * 디렉터리 하나를 통째로 R2에 올린다.
 *
 *   node packages/ingest/scripts/upload-dir.mjs <로컬디렉터리> <R2 프리픽스> [--immutable]
 *
 * **왜 필요한가.** 배경지도 글리프는 글꼴 하나당 256개 파일이다(범위당 하나).
 * `wrangler r2 object put`을 512번 부르면 몇십 분이 걸린다. 청크 업로드 경로는
 * 매니페스트·색인과 묶여 있어 이런 정적 자산에는 맞지 않는다.
 *
 * 큰 파일(수백 MB) 하나는 `upload-large.mjs`가 멀티파트로 올린다. 여기는
 * 작은 파일이 아주 많은 경우다.
 *
 * 주의: 서명 헤더에 자격증명이 들어간다. 어떤 경로로도 헤더를 로그에 내지 않는다.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, posix } from 'node:path';

import { configFromEnv, R2Client } from '@realdealmap/ingest';

import { loadEnv } from './env.mjs';

/** 확장자 → content-type. 모르는 것은 옥텟 스트림으로 둔다. */
const TYPES = {
  '.pbf': 'application/x-protobuf',
  '.json': 'application/json',
  '.png': 'image/png',
  '.pmtiles': 'application/octet-stream',
};

/** 한 번에 여덟 개씩. 순차는 너무 느리고, 다 풀면 R2가 간헐적으로 끊는다. */
const CONCURRENCY = 8;

const walk = (dir, prefix = '') => {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const key = prefix ? posix.join(prefix, entry) : entry;
    if (statSync(full).isDirectory()) out.push(...walk(full, key));
    else out.push({ full, key });
  }
  return out;
};

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const immutable = args.includes('--immutable');
  const [root, prefix] = args.filter((a) => !a.startsWith('--'));
  if (!root || !prefix) throw new Error('쓰임: upload-dir.mjs <로컬디렉터리> <R2 프리픽스> [--immutable]');

  const r2 = new R2Client(configFromEnv());
  const files = walk(root);
  console.log(`${root} → ${prefix} · 파일 ${files.length}개`);

  let bytes = 0;
  for (let i = 0; i < files.length; i += CONCURRENCY) {
    await Promise.all(
      files.slice(i, i + CONCURRENCY).map(async ({ full, key }) => {
        const body = readFileSync(full);
        await r2.put(posix.join(prefix, key), body, {
          contentType: TYPES[extname(full).toLowerCase()] ?? 'application/octet-stream',
          // 이름에 날짜나 해시가 박힌 자산만 immutable로 둔다. 그렇지 않은 것을
          // 1년 캐시로 올리면 고치고 싶어도 사용자 기기에서 못 바꾼다.
          cacheControl: immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=300',
        });
        bytes += body.length;
      }),
    );
  }
  console.log(`올림 ${files.length}개 · ${(bytes / 1048576).toFixed(1)} MiB`);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
