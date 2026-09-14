/**
 * 건물 외곽선을 법정동 단위로 굽는다 — 도로명주소 **건물 도형**(SHP) + **건물DB**.
 *
 *   node --max-old-space-size=8192 packages/ingest/scripts/build-building-shapes.mjs \
 *     <건물 도형 폴더> <건물DB 폴더> <출력 폴더> [--only=11000]
 *
 *     실거래가(법정동명|지번) ──건물DB──▶ 건물키 ──건물 도형──▶ 외곽선
 *
 * **올리지 않는다.** 이 자료는 보안각서를 쓰고 받은 것이고 국외 반출 가부를
 * 아직 묻고 있다(`Doc/전자지도-신청.html` 2절). 여기서는 굽기만 한다 —
 * 업로드 단계는 답이 온 뒤에 붙인다. 원자료도 가공물도 전부
 * 버전관리 밖(`RealDealMap/spike/juso/`)에 둔다.
 *
 * **법정동으로 쪼개는 이유.** 시군구 하나가 광진구 기준 892KB다. 상세창 하나를
 * 열자고 그것을 받게 할 수는 없다. 법정동이면 수십 KB고, 사용자가 보고 있는
 * 동네의 것만 받는다.
 *
 * **시도 하나씩 비운다.** 전국 건물 720만 동의 주소를 한 Map에 담으면 몇 GB다.
 * 시군구는 시도를 넘지 않으므로 시도 한 쌍을 처리하고 바로 내보내면 최대 사용량이
 * 가장 큰 시도 하나로 묶인다 — `build-juso-index.mjs`와 같은 이유다.
 *
 * **도형 파일과 건물DB 파일은 이름이 서로 다르다.** 도형은 시도 코드가 붙은
 * `...TL_SGCO_RNADR_MST.11000.shp`이고 건물DB는 `build_seoul.txt`다. 이름 대응표를
 * 손으로 적는 대신 **파일이 실제로 담고 있는 시군구코드의 앞 두 자리**로 잇는다 —
 * 표를 적어 두면 시도가 통합·분리될 때마다 조용히 어긋난다(광주·전남, 인천).
 */
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import { gunzipSync, gzipSync } from 'node:zlib';

import {
  dongShapes,
  outlinesOf,
  parseJusoRow,
  readShapefile,
  shapeBuildingKey,
  shapeIndex,
} from '@realdealmap/ingest';

/** 도로명주소 배포본은 CP949다. 실제 파일로 확인했다(202608 전체분). */
const decoder = new TextDecoder('euc-kr');

const readLines = (path) => decoder.decode(readFileSync(path)).split('\r\n');

/** `build_seoul.txt` → `seoul` */
const regionOf = (file) => file.replace(/^(build|jibun)_/, '').replace(/\.txt$/, '');

/** `Total.JUSURB.20260901.TL_SGCO_RNADR_MST.11000.shp` → `20260901` */
const sourceOf = (file) => file.match(/\.(\d{8})\./)?.[1] ?? 'unknown';

/** 파일이 담고 있는 시도(코드 앞 두 자리). 첫 유효 행으로 정한다. */
const sidoOfBuildFile = (path) => {
  for (const line of readLines(path)) {
    const row = parseJusoRow(line, 'building');
    if (row !== null) return row.bjdCd.slice(0, 2);
  }
  return null;
};

/** 도형 파일이 담고 있는 시도. 첫 레코드의 시군구코드로 정한다. */
const sidoOfShapeFile = (shp, dbf) => {
  for (const f of readShapefile(shp, dbf)) {
    const key = shapeBuildingKey(f.attributes);
    if (key !== null) return key.sggCd.slice(0, 2);
  }
  return null;
};

/** 건물DB에서 `건물키 → 주소들`. 한 건물에 지번이 여럿 딸린다(관련지번). */
const readAddresses = (dir, files, region) => {
  const addrs = new Map();
  let rows = 0;
  for (const [prefix, table] of [
    ['build', 'building'],
    // 관련지번이 없으면 대표지번이 아닌 지번으로 거래된 건이 통째로 빠진다.
    ['jibun', 'jibun'],
  ]) {
    const file = `${prefix}_${region}.txt`;
    if (!files.includes(file)) continue;
    for (const line of readLines(join(dir, file))) {
      if (line === '') continue;
      const row = parseJusoRow(line, table);
      if (row === null) continue;
      rows += 1;
      const list = addrs.get(row.buildingKey);
      if (list === undefined) addrs.set(row.buildingKey, [row]);
      else list.push(row);
    }
  }
  return { addrs, rows };
};

