/**
 * 한 지역을 실제로 수집해 청크까지 만들어 보는 실행기 (T2.1~T2.7 관통 확인).
 *
 *   node packages/ingest/scripts/run-region.mjs 11110 202608
 *   node packages/ingest/scripts/run-region.mjs 11110 202608 --write
 *
 * `--write`를 주면 청크를 `packages/ingest/out/`에 저장한다. R2 업로드는 하지 않는다.
 * 주의: 요청 URL에는 serviceKey가 들어간다. 어떤 경우에도 URL 전체를 출력하지 않는다.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  buildChunk,
  chunkObjectKey,
  datasetKeys,
  MolitClient,
  normalizeAll,
} from '../dist/index.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '../../..');
const OUT_DIR = resolve(HERE, '../out');

const readServiceKey = () => {
  const raw = readFileSync(resolve(ROOT, '.env'), 'utf8');
  const key = raw.match(/^DATA_GO_KR_SERVICE_KEY=(.*)$/m)?.[1]?.trim();
  if (!key) throw new Error('.env의 DATA_GO_KR_SERVICE_KEY가 비어 있습니다.');
  return key;
};

const pad = (value, width) => String(value).padStart(width);

const main = async () => {
  const [sggCd = '11110', period = '202608'] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  const write = process.argv.includes('--write');

  const client = new MolitClient({ serviceKey: readServiceKey() });
  const resolved = client.resolveSggCd(sggCd);
  if (resolved !== sggCd) console.log(`시군구 코드 보정: ${sggCd} → ${resolved}`);
  console.log(`지역=${resolved} 계약월=${period}\n`);

  let totalRecords = 0;
  let totalBytes = 0;
  let issues = 0;

  for (const key of datasetKeys()) {
    const fetched = await client.fetchAll(key, resolved, period);
    const { transactions, failures } = normalizeAll(key, fetched.items);
    const chunk = buildChunk(resolved, key, period, transactions);

    totalRecords += chunk.payload.count;
    totalBytes += chunk.bytes.byteLength;

    const precisions = new Map();
    for (const record of chunk.payload.records) {
      precisions.set(record.precision, (precisions.get(record.precision) ?? 0) + 1);
    }
    const mix = [...precisions.entries()].map(([p, n]) => `${p}:${n}`).join(' ') || '-';

    console.log(
      `${key.padEnd(16)} total=${pad(fetched.totalCount, 5)} pages=${fetched.pages} ` +
        `records=${pad(chunk.payload.count, 5)} gzip=${pad(chunk.bytes.byteLength, 6)}B  ${mix}`,
    );

    if (failures.length > 0) {
      issues += 1;
      console.log(`  ! 정규화 실패 ${failures.length}건 — ${failures[0].message}`);
    }
    if (fetched.drift.unknown.length > 0 || fetched.drift.missing.length > 0) {
      issues += 1;
      console.log(
        `  ! 스키마 변화 추가=[${fetched.drift.unknown.join(',')}] 누락=[${fetched.drift.missing.join(',')}]`,
      );
    }
    if (write) {
      const objectKey = chunkObjectKey(chunk);
      const target = resolve(OUT_DIR, objectKey);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, chunk.bytes);
    }
  }

  console.log(
    `\n합계 레코드=${totalRecords} gzip=${(totalBytes / 1024).toFixed(1)}KB ` +
      `호출=${datasetKeys().reduce((sum, k) => sum + client.usage(k), 0)} 이슈=${issues}`,
  );
  if (write) console.log(`청크 저장 위치: packages/ingest/out/`);
  process.exitCode = issues > 0 ? 1 : 0;
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
