/**
 * 구운 건물 외곽선을 **올리기 전에** 검사한다.
 *
 *   node packages/ingest/scripts/verify-building-shapes.mjs <출력 폴더>
 *
 * **왜 따로 검사하나.** 이 자료가 틀리면 상세창이 남의 건물을 그린다. 좌표도
 * 그림도 각각은 멀쩡해 보여서 화면만 봐서는 잡히지 않고, 사용자는 그것을
 * 자기가 누른 건물이라고 믿는다. 그래서 앱이 실제로 밟는 길을 그대로 밟아 본다 —
 * 목차에서 조각을 고르고, 그 조각을 열고, 지번이 가리키는 모양이 있는지 본다.
 *
 * 실제로 한 번 잡았다. 시도 파일에 섞인 남의 시군구를 덮어쓰던 때
 * 로그가 센 파일 수와 디스크에 남은 수가 10개 어긋났다.
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { gunzipSync } from 'node:zlib';

import { partFor, SHAPE_SCHEMA_VERSION } from '@realdealmap/ingest';

/** 조각마다 첫·중간·끝 지번을 뽑아 목차와 맞춰 본다. 전부 보면 너무 느리다. */
const sampleJibuns = (jibuns) => {
  if (jibuns.length === 0) return [];
  const picked = new Set([jibuns[0], jibuns[jibuns.length >> 1], jibuns[jibuns.length - 1]]);
  return [...picked];
};

const main = () => {
  const [root] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  if (!root) throw new Error('쓰임: verify-building-shapes.mjs <출력 폴더>');

  const problems = [];
  const stat = { regions: 0, dongs: 0, parts: 0, buildings: 0, shapes: 0, bytes: 0, checked: 0 };
  const sizes = [];

  const regions = readdirSync(root).filter((name) =>
    statSync(join(root, name)).isDirectory(),
  );
  if (regions.length === 0) throw new Error(`${root}에 시군구 폴더가 없습니다`);

  for (const sggCd of regions.sort()) {
    const dir = join(root, sggCd);
    const indexPath = join(dir, 'index.json');
    if (!existsSync(indexPath)) {
      problems.push(`${sggCd} 목차가 없다`);
      continue;
    }
    const index = JSON.parse(readFileSync(indexPath, 'utf8'));
    if (index.schemaVersion !== SHAPE_SCHEMA_VERSION) {
      problems.push(`${sggCd} 목차의 판이 ${index.schemaVersion}이다`);
      continue;
    }
    if (index.sggCd !== sggCd) problems.push(`${sggCd} 목차가 ${index.sggCd}라고 적혀 있다`);
    if (!index.attribution) problems.push(`${sggCd} 목차에 출처 표시가 없다`);
    stat.regions += 1;

    /** 목차가 가리키는 파일들. 여기 없는 `.gz`는 아무도 안 읽는 찌꺼기다 */
    const referenced = new Set(['index.json']);

    for (const [umdNm, dong] of Object.entries(index.dongs ?? {})) {
      stat.dongs += 1;
      if (!Array.isArray(dong.parts) || dong.parts.length === 0) {
        problems.push(`${sggCd} ${umdNm} 조각이 없다`);
        continue;
      }

      let dongBuildings = 0;
      for (const part of dong.parts) {
        stat.parts += 1;
        referenced.add(part.file);
        const path = join(dir, part.file);
        if (!existsSync(path)) {
          problems.push(`${sggCd} ${umdNm} ${part.file}이 없다`);
          continue;
        }
        const size = statSync(path).size;
        sizes.push(size);
        stat.bytes += size;
        if (size !== part.bytes) {
          problems.push(`${sggCd} ${umdNm} ${part.file} 크기가 목차와 다르다`);
        }

        const body = JSON.parse(gunzipSync(readFileSync(path)));
        if (body.schemaVersion !== SHAPE_SCHEMA_VERSION) {
          problems.push(`${sggCd} ${umdNm} ${part.file} 판이 다르다`);
          continue;
        }
        if (body.bjdCd !== dong.bjdCd || body.umdNm !== umdNm) {
          problems.push(`${sggCd} ${umdNm} ${part.file}이 다른 동을 담고 있다`);
        }
        if (!body.attribution) problems.push(`${sggCd} ${umdNm} ${part.file}에 출처가 없다`);

        const jibuns = Object.keys(body.buildings ?? {});
        if (jibuns.length !== part.buildings) {
          problems.push(
            `${sggCd} ${umdNm} ${part.file} 지번 수가 목차(${part.buildings})와 ${jibuns.length}로 다르다`,
          );
        }
        dongBuildings += jibuns.length;
        stat.buildings += jibuns.length;
        stat.shapes += (body.shapes ?? []).length;

        // 링은 `[경도, 위도, ...]`로 평평하다. 홀수면 그 뒤가 한 칸씩 밀린다.
        for (const ring of body.shapes ?? []) {
          if (!Array.isArray(ring) || ring.length < 6 || ring.length % 2 !== 0) {
            problems.push(`${sggCd} ${umdNm} ${part.file}에 모양이 깨진 링이 있다`);
            break;
          }
        }

        // 앱이 밟는 길 그대로: 지번 → 조각 → 모양.
        for (const jibun of sampleJibuns(jibuns)) {
          stat.checked += 1;
          const picked = partFor(dong, jibun);
          if (picked?.file !== part.file) {
            problems.push(
              `${sggCd} ${umdNm} ${jibun} → ${picked?.file ?? '없음'} (있어야 할 곳 ${part.file})`,
            );
          }
          for (const id of body.buildings[jibun]) {
            if (!Array.isArray(body.shapes?.[id])) {
              problems.push(`${sggCd} ${umdNm} ${jibun}이 없는 모양 #${id}을 가리킨다`);
            }
          }
        }
      }

      if (dongBuildings !== dong.buildings) {
        problems.push(
          `${sggCd} ${umdNm} 지번 합계가 목차(${dong.buildings})와 ${dongBuildings}로 다르다`,
        );
      }
    }

    for (const file of readdirSync(dir)) {
      if (!referenced.has(file)) problems.push(`${sggCd} ${file}을 아무도 가리키지 않는다`);
    }
  }

  sizes.sort((a, b) => a - b);
  const kb = (n) => `${(n / 1024).toFixed(0)}KB`;
  console.log(
    `시군구 ${stat.regions} · 법정동 ${stat.dongs.toLocaleString()} · 조각 ${stat.parts.toLocaleString()} · ` +
      `지번 ${stat.buildings.toLocaleString()} · 모양 ${stat.shapes.toLocaleString()}`,
  );
  console.log(
    `조각 크기 중앙값 ${kb(sizes[sizes.length >> 1] ?? 0)} · 최대 ${kb(sizes[sizes.length - 1] ?? 0)} · ` +
      `합계 ${(stat.bytes / 1048576).toFixed(1)}MB`,
  );
  console.log(`목차대로 짚어 본 지번 ${stat.checked.toLocaleString()}개`);

  if (problems.length > 0) {
    console.error(`\n어긋남 ${problems.length}건 — 올리지 마세요.`);
    for (const line of problems.slice(0, 40)) console.error(`  ${line}`);
    if (problems.length > 40) console.error(`  ... 그 밖에 ${problems.length - 40}건`);
    process.exitCode = 1;
    return;
  }
  console.log('\n어긋남 없음. 올려도 된다.');
};

main();