/**
 * 도형을 법정동 통에 담는다.
 *
 * 한 건물이 여러 지번에 딸리므로 **모양은 한 번만 담고 지번은 번호로 가리킨다.**
 * 그대로 복사하면 같은 건물이 파일 안에 여러 번 들어간다.
 */
const addToDong = (dongs, addr, buildingKey, outlines) => {
  let dong = dongs.get(addr.bjdCd);
  if (dong === undefined) {
    dong = { umdNm: addr.umdNm, shapes: [], ids: new Map(), buildings: new Map() };
    dongs.set(addr.bjdCd, dong);
  }
  let ids = dong.ids.get(buildingKey);
  if (ids === undefined) {
    ids = outlines.map((ring) => dong.shapes.push(ring) - 1);
    dong.ids.set(buildingKey, ids);
  }
  const at = dong.buildings.get(addr.jibun);
  if (at === undefined) dong.buildings.set(addr.jibun, [...ids]);
  else for (const id of ids) if (!at.includes(id)) at.push(id);
};

/**
 * 조각 하나가 넘지 않을 크기(gzip 뒤).
 *
 * 상세창 하나를 열 때 받는 양이다. 쪼개지 않으면 서울 신림동이 873KB였다.
 */
const PART_LIMIT_BYTES = 150 * 1024;

/** JSON이 gzip으로 줄어드는 비율. 실측 3.9배 — 예산을 잡는 데만 쓴다. */
const GZIP_RATIO = 3.9;

/**
 * 지번을 사전 순으로 줄 세워 조각으로 끊는다.
 *
 * 사전 순인 것은 앱이 셈을 하지 않게 하기 위해서다(`shapes.ts`의 `partFor`).
 * 크기는 좌표 개수로 어림한다 — 한 조각이 상한을 조금 넘는 것은
 * 상관없고, **경계가 양쪽에서 같기만** 하면 된다.
 */
const splitDong = (dong) => {
  const budget = PART_LIMIT_BYTES * GZIP_RATIO;
  const parts = [];
  let current = null;
  for (const jibun of [...dong.buildings.keys()].sort()) {
    const ids = dong.buildings.get(jibun);
    // 좌표 하나가 대략 11바이트(`127.071234,`)다.
    const cost = ids.reduce((sum, id) => sum + dong.shapes[id].length * 11, 0) + jibun.length + 8;
    if (current === null || (current.bytes + cost > budget && current.jibuns.length > 0)) {
      current = { jibuns: [], bytes: 0 };
      parts.push(current);
    }
    current.jibuns.push(jibun);
    current.bytes += cost;
  }
  return parts;
};

/** 조각 하나의 알맹이. 조각에 든 모양만 추려 번호를 다시 매긴다. */
const partContent = (dong, jibuns) => {
  const shapes = [];
  const moved = new Map();
  const buildings = {};
  for (const jibun of jibuns) {
    buildings[jibun] = dong.buildings.get(jibun).map((id) => {
      let at = moved.get(id);
      if (at === undefined) {
        at = shapes.push(dong.shapes[id]) - 1;
        moved.set(id, at);
      }
      return at;
    });
  }
  return { shapes, buildings };
};

/**
 * 앞선 시도가 쓴 같은 법정동을 읽어 지금 것에 합친다.
 *
 * **시도 파일에는 남의 시군구가 몇 줄씩 섞여 있다.** 서울 파일에서 시군구 28개가
 * 나왔는데 서울은 25개다. 그냥 덮어쓰면 **뒤에 처리한 시도의 유령 몇 줄이
 * 앞서 제대로 구운 법정동을 통째로 지운다** — 목차와 파일이 서로 맞아떨어져
 * 있어서 검증으로도 안 잡히고, 그 동네 건물만 조용히 사라진다.
 * 건물DB 색인에서 하남시 14,072개가 1개로 줄었던 그 실패다.
 *
 * 같은 모양이 양쪽에 있으면 한 번만 남긴다.
 */
