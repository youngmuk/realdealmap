/**
 * 좌표 사전을 만든다 — 도로명주소 두 파일을 이어 `법정동명|지번 → 좌표`로.
 *
 *   node --max-old-space-size=8192 packages/ingest/scripts/build-geo-dict.mjs \
 *     <위치정보요약DB 폴더> <건물DB 색인 폴더> <출력 폴더>
 *
 * 색인 폴더는 `build-juso-index.mjs`가 만든 것이다.
 *
 *     실거래가(법정동명|지번) ──색인──▶ 건물키 ──위치DB──▶ (x, y) ──utmk──▶ 위경도
 *
 * **왜 시도 파일 하나씩 비우나.** 전국 800만 점을 한 Map에 담으면 몇 GB가 된다.
 * 시군구는 시도를 넘지 않으므로 시도 하나를 처리하고 바로 내보내면 최대 사용량이
 * 가장 큰 시도(경기) 하나로 묶인다. `build-juso-index.mjs`와 같은 이유다.
 *
 * **법정동 중심점도 같이 만든다.** 단독다가구 매매와 토지 매매는 지번이
 * `4**`처럼 가려져 오고, 단독 전월세는 지번 필드 자체가 없다. 실측으로
 * 온전한 지번이 한 건도 없었다(R-8). 이 건들의 사전 열쇠는 `법정동명|`이 되므로,
 * 그 법정동에 속한 건물 좌표의 중앙값을 그 열쇠에 넣어 둔다. 앱은 이런 건을
 * 낱개 핀이 아니라 **옅은 원**으로 그린다 — 정밀도 등급이 따로 붙기 때문이다.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  addEntrcRows,
  addSplitRegions,
  GEO_VERSION,
  utmkToWgs84,
  UtmkError,
} from '@realdealmap/ingest';

/** 도로명주소 배포본은 CP949다. 실제 파일로 확인했다(202602 전체분). */
const decoder = new TextDecoder('euc-kr');

const readLines = (path) => decoder.decode(readFileSync(path)).split('\r\n');

/** `entrc_seoul.txt` → `seoul` */
const regionOf = (file) => file.replace(/^entrc_/, '').replace(/\.txt$/, '');

/**
 * 성분별 중앙값.
 *
 * 진짜 기하 중앙값은 아니지만 법정동 하나 안에서 대표점을 고르는 데는 충분하고,
 * 평균과 달리 **동떨어진 한 점에 끌려가지 않는다**. 법정동은 강을 건너거나
 * 산을 넘기도 해서 그 성질이 필요하다.
 */
const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

const round6 = (value) => Math.round(value * 1e6) / 1e6;

/**
 * 한 시군구의 사전을 만든다.
 *
 * @param table 색인 — `법정동명|지번 → 건물키`
 * @param points 좌표 표 — `건물키 → [x, y]`
 */
const buildEntries = (table, points, today) => {
  const entries = {};
  /** 법정동명 → 그 동에서 나온 좌표들. 중심점을 내는 데 쓴다 */
  const byUmd = new Map();
  const stat = { located: 0, noPoint: 0, offMap: 0, centers: 0 };

  for (const [geoKey, buildingKey] of Object.entries(table)) {
    const xy = points.get(buildingKey);
    if (xy === undefined) {
      stat.noPoint += 1;
      continue;
    }

    let latLng;
    try {
      latLng = utmkToWgs84(xy[0], xy[1]);
    } catch (error) {
      // 한반도 밖은 좌표계를 잘못 읽은 것이다. 한두 점 때문에 시군구 전체를
      // 버릴 이유는 없지만, 조용히 넘기면 안 되므로 세어서 밖으로 낸다.
      if (!(error instanceof UtmkError)) throw error;
      stat.offMap += 1;
      continue;
    }

    entries[geoKey] = { ...latLng, source: 'address', checkedOn: today };
    stat.located += 1;

    const umdNm = geoKey.slice(0, geoKey.indexOf('|'));
    let bucket = byUmd.get(umdNm);
    if (bucket === undefined) {
      bucket = { lat: [], lng: [] };
      byUmd.set(umdNm, bucket);
    }
    bucket.lat.push(latLng.lat);
    bucket.lng.push(latLng.lng);
  }

  for (const [umdNm, bucket] of byUmd) {
    // 지번이 가려진 건들의 열쇠다. 이미 있으면 건드리지 않는다 —
    // 실제로 `법정동명|` 모양의 지번이 색인에 있을 이유는 없지만,
    // 있다면 그쪽이 더 정확한 값이다.
    const key = `${umdNm}|`;
    if (entries[key] !== undefined) continue;
    entries[key] = {
      lat: round6(median(bucket.lat)),
      lng: round6(median(bucket.lng)),
      source: 'address',
      checkedOn: today,
    };
    stat.centers += 1;
  }

  return { entries, stat };
};

