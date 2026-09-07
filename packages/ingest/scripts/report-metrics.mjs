/**
 * 운영 지표를 R2에서 읽어 마크다운으로 낸다 (T6.5).
 *
 *   node packages/ingest/scripts/report-metrics.mjs --months=12
 *
 * **지표를 따로 쌓지 않는다.** 텔레메트리 저장소를 두면 그것이 진실인 척하다가
 * 실제 R2와 어긋나는 날이 온다. 여기서 재는 값은 전부 지금 R2에 있는 것에서
 * 계산한다 — 배포 상태, 좌표 채움 비율, 신선도, 저장 용량.
 *
 * 여기서 잴 수 없는 것은 적지 않는다:
 *   · 배치 성공률 — GitHub Actions API에 있다. 워크플로가 붙인다.
 *   · 캐시 적중률 — Cloudflare 쪽이고, 사용자 지정 도메인 전환(T6.3) 뒤에 잴 수 있다.
 *   · 해시 실패율 — 수집 시점에만 관측된다. 배포 로그가 남긴다.
 */
import { queryableRegions } from '@realdealmap/shared';

import { configFromEnv, manifestKey, R2Client, readIndex, recentPeriods } from '../dist/index.js';

import { loadEnv } from './env.mjs';

const argOf = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};

const pct = (part, whole) => (whole === 0 ? '—' : `${((part / whole) * 100).toFixed(1)}%`);
const mib = (bytes) => `${(bytes / 1024 / 1024).toFixed(1)} MiB`;

/** 사람이 읽는 경과 시간. "3시간 전"이 "2026-09-08T02:26Z"보다 빨리 읽힌다. */
const ago = (iso, now) => {
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return '알 수 없음';
  const minutes = Math.floor((now - then) / 60000);
  if (minutes < 60) return `${minutes}분 전`;
  if (minutes < 60 * 24) return `${Math.floor(minutes / 60)}시간 전`;
  return `${Math.floor(minutes / 1440)}일 전`;
};

const main = async () => {
  loadEnv();
  const months = Number(argOf('months', '12'));
  const needed = new Set(recentPeriods(new Date(), months));
  const now = Date.now();

  const r2 = new R2Client(configFromEnv());
  const all = queryableRegions();

  // 적재 상태 — 매니페스트에서 직접 센다.
  let complete = 0;
  let partial = 0;
  let absent = 0;
  let records = 0;
  const stale = [];
  const published = [];

  for (const region of all) {
    const raw = await r2.get(manifestKey(region.sggCd));
    if (raw === null) {
      absent += 1;
      continue;
    }
    let manifest;
    try {
      manifest = JSON.parse(new TextDecoder().decode(raw));
    } catch {
      absent += 1;
      continue;
    }

    const have = new Set(manifest.files.map((f) => f.month));
    const missing = [...needed].filter((m) => !have.has(m));
    if (missing.length === 0) complete += 1;
    else partial += 1;
    published.push(region.sggCd);

    records += manifest.files.reduce((sum, f) => sum + f.records, 0);

    // TTL이 1시간인데 하루가 넘었으면 갱신 경로가 그 지역에서 멎은 것이다.
    const age = now - Date.parse(manifest.refreshedAt);
    if (age > 24 * 3600 * 1000) {
      stale.push({ sggCd: region.sggCd, name: region.name, at: manifest.refreshedAt });
    }
  }

  // 좌표 채움 — 색인이 지역마다 located/records를 들고 있다.
  const index = await readIndex(r2);
  const located = index.regions.reduce((a, r) => a + r.located, 0);
  // 분모는 records가 아니라 sampled다. records는 매니페스트 전체 건수인데
  // located는 마지막 회차에 훑어 본 것만 세므로, 나누면 채움률이 낮게 나온다.
  const indexed = index.regions.reduce((a, r) => a + (r.sampled ?? r.records), 0);

  // 색인에 없는 지역은 앱에서 **존재하지 않는다.** 매니페스트가 있어도 앱은
  // 색인을 보고 지역 목록을 만들기 때문이다. 배포는 됐는데 안 보이는 상태라
  // 로그만 봐서는 정상으로 읽힌다.
  const inIndex = new Set(index.regions.map((r) => r.sggCd));
  const invisible = published.filter((code) => !inIndex.has(code));

  // 저장 용량 — 청크와 매니페스트를 합쳐 전부 훑는다.
  let bytes = 0;
  let objects = 0;
  for (const prefix of ['v1/']) {
    let token;
    do {
      const page = await r2.list(prefix, token);
      objects += page.keys.length;
      bytes += page.bytes ?? 0;
      token = page.nextToken;
    } while (token);
  }

  const lines = [
    '## 운영 지표',
    '',
    `기준 ${new Date(now).toISOString()} · 보관 ${months}개월`,
    '',
    '### 적재',
    '',
    '| 항목 | 값 |',
    '| --- | --- |',
    `| 전체 시군구 | ${all.length} |`,
    `| ${months}개월 완료 | ${complete} (${pct(complete, all.length)}) |`,
    `| 일부만 | ${partial} |`,
    `| 없음 | ${absent} |`,
    `| 총 거래 | ${records.toLocaleString()}건 |`,
    '',
    '### 색인',
    '',
    '| 항목 | 값 |',
    '| --- | --- |',
    `| 배포된 지역 | ${published.length} |`,
    `| 색인에 실린 지역 | ${index.regions.length} |`,
    `| 색인에 없는 지역 | ${invisible.length}${invisible.length ? ` — ${invisible.join(', ')}` : ''} |`,
    '',
    '색인에 없는 지역은 매니페스트가 있어도 앱에서 고를 수 없다.',
    '',
    '### 좌표',
    '',
    '| 항목 | 값 |',
    '| --- | --- |',
    `| 좌표 있음 | ${located.toLocaleString()} / ${indexed.toLocaleString()} (${pct(located, indexed)}) |`,
    `| 좌표 미확인 | ${(indexed - located).toLocaleString()} (${pct(indexed - located, indexed)}) |`,
    '',
    '좌표가 없는 거래도 목록과 상세에는 나온다. 지도에만 안 찍힌다.',
    '',
    '### 저장',
    '',
    '| 항목 | 값 |',
    '| --- | --- |',
    `| 객체 수 | ${objects.toLocaleString()} |`,
    `| 용량 | ${mib(bytes)} (무료 10 GB의 ${((bytes / (10 * 1024 ** 3)) * 100).toFixed(2)}%) |`,
    '',
    '### 신선도',
    '',
  ];

  if (stale.length === 0) {
    lines.push('하루가 넘도록 갱신되지 않은 지역이 없다.');
  } else {
    lines.push(`하루가 넘은 지역 ${stale.length}개 — 갱신 경로가 멎었는지 본다.`, '');
    lines.push('| 시군구 | 마지막 갱신 |', '| --- | --- |');
    for (const s of stale.slice(0, 20)) {
      lines.push(`| ${s.sggCd} ${s.name} | ${ago(s.at, now)} |`);
    }
    if (stale.length > 20) lines.push(`| … | 외 ${stale.length - 20}개 |`);
  }

  console.log(lines.join('\n'));
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