const mergePrevious = (dir, entry, dong) => {
  const seen = new Map();
  dong.shapes.forEach((ring, at) => seen.set(JSON.stringify(ring), at));

  for (const part of entry.parts) {
    const path = join(dir, part.file);
    if (!existsSync(path)) continue;
    const body = JSON.parse(gunzipSync(readFileSync(path)));
    const moved = new Map();
    for (const [jibun, ids] of Object.entries(body.buildings)) {
      const list = dong.buildings.get(jibun) ?? [];
      for (const id of ids) {
        let at = moved.get(id);
        if (at === undefined) {
          const ring = body.shapes[id];
          const key = JSON.stringify(ring);
          at = seen.get(key);
          if (at === undefined) {
            at = dong.shapes.push(ring) - 1;
            seen.set(key, at);
          }
          moved.set(id, at);
        }
        if (!list.includes(at)) list.push(at);
      }
      dong.buildings.set(jibun, list);
    }
  }
  return dong;
};

/** 시군구별로 나눠 쓴다. 같은 실행에서 이미 쓴 시군구면 목차를 합친다. */
const writeRegions = (dongs, out, source, written) => {
  const bySgg = new Map();
  for (const [bjdCd, dong] of dongs) {
    const sggCd = bjdCd.slice(0, 5);
    let bucket = bySgg.get(sggCd);
    if (bucket === undefined) bySgg.set(sggCd, (bucket = new Map()));
    bucket.set(bjdCd, dong);
  }

  let bytes = 0;
  let files = 0;
  for (const [sggCd, bucket] of bySgg) {
    const dir = join(out, sggCd);
    mkdirSync(dir, { recursive: true });
    const indexPath = join(dir, 'index.json');
    const before =
      written.has(sggCd) && existsSync(indexPath)
        ? JSON.parse(readFileSync(indexPath, 'utf8')).dongs
        : {};

    const entries = {};
    for (const [bjdCd, dong] of bucket) {
      const previous = before[dong.umdNm];
      if (previous !== undefined) {
        mergePrevious(dir, previous, dong);
        // 옛 조각을 다시 쓰는 것이므로 셈에서 뺀다. 안 그러면 로그의 파일 수가
        // 디스크에 있는 것보다 많아진다.
        files -= previous.parts.length;
        bytes -= previous.bytes;
      }
      const parts = [];
      let dongBytes = 0;
      splitDong(dong).forEach((part, at) => {
        const content = partContent(dong, part.jibuns);
        const payload = dongShapes(
          { sggCd, bjdCd, umdNm: dong.umdNm, source },
          content.shapes,
          content.buildings,
        );
        const file = `${bjdCd}.${at + 1}.json.gz`;
        writeFileSync(join(dir, file), gzipSync(Buffer.from(JSON.stringify(payload)), { level: 9 }));
        const size = statSync(join(dir, file)).size;
        parts.push({
          file,
          from: part.jibuns[0],
          to: part.jibuns[part.jibuns.length - 1],
          buildings: part.jibuns.length,
          bytes: size,
        });
        dongBytes += size;
        files += 1;
      });
      // 합친 결과가 조각 수를 줄일 수 있다. 남은 옛 조각을 지우지 않으면
      // 아무도 가리키지 않는 파일이 배포본에 섞여 올라간다.
      if (previous !== undefined) {
        const kept = new Set(parts.map((p) => p.file));
        for (const old of previous.parts) if (!kept.has(old.file)) rmSync(join(dir, old.file));
      }
      entries[dong.umdNm] = { bjdCd, buildings: dong.buildings.size, bytes: dongBytes, parts };
      bytes += dongBytes;
    }

    writeFileSync(indexPath, JSON.stringify(shapeIndex({ sggCd, source }, { ...before, ...entries })));
    written.add(sggCd);
  }
  return { regions: bySgg.size, files, bytes };
};