const main = () => {
  const [src, indexDir, out] = process.argv.slice(2);
  if (!src || !indexDir || !out) {
    throw new Error('쓰임: build-geo-dict.mjs <위치DB 폴더> <색인 폴더> <출력 폴더>');
  }
  mkdirSync(out, { recursive: true });

  const today = new Date().toISOString().slice(0, 10);
  const generatedAt = new Date().toISOString();

  const files = readdirSync(src).filter((f) => f.startsWith('entrc_') && f.endsWith('.txt'));
  if (files.length === 0) throw new Error(`${src}에 entrc_*.txt가 없습니다`);

  const totals = {
    points: 0, skipped: 0, collisions: 0,
    regions: 0, located: 0, noPoint: 0, offMap: 0, centers: 0, noIndex: 0,
    ambiguous: 0, splitFilled: [],
  };
  /**
   * 이번 실행에서 이미 사전을 쓴 시군구.
   *
   * 시도 파일에 남의 시군구가 몇 줄씩 섞여 있다. 그냥 덮어쓰면 나중에 처리한
   * 시도의 유령 한 줄이 앞서 만든 사전을 통째로 지운다 — 건물DB 색인에서
   * 하남시 14,072개가 1개로 줄었던 그 실패다. 집계는 멀쩡했고 오류도 없었다.
   */
  const written = new Set();

  for (const file of files.sort()) {
    const points = new Map();
    const report = addEntrcRows(points, readLines(join(src, file)));
    // 갈라진 구는 옛 구에서 만들어 낸다. 안 하면 인천 4개 구가 통째로 빈다.
    const split = addSplitRegions(points);
    totals.splitFilled.push(...split.filled);
    totals.ambiguous += split.ambiguous;

    let located = 0;
    let regions = 0;
    for (const [sggCd, bucket] of points) {
      const indexPath = join(indexDir, `${sggCd}.json`);
      if (!existsSync(indexPath)) {
        totals.noIndex += 1;
        continue;
      }
      const table = JSON.parse(readFileSync(indexPath, 'utf8'));
      const { entries, stat } = buildEntries(table, bucket, today);

      const path = join(out, `${sggCd}.json`);
      const merged = written.has(sggCd) && existsSync(path)
        ? { ...JSON.parse(readFileSync(path, 'utf8')).entries, ...entries }
        : entries;
      writeFileSync(
        path,
        JSON.stringify({ version: GEO_VERSION, sggCd, generatedAt, entries: merged }),
      );
      if (!written.has(sggCd)) {
        totals.regions += 1;
        regions += 1;
      }
      written.add(sggCd);

      located += stat.located;
      totals.located += stat.located;
      totals.noPoint += stat.noPoint;
      totals.offMap += stat.offMap;
      totals.centers += stat.centers;
    }

    console.log(
      `${regionOf(file).padEnd(12)} 시군구 ${String(regions).padStart(3)} · ` +
        `좌표 ${report.points.toLocaleString().padStart(9)} · ` +
        `버림 ${report.skipped.toLocaleString().padStart(6)} · ` +
        `사전 항목 ${located.toLocaleString().padStart(9)}`,
    );
    totals.points += report.points;
    totals.skipped += report.skipped;
    totals.collisions += report.collisions;
  }

  const want = totals.located + totals.noPoint;
  console.log(
    `\n합계 — 시군구 ${totals.regions} · 좌표 ${totals.points.toLocaleString()} · ` +
      `버림 ${totals.skipped.toLocaleString()} · 같은건물 다른좌표 ${totals.collisions.toLocaleString()}`,
  );
  console.log(
    `색인 열쇠 ${want.toLocaleString()} 중 좌표 붙음 ${totals.located.toLocaleString()} ` +
      `(${((totals.located / want) * 100).toFixed(1)}%) · 좌표 없음 ${totals.noPoint.toLocaleString()} · ` +
      `한반도 밖 ${totals.offMap.toLocaleString()}`,
  );
  console.log(`법정동 중심점 ${totals.centers.toLocaleString()}개 (지번이 가려진 거래용)`);
  if (totals.splitFilled.length > 0) {
    console.log(
      `갈라진 구를 옛 구에서 채웠다 — ${totals.splitFilled.join(', ')}` +
        `${totals.ambiguous > 0 ? ` · 도로명번호가 겹쳐 버린 건물 ${totals.ambiguous}` : ''}`,
    );
  }
  if (totals.noIndex > 0) console.log(`색인이 없어 건너뛴 시군구 ${totals.noIndex}개`);

  // **색인에는 있는데 사전이 안 나온 시군구를 잡는다.**
  // 처음 돌렸을 때 인천 4개 구가 정확히 이렇게 빠졌다. 좌표 표에 그 코드가
  // 아예 없으니 반복문이 돌지 않았고, 세는 곳도 없어 로그가 멀쩡했다.
  // 합계(99.2%)도 그 4개를 분모에 넣지 않아 좋아 보였다.
  const missing = readdirSync(indexDir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => f.slice(0, -'.json'.length))
    .filter((sggCd) => !written.has(sggCd));
  if (missing.length > 0) {
    throw new Error(
      `색인에 있는데 사전이 안 나온 시군구 ${missing.length}개: ${missing.join(', ')}. ` +
        '두 파일의 시군구 코드 체계가 어긋났을 수 있습니다.',
    );
  }

  // 한반도 밖이 몇 점 나오는 것은 원천의 잡음이지만, 많아지면 열을 바꿔 읽은 것이다.
  if (totals.offMap > totals.located * 0.001) {
    throw new Error(`한반도 밖 좌표가 0.1%를 넘습니다 (${totals.offMap}). 열 배치를 보세요.`);
  }
  if (totals.collisions > 0) {
    console.log('\n주의: 한 건물에 좌표가 여럿입니다. 배포본 형식이 바뀌었는지 보세요.');
  }
};

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
