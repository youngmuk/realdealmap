/**
 * raw/bjd.txt(법정동코드 전체자료)에서 실거래가 API 조회 단위인
 * 시군구 5자리 코드 목록을 뽑아 data/regions.json 과 data/legacy-codes.json 을 만든다.
 *
 *   node packages/shared/scripts/build-regions.mjs
 *
 * 법정동코드는 시도(2) + 시군구(3) + 읍면동(3) + 리(2) = 10자리다.
 * 시군구 레벨은 읍면동·리 자리가 모두 0이면서 시군구 자리가 0이 아닌 항목이다.
 */
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const RAW_FILE = resolve(HERE, '../raw/bjd.txt');
const OUT_DIR = resolve(HERE, '../data');

const ALIVE = '존재';

/**
 * 폐지된 시도 코드 → 현행 시도 코드.
 * 실거래가 API가 과거 신고분에 대해 어떤 코드를 받는지는 실호출로 확인해야 하므로
 * (기술검토서 T1.1) 옛 코드를 버리지 않고 매핑으로 보존한다.
 */
const SIDO_SUCCESSOR = {
  21: '26', // 부산직할시  → 부산광역시
  22: '27', // 대구직할시  → 대구광역시
  23: '28', // 인천직할시  → 인천광역시
  24: '12', // 광주직할시  → (광주광역시) → 전남광주통합특별시
  25: '30', // 대전직할시  → 대전광역시
  29: '12', // 광주광역시  → 전남광주통합특별시
  42: '51', // 강원도      → 강원특별자치도
  45: '52', // 전라북도    → 전북특별자치도
  46: '12', // 전라남도    → 전남광주통합특별시
  49: '50', // 제주도      → 제주특별자치도
};

function parseRows(text) {
  const [header, ...lines] = text.split(/\r?\n/);
  if (!header.startsWith('법정동코드')) {
    throw new Error('예상한 헤더가 아닙니다. raw/bjd.txt를 다시 내려받으세요.');
  }
  return lines
    .filter((line) => line.trim())
    .map((line) => {
      const [code, name, status] = line.split('\t');
      return { code, name, status };
    });
}

const isSggLevel = (code) => code.slice(5) === '00000' && code.slice(2, 5) !== '000';

/** "경기도 수원시 장안구" → { sidoName: "경기도", sggName: "수원시 장안구" } */
function splitName(name) {
  const [sidoName, ...rest] = name.split(' ');
  return { sidoName, sggName: rest.join(' ') };
}

