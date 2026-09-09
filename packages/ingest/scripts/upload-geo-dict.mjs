/**
 * `build-geo-dict.mjs`가 만든 사전을 R2에 올린다.
 *
 *   node packages/ingest/scripts/upload-geo-dict.mjs <사전 폴더> [--dry-run]
 *
 * **왜 `upload-dir.mjs`를 안 쓰나.** 그쪽은 정적 자산용이라 `max-age=300`을 붙인다.
 * 사전은 적재 잡이 읽는 것이라, 방금 올린 사전 대신 5분 전 것을 읽으면 그 회차
 * 좌표가 통째로 어긋난다. `writeDictionary`가 붙이는 `no-store`를 그대로 쓴다.
 *
 * 올리기 전에 `parseDictionary`로 한 번 되읽는다. 판이 다르거나 모양이 깨졌으면
 * 그 함수는 **빈 사전**을 주므로, 그것을 그대로 올리면 좌표를 지우는 셈이 된다.
 * 여기서 걸러 낸다.
 */
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  configFromEnv,
  dictionaryBytes,
  parseDictionary,
  R2Client,
  writeDictionary,
} from '@realdealmap/ingest';

import { loadEnv } from './env.mjs';

/** 한 번에 여덟 개씩. 순차는 너무 느리고, 다 풀면 R2가 간헐적으로 끊는다. */
const CONCURRENCY = 8;

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const dryRun = args.includes('--dry-run');
  const [dir] = args.filter((a) => !a.startsWith('--'));
  if (!dir) throw new Error('쓰임: upload-geo-dict.mjs <사전 폴더> [--dry-run]');

  const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
  if (files.length === 0) throw new Error(`${dir}에 사전이 없습니다`);

  const r2 = new R2Client(configFromEnv());
  console.log(`${dir} → v1/geo/ · ${files.length}개${dryRun ? ' (시험 실행)' : ''}`);

  let bytes = 0;
  let entries = 0;
  let done = 0;
  for (let i = 0; i < files.length; i += CONCURRENCY) {
    await Promise.all(
      files.slice(i, i + CONCURRENCY).map(async (file) => {
        const sggCd = file.slice(0, -'.json'.length);
        const dictionary = parseDictionary(sggCd, readFileSync(join(dir, file), 'utf8'));
        const count = Object.keys(dictionary.entries).length;
        // 빈 사전은 올리지 않는다. 판이 다르거나 깨진 파일이라는 뜻이고,
        // 그대로 올리면 있던 좌표를 지운다.
        if (count === 0) throw new Error(`${file}이 비어 있습니다. 판이 다르거나 깨졌습니다.`);
        entries += count;
        bytes += dictionaryBytes(dictionary);
        if (!dryRun) await writeDictionary(r2, dictionary);
      }),
    );
    done += Math.min(CONCURRENCY, files.length - i);
    process.stdout.write(`\r  ${done}/${files.length}`);
  }
  process.stdout.write('\r' + ' '.repeat(24) + '\r');

  console.log(
    `${dryRun ? '확인' : '올림'} ${files.length}개 · 항목 ${entries.toLocaleString()} · ` +
      `${(bytes / 1048576).toFixed(1)} MiB`,
  );
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