const main = () => {
  const args = process.argv.slice(2);
  const only = args.find((a) => a.startsWith('--only='))?.slice('--only='.length);
  const [shapeDir, jusoDir, out] = args.filter((a) => !a.startsWith('--'));
  if (!shapeDir || !jusoDir || !out) {
    throw new Error('쓰임: build-building-shapes.mjs <건물 도형 폴더> <건물DB 폴더> <출력 폴더>');
  }
  mkdirSync(out, { recursive: true });

  const shapeFiles = readdirSync(shapeDir)
    .filter((f) => f.includes('RNADR_MST') && f.endsWith('.shp'))
    .filter((f) => only === undefined || f.includes(only))
    .sort();
  if (shapeFiles.length === 0) throw new Error(`${shapeDir}에 *RNADR_MST*.shp가 없습니다`);

  const jusoFiles = readdirSync(jusoDir);
  const regions = [...new Set(jusoFiles.filter((f) => f.startsWith('build_')).map(regionOf))];
  if (regions.length === 0) throw new Error(`${jusoDir}에 build_*.txt가 없습니다`);

  const sidoToRegion = new Map();
  for (const region of regions) {
    const sido = sidoOfBuildFile(join(jusoDir, `build_${region}.txt`));
    if (sido !== null && !sidoToRegion.has(sido)) sidoToRegion.set(sido, region);
  }

  const totals = { shapes: 0, joined: 0, noKey: 0, noAddress: 0, files: 0, bytes: 0, regions: 0 };
  const written = new Set();

  for (const file of shapeFiles) {
    const shp = readFileSync(join(shapeDir, file));
    const dbf = readFileSync(join(shapeDir, file.replace(/\.shp$/, '.dbf')));
    const source = sourceOf(file);
    const sido = sidoOfShapeFile(shp, dbf);
    const region = sido === null ? undefined : sidoToRegion.get(sido);
    if (region === undefined) {
      console.log(`${file} — 짝이 될 건물DB를 못 찾았습니다 (시도 ${sido}). 건너뜁니다.`);
      continue;
    }

    const { addrs, rows } = readAddresses(jusoDir, jusoFiles, region);
    const dongs = new Map();
    const stat = { shapes: 0, joined: 0, noKey: 0, noAddress: 0 };

    for (const f of readShapefile(shp, dbf)) {
      stat.shapes += 1;
      const key = shapeBuildingKey(f.attributes);
      if (key === null) {
        stat.noKey += 1;
        continue;
      }
      const list = addrs.get(key.buildingKey);
      if (list === undefined) {
        stat.noAddress += 1;
        continue;
      }
      stat.joined += 1;
      const outlines = outlinesOf(f.polygons);
      if (outlines.length === 0) continue;
      for (const addr of list) addToDong(dongs, addr, key.buildingKey, outlines);
    }

    const wrote = writeRegions(dongs, out, source, written);
    totals.shapes += stat.shapes;
    totals.joined += stat.joined;
    totals.noKey += stat.noKey;
    totals.noAddress += stat.noAddress;
    totals.files += wrote.files;
    totals.bytes += wrote.bytes;

    const rate = stat.shapes === 0 ? 0 : (stat.joined / stat.shapes) * 100;
    console.log(
      `${region.padEnd(18)} 도형 ${stat.shapes.toLocaleString().padStart(9)} · ` +
        `주소 ${rows.toLocaleString().padStart(9)} · ` +
        `이음 ${rate.toFixed(1).padStart(5)}% · ` +
        `시군구 ${String(wrote.regions).padStart(3)} · 법정동 ${String(wrote.files).padStart(4)} · ` +
        `${(wrote.bytes / 1024 / 1024).toFixed(1)}MB`,
    );
  }

  totals.regions = written.size;
  const joinRate = totals.shapes === 0 ? 0 : (totals.joined / totals.shapes) * 100;
  console.log(
    `\n합계 — 도형 ${totals.shapes.toLocaleString()} · 이음 ${joinRate.toFixed(1)}% ` +
      `(열쇠 못 만듦 ${totals.noKey.toLocaleString()} · 주소 없음 ${totals.noAddress.toLocaleString()})`,
  );
  console.log(
    `시군구 ${totals.regions} · 법정동 파일 ${totals.files.toLocaleString()} · ` +
      `${(totals.bytes / 1024 / 1024).toFixed(1)}MB (gzip)`,
  );
};

main();
