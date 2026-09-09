/**
 * 큰 파일을 R2에 멀티파트로 올린다.
 *
 *   node packages/ingest/scripts/upload-large.mjs <로컬파일> <키> [--content-type=...] [--immutable]
 *
 * **왜 따로 필요한가.** `R2Client.put`은 본문을 통째로 메모리에 들고 한 번에 보낸다.
 * 청크(수 MB)에는 맞지만 배경지도(수백 MB)에는 맞지 않는다. `wrangler r2 object put`은
 * 300 MiB에서 막힌다 — 실제로 729 MiB 배경지도를 올리다 거부당했다.
 *
 * 서명은 R2Client와 같은 `signRequest`를 쓴다. 서명 코드를 두 벌 두면 언젠가 어긋난다.
 *
 * 주의: 서명 헤더에 자격증명이 들어간다. 어떤 경로로도 헤더와 URL을 로그에 내지 않는다.
 */
import { createReadStream, statSync } from 'node:fs';
import { basename } from 'node:path';

import { configFromEnv, signRequest } from '../dist/index.js';

import { loadEnv } from './env.mjs';

/** 100 MiB. R2 최소 파트 크기(5 MiB)보다 넉넉하고, 파트 수를 열 개 안쪽으로 묶는다. */
const PART_SIZE = 100 * 1024 * 1024;

const send = async (config, method, key, query, body, extraHeaders = {}) => {
  const path = `/${config.bucket}/${key}`;
  const signed = signRequest(config, method, path, query, body, new Date(), extraHeaders);
  const res = await fetch(signed.url, {
    method,
    headers: signed.headers,
    ...(body === undefined ? {} : { body }),
  });
  const text = await res.text();
  if (!res.ok) {
    // 본문에 URL·자격증명이 실리지 않는다. 코드만 옮긴다.
    const code = /<Code>([^<]*)<\/Code>/.exec(text)?.[1] ?? `HTTP_${res.status}`;
    throw new Error(`${method} ${key} 실패 (${res.status} ${code})`);
  }
  return text;
};

/** 파일을 PART_SIZE 단위로 읽어 넘긴다. 통째로 메모리에 올리지 않는다. */
const parts = async function* (file) {
  let buffered = [];
  let size = 0;
  for await (const chunk of createReadStream(file, { highWaterMark: 8 * 1024 * 1024 })) {
    buffered.push(chunk);
    size += chunk.length;
    if (size >= PART_SIZE) {
      yield Buffer.concat(buffered, size);
      buffered = [];
      size = 0;
    }
  }
  if (size > 0) yield Buffer.concat(buffered, size);
};

const main = async () => {
  loadEnv();
  const args = process.argv.slice(2);
  const typeArg = args.find((a) => a.startsWith('--content-type='));
  const contentType = typeArg ? typeArg.slice('--content-type='.length) : 'application/octet-stream';
  // 이름에 날짜나 해시가 박힌 자산만 immutable로 둔다.
  //
  // **배경지도가 이것을 놓치고 있었다.** 729 MiB PMTiles에 cache-control이 없어서
  // 지도를 볼 때마다 타일 조각을 다시 검증했다. R2는 그 검증 하나하나가 Class B
  // 요청이고, 무료 한도(월 1,000만)를 가장 빨리 쓰는 것이 바로 그것이다.
  const immutable = args.includes('--immutable');
  const [file, key] = args.filter((a) => !a.startsWith('--'));
  if (!file || !key) {
    throw new Error('쓰임: upload-large.mjs <로컬파일> <키> [--content-type=...] [--immutable]');
  }

  const config = configFromEnv();
  const total = statSync(file).size;
  console.log(`${basename(file)} → ${key}`);
  console.log(`  ${(total / 1048576).toFixed(1)} MiB · 파트 ${Math.ceil(total / PART_SIZE)}개`);

  const started = await send(config, 'POST', key, 'uploads=', undefined, {
    'content-type': contentType,
    ...(immutable ? { 'cache-control': 'public, max-age=31536000, immutable' } : {}),
  });
  const uploadId = /<UploadId>([^<]*)<\/UploadId>/.exec(started)?.[1];
  if (!uploadId) throw new Error('UploadId를 받지 못했습니다');

  const etags = [];
  try {
    let n = 0;
    for await (const part of parts(file)) {
      n += 1;
      // 정규 쿼리는 **정렬된 상태**여야 서명이 맞는다. partNumber < uploadId.
      const query = `partNumber=${n}&uploadId=${encodeURIComponent(uploadId)}`;
      const res = await send(config, 'PUT', key, query, part, {
        'content-length': String(part.length),
      });
      void res;
      // ETag는 헤더로 오지만 fetch가 노출하지 않는 경우가 있어 다시 요청하지 않고
      // 파트 번호 기준으로 재조회한다 — 아래 목록 조회로 한 번에 모은다.
      console.log(`  파트 ${n} 올림 (${(part.length / 1048576).toFixed(0)} MiB)`);
    }

    const listed = await send(config, 'GET', key, `uploadId=${encodeURIComponent(uploadId)}`);
    for (const m of listed.matchAll(/<Part>[\s\S]*?<\/Part>/g)) {
      const num = /<PartNumber>(\d+)<\/PartNumber>/.exec(m[0])?.[1];
      const tag = /<ETag>([^<]*)<\/ETag>/.exec(m[0])?.[1];
      if (num && tag) etags.push({ num: Number(num), tag });
    }
    etags.sort((a, b) => a.num - b.num);
    if (etags.length !== n) throw new Error(`파트 수가 맞지 않습니다: 올린 ${n} · 확인 ${etags.length}`);

    const xml =
      '<CompleteMultipartUpload>' +
      etags.map((e) => `<Part><PartNumber>${e.num}</PartNumber><ETag>${e.tag}</ETag></Part>`).join('') +
      '</CompleteMultipartUpload>';
    const body = Buffer.from(xml, 'utf8');
    await send(config, 'POST', key, `uploadId=${encodeURIComponent(uploadId)}`, body, {
      'content-length': String(body.length),
    });
    console.log('  완료');
  } catch (error) {
    // 실패한 멀티파트를 남기면 R2에 조각이 계속 쌓인다.
    await send(config, 'DELETE', key, `uploadId=${encodeURIComponent(uploadId)}`).catch(() => {});
    throw error;
  }
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
