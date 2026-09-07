/**
 * T0.3 완료 확인 — 발급한 토큰으로 실제 버킷에 PUT/GET/HEAD/LIST/DELETE가 되는지 본다.
 *
 *   node packages/ingest/scripts/verify-r2.mjs
 *
 * 자격증명은 .env에서 읽고 화면에 내지 않는다.
 * 시험용 객체는 검증이 끝나면 지운다.
 */
import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { R2Client, configFromEnv } from '../dist/index.js';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');

/** .env를 process.env에 얹는다. 이미 있는 값은 덮어쓰지 않는다. */
const loadEnv = () => {
  let raw;
  try {
    raw = readFileSync(resolve(ROOT, '.env'), 'utf8');
  } catch {
    throw new Error('.env가 없습니다. .env.example을 복사해 채우세요.');
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim();
  }
};

const step = async (label, fn) => {
  const started = Date.now();
  try {
    const detail = await fn();
    console.log(`  ✓ ${label.padEnd(28)} ${String(Date.now() - started).padStart(4)}ms  ${detail ?? ''}`);
    return true;
  } catch (error) {
    console.log(`  ✗ ${label.padEnd(28)} ${error instanceof Error ? error.message : error}`);
    return false;
  }
};

const main = async () => {
  loadEnv();
  const config = configFromEnv();
  const client = new R2Client(config);

  console.log(`버킷=${client.bucket}  계정=${config.accountId.slice(0, 8)}…\n`);

  // 실제 청크와 같은 형태로 시험한다. gzip + 콘텐츠 해시 경로.
  const key = `_selftest/${Date.now()}.json.gz`;
  const json = Buffer.from(JSON.stringify({ hello: 'realdealmap' }), 'utf8');
  const payload = gzipSync(json);
  const results = [];

  results.push(
    await step('PUT (gzip 객체 업로드)', async () => {
      await client.put(key, payload, {
        contentType: 'application/json',
        contentEncoding: 'gzip',
        cacheControl: 'public, max-age=31536000, immutable',
      });
      return `${payload.byteLength} bytes`;
    }),
  );

  results.push(
    await step('HEAD (존재 확인)', async () => {
      if (!(await client.exists(key))) throw new Error('올린 객체가 보이지 않습니다');
    }),
  );

  results.push(
    await step('GET (내용 일치 확인)', async () => {
      // content-encoding: gzip을 붙였으므로 fetch가 받으면서 압축을 푼다.
      // 앱·CDN이 받는 것과 같은 형태이고, 콘텐츠 해시도 이 압축 전 JSON 기준이다.
      const restored = await client.get(key);
      if (restored === null) throw new Error('객체를 받지 못했습니다');
      if (Buffer.compare(Buffer.from(restored), json) !== 0) {
        throw new Error('받은 내용이 올린 내용과 다릅니다');
      }
      return `${restored.byteLength} bytes (gzip ${payload.byteLength} → 자동 해제)`;
    }),
  );

  // 압축 헤더 없이 올리면 저장이 바이트 단위로 정확한지 별도로 본다.
  const rawKey = `_selftest/${Date.now()}-raw.bin`;
  results.push(
    await step('PUT/GET (바이트 무손실 확인)', async () => {
      await client.put(rawKey, payload, { contentType: 'application/octet-stream' });
      const back = await client.get(rawKey);
      if (back === null) throw new Error('객체를 받지 못했습니다');
      if (Buffer.compare(Buffer.from(back), payload) !== 0) {
        throw new Error('저장된 바이트가 올린 바이트와 다릅니다');
      }
      await client.delete(rawKey);
      return `${payload.byteLength} bytes 정확히 일치`;
    }),
  );

  results.push(
    await step('LIST (접두사 조회)', async () => {
      const { keys } = await client.list('_selftest/');
      if (!keys.includes(key)) throw new Error('목록에 방금 올린 키가 없습니다');
      return `${keys.length}건`;
    }),
  );

  results.push(
    await step('DELETE (정리)', async () => {
      await client.delete(key);
      if (await client.exists(key)) throw new Error('삭제 후에도 객체가 남아 있습니다');
    }),
  );

  const failed = results.filter((r) => !r).length;
  console.log(`\n${failed === 0 ? '전부 통과 — T0.3 완료 기준 충족' : `${failed}건 실패`}`);
  process.exitCode = failed === 0 ? 0 : 1;
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