async function main() {
  const text = await readFile(RAW_FILE, 'utf8');
  const rows = parseRows(text);

  const alive = rows.filter((r) => r.status === ALIVE);
  const retired = rows.filter((r) => r.status !== ALIVE);

  const aliveSgg = alive
    .filter((r) => isSggLevel(r.code))
    .map((r) => ({ sggCd: r.code.slice(0, 5), name: r.name, ...splitName(r.name) }));

  // 일반구를 둔 시(수원시 등)는 그 자체로도 시군구 코드를 갖는다.
  // 하위 구와 중복 조회가 되므로 조회 대상에서는 제외하고 부모로만 남긴다.
  const parentNames = new Set(
    aliveSgg
      .filter((p) => aliveSgg.some((c) => c.name !== p.name && c.name.startsWith(`${p.name} `)))
      .map((p) => p.name),
  );

  const byName = new Map(aliveSgg.map((r) => [r.name, r]));

  const regions = aliveSgg
    .map((r) => {
      const isParent = parentNames.has(r.name);
      const parent = aliveSgg.find(
        (p) => parentNames.has(p.name) && r.name.startsWith(`${p.name} `),
      );
      return {
        sggCd: r.sggCd,
        name: r.name,
        sidoCd: r.sggCd.slice(0, 2),
        sidoName: r.sidoName,
        sggName: r.sggName,
        // queryable=false 인 항목은 하위 구로 나뉘므로 직접 조회하지 않는다.
        queryable: !isParent,
        ...(parent ? { parentCd: parent.sggCd } : {}),
        ...(isParent ? { hasSubGu: true } : {}),
      };
    })
    .sort((a, b) => a.sggCd.localeCompare(b.sggCd));

  // 폐지된 시군구 → 현행 시군구 후보 매핑
  const legacy = [];
  for (const r of retired) {
    if (!isSggLevel(r.code)) continue;
    const legacyCd = r.code.slice(0, 5);
    const successorSido = SIDO_SUCCESSOR[legacyCd.slice(0, 2)];
    if (!successorSido) continue;

    const { sggName } = splitName(r.name);
    if (!sggName) continue;

    const current = regions.find(
      (c) => c.sidoCd === successorSido && c.sggName === sggName,
    );
    if (!current) continue;

    legacy.push({
      legacyCd,
      legacyName: r.name,
      currentCd: current.sggCd,
      currentName: current.name,
    });
  }

  // 같은 legacyCd가 여러 번 나올 수 있으므로(연혁상 재편) 중복 제거
  const legacyUnique = [...new Map(legacy.map((l) => [l.legacyCd, l])).values()].sort((a, b) =>
    a.legacyCd.localeCompare(b.legacyCd),
  );

  const generatedAt = new Date().toISOString();
  const queryable = regions.filter((r) => r.queryable);

  await mkdir(OUT_DIR, { recursive: true });
  await writeFile(
    resolve(OUT_DIR, 'regions.json'),
    `${JSON.stringify(
      {
        generatedAt,
        source: '행정표준코드관리시스템 법정동코드 전체자료 (code.go.kr)',
        note: '실거래가 API의 LAWD_CD는 queryable=true 인 항목의 sggCd를 사용한다.',
        totalSggLevel: regions.length,
        queryableCount: queryable.length,
        regions,
      },
      null,
      2,
    )}\n`,
    'utf8',
  );

  // Worker는 파일시스템이 없다. 조회 대상 코드 집합만 fs 없이 import할 수 있게
  // 모듈로 굽는다. 코드 자체를 손으로 적으면 카탈로그와 어긋나므로 여기서 생성하고,
  // `codes.generated.test.ts`가 regions.json과 일치하는지 잠근다.
  await writeFile(
    resolve(HERE, '../src/codes.generated.ts'),
    [
      '// 자동 생성 파일. 직접 고치지 말고 `npm run regions:build`를 실행한다.',
      '//',
      '// Worker에서 쓰려고 만든 fs 없는 사본이다. `regions.ts`는 node:fs를 쓰므로',
      '// Cloudflare Workers 런타임에서 import할 수 없다.',
      '',
      `/** 생성 시각 ${generatedAt} */`,
      'export const QUERYABLE_SGG_CODES: readonly string[] = [',
      ...queryable.map((r) => `  '${r.sggCd}', // ${r.name}`),
      '];',
      '',
      '/** 조회 대상 시군구인지. Worker의 미등록 코드 거부(R-11 ③)에 쓴다. */',
      'export const isQueryableSggCd = (sggCd: string): boolean =>',
      '  QUERYABLE_CODE_SET.has(sggCd);',
      '',
      'const QUERYABLE_CODE_SET = new Set(QUERYABLE_SGG_CODES);',
      '',
    ].join('\n'),
    'utf8',
  );

  await writeFile(
    resolve(OUT_DIR, 'legacy-codes.json'),
    `${JSON.stringify(
      {
        generatedAt,
        note:
          '폐지된 시군구 코드와 현행 코드의 대응. 국토부 실거래가 API가 과거 계약월에 대해 ' +
          '옛 코드를 요구하는지는 실호출로 확인해야 한다.',
        sidoSuccessor: SIDO_SUCCESSOR,
        count: legacyUnique.length,
        mappings: legacyUnique,
      },
      null,
      2,
    )}\n`,
    'utf8',
  );

  // 요약 출력
  const bySido = new Map();
  for (const r of queryable) {
    bySido.set(r.sidoName, (bySido.get(r.sidoName) ?? 0) + 1);
  }

  console.log(`시군구 레벨 전체 : ${regions.length}`);
  console.log(`조회 대상(LAWD_CD): ${queryable.length}`);
  console.log(`하위 구를 둔 시   : ${parentNames.size}`);
  console.log(`폐지 코드 매핑    : ${legacyUnique.length}`);
  console.log('');
  for (const [sido, n] of bySido) {
    console.log(`  ${sido.padEnd(12, ' ')} ${String(n).padStart(3, ' ')}`);
  }
  if (byName.size !== aliveSgg.length) {
    console.warn('\n[경고] 동일한 시군구 이름이 중복 존재합니다. 부모 판별을 재확인하세요.');
  }
}

main().catch((err) => {
  console.error(`[build-regions] ${err.message}`);
  process.exit(1);
});
