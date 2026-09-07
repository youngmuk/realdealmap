/**
 * T1.1 스파이크 — 국토교통부 실거래가 API 실호출 검증기.
 *
 *   node packages/ingest/scripts/probe-api.mjs codes    # T1.1b 시군구 코드 체계 교차 검증
 *   node packages/ingest/scripts/probe-api.mjs all      # 9종 전체 호출 + 픽스처 저장
 *   node packages/ingest/scripts/probe-api.mjs edge     # T1.2 경계 동작 확인
 *   node packages/ingest/scripts/probe-api.mjs one <서비스명> <LAWD_CD> <YYYYMM>
 *
 * 인증키는 인자로 받지 않는다. 항상 .env에서 읽는다 — argv에 두면 셸 히스토리와
 * 프로세스 목록(ps · 작업관리자)에 그대로 남는다.
 *
 * 주의: serviceKey가 쿼리스트링에 들어가므로 요청 URL 전체를 절대 출력하지 않는다.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../../..');
const FIXTURE_DIR = resolve(HERE, '../test/fixtures');

// https로 고정한다. serviceKey가 쿼리스트링에 들어가므로 평문 http로 보내면
// 경로상의 프록시·공유 Wi-Fi에 인증키가 그대로 노출된다. 기술문서가 "전송 레벨 암호화 없음"이라
// 적어 두었지만 https도 정상 동작함을 실호출로 확인했으므로 평문 전환 경로를 두지 않는다.
const BASE = 'https://apis.data.go.kr/1613000';

/**
 * 기술문서 II장 "OPENAPI 에러 코드정리" 기준 분류.
 * 재시도해도 결과가 달라지지 않는 오류에 백오프를 쓰면 쿼터만 낭비된다.
 */
const ERROR_CODES = {
  '00': { label: 'NORMAL', retry: false },
  '000': { label: 'NORMAL', retry: false },
  '01': { label: 'Application Error', retry: true },
  '02': { label: 'DB Error', retry: true },
  '03': { label: 'No Data', retry: false },
  '04': { label: 'HTTP Error', retry: true },
  '05': { label: 'Service Timeout', retry: true },
  10: { label: 'ServiceKey 누락', retry: false },
  11: { label: '필수 파라미터 누락', retry: false },
  12: { label: '폐기된 서비스', retry: false },
  20: { label: '서비스 접근 거부(미승인)', retry: false },
  22: { label: '일일 트래픽 초과', retry: false },
  30: { label: '등록되지 않은 서비스키 / URL 인코딩 누락', retry: false },
  31: { label: '기간 만료된 서비스키', retry: false },
  32: { label: '등록되지 않은 도메인 또는 IP', retry: false },
};

const classify = (code) => {
  if (code === null || code === undefined) return '';
  const hit = ERROR_CODES[code] ?? ERROR_CODES[String(Number(code))];
  if (!hit) return ` [미분류 코드]`;
  return hit.label === 'NORMAL' ? '' : ` [${hit.label}${hit.retry ? ' · 재시도가능' : ' · 재시도무의미'}]`;
};

/** MVP 대상 9종. 값은 서비스명 = 오퍼레이션명이다. */
const SERVICES = {
  'apartment/sale': 'RTMSDataSvcAptTradeDev',
  'apartment/rent': 'RTMSDataSvcAptRent',
  'officetel/sale': 'RTMSDataSvcOffiTrade',
  'officetel/rent': 'RTMSDataSvcOffiRent',
  'rowhouse/sale': 'RTMSDataSvcRHTrade',
  'rowhouse/rent': 'RTMSDataSvcRHRent',
  'detached/sale': 'RTMSDataSvcSHTrade',
  'detached/rent': 'RTMSDataSvcSHRent',
  'land/sale': 'RTMSDataSvcLandTrade',
};

function loadServiceKey() {
  const envPath = resolve(REPO, '.env');
  if (!existsSync(envPath)) throw new Error('.env 파일이 없습니다. .env.example을 복사해 채우세요.');
  const raw = readFileSync(envPath, 'utf8');
  const m = raw.match(/^DATA_GO_KR_SERVICE_KEY=(.*)$/m);
  const key = m ? m[1].trim() : '';
  if (!key) throw new Error('DATA_GO_KR_SERVICE_KEY가 비어 있습니다.');
  // 포털은 Encoding(퍼센트 인코딩)과 Decoding(원문) 두 형태의 키를 준다.
  // 이미 인코딩된 키를 다시 인코딩하면 인증에 실패하므로 형태를 보고 결정한다.
  return key.includes('%') ? key : encodeURIComponent(key);
}

const pick = (xml, tag) => {
  const m = xml.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
  return m ? m[1].trim() : null;
};

async function call(serviceKey, service, lawdCd, dealYmd, { numOfRows = 100, pageNo = 1 } = {}) {
  const url =
    `${BASE}/${service}/${service.replace('RTMSDataSvc', 'getRTMSDataSvc')}` +
    `?serviceKey=${serviceKey}&LAWD_CD=${lawdCd}&DEAL_YMD=${dealYmd}` +
    `&numOfRows=${numOfRows}&pageNo=${pageNo}`;

  const started = Date.now();
  let res;
  try {
    res = await fetch(url, { headers: { Accept: 'application/xml' } });
  } catch (err) {
    // URL을 그대로 노출하지 않도록 메시지만 전달한다.
    return { ok: false, transport: err.message, ms: Date.now() - started };
  }
  const xml = await res.text();
  const items = xml.match(/<item>/g);

  // 첫 item의 태그명을 뽑아 기술문서의 응답 명세와 대조한다.
  const firstItem = xml.match(/<item>([\s\S]*?)<\/item>/);
  const fields = firstItem
    ? [...new Set([...firstItem[1].matchAll(/<([A-Za-z][A-Za-z0-9_]*)>/g)].map((m) => m[1]))].sort()
    : [];

  return {
    ok: res.ok,
    http: res.status,
    ms: Date.now() - started,
    resultCode: pick(xml, 'resultCode') ?? pick(xml, 'returnReasonCode'),
    resultMsg: pick(xml, 'resultMsg') ?? pick(xml, 'returnAuthMsg'),
    totalCount: pick(xml, 'totalCount'),
    itemCount: items ? items.length : 0,
    fields,
    xml,
  };
}

/**
 * 기술문서 "토지 매매 실거래가 조회"의 응답 명세에 적힌 항목.
 * 실호출 결과와 대조해 문서와 실제가 일치하는지 확인한다.
 */
const DOCUMENTED_LAND_FIELDS = [
  'cdealDay', 'cdealType', 'dealAmount', 'dealArea', 'dealDay', 'dealMonth',
  'dealYear', 'dealingGbn', 'estateAgentSggNm', 'jibun', 'jimok', 'landUse',
  'sggCd', 'sggNm', 'shareDealingType', 'umdNm',
];

const fmt = (r) => {
  if (r.transport) return `전송실패 ${r.transport}`;
  const code = r.resultCode ?? '-';
  const msg = (r.resultMsg ?? '-').slice(0, 24);
  return (
    `HTTP ${r.http} · code=${code}${classify(r.resultCode)} · ${msg}` +
    ` · total=${r.totalCount ?? '-'} · items=${r.itemCount} · ${r.ms}ms`
  );
};

// 기술문서상 초당 최대 30 tps. 스파이크는 순차 호출이므로 여유롭게 잡는다.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** 최근 확정 월과 12개월 전 월. 당월은 신고가 거의 없어 판별에 부적합하다. */
function months() {
  const d = new Date();
  d.setMonth(d.getMonth() - 1);
  const recent = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}`;
  d.setMonth(d.getMonth() - 11);
  const old = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}`;
  return { recent, old };
}

/** T1.1b — 행정구역 개편 전후 코드 중 어느 쪽이 데이터를 반환하는지 확인한다. */
async function probeCodes(key) {
  const { recent, old } = months();
  const pairs = [
    ['전남광주통합 동구 (신)', '12210', '광주광역시 동구 (구)', '29110'],
    ['전남광주통합 목포시 (신)', '12110', '전라남도 목포시 (구)', '46110'],
    ['강원특별자치도 춘천시 (신)', '51110', '강원도 춘천시 (구)', '42110'],
    ['전북특별자치도 전주 완산구 (신)', '52111', '전라북도 전주 완산구 (구)', '45111'],
    ['화성시 만세구 (2025 신설)', '41591', '화성시 (상위)', '41590'],
    ['부천시 원미구 (2024 재설치)', '41192', '부천시 (상위)', '41190'],
    ['서울 종로구 (대조군)', '11110', '서울 종로구 (동일)', '11110'],
  ];

  console.log(`대상 서비스: apartment/sale (${SERVICES['apartment/sale']})`);
  console.log(`계약월: 최근=${recent} · 12개월전=${old}\n`);

  for (const [nameA, codeA, nameB, codeB] of pairs) {
    for (const ym of [recent, old]) {
      const a = await call(key, SERVICES['apartment/sale'], codeA, ym);
      await sleep(250);
      const b = await call(key, SERVICES['apartment/sale'], codeB, ym);
      await sleep(250);
      console.log(`[${ym}] ${nameA} ${codeA}`);
      console.log(`         ${fmt(a)}`);
      console.log(`         ${nameB} ${codeB}`);
      console.log(`         ${fmt(b)}`);
    }
    console.log('');
  }
}

/** T1.1 — 9종을 한 지역에 대해 호출하고 원문 XML을 픽스처로 남긴다. */
async function probeAll(key, lawdCd = '11110', dealYmd = months().recent) {
  mkdirSync(FIXTURE_DIR, { recursive: true });
  console.log(`지역=${lawdCd} 계약월=${dealYmd}\n`);

  const summary = [];
  for (const [name, service] of Object.entries(SERVICES)) {
    const r = await call(key, service, lawdCd, dealYmd);
    console.log(`${name.padEnd(16)} ${fmt(r)}`);
    if (r.fields.length) console.log(`${' '.repeat(17)}필드 ${r.fields.length}개: ${r.fields.join(', ')}`);
    if (r.xml) {
      const file = resolve(FIXTURE_DIR, `${name.replace('/', '-')}.xml`);
      writeFileSync(file, r.xml, 'utf8');
    }
    summary.push({ name, code: r.resultCode, items: r.itemCount, fields: r.fields });
    await sleep(300);
  }

  // 기술문서를 확보한 토지 매매만 명세와 실제를 대조한다.
  const land = summary.find((s) => s.name === 'land/sale');
  if (land?.fields.length) {
    const missing = DOCUMENTED_LAND_FIELDS.filter((f) => !land.fields.includes(f));
    const extra = land.fields.filter((f) => !DOCUMENTED_LAND_FIELDS.includes(f));
    console.log('\n[토지 매매] 기술문서 대조');
    console.log(`  문서에 있으나 응답에 없음: ${missing.length ? missing.join(', ') : '없음'}`);
    console.log(`  응답에 있으나 문서에 없음: ${extra.length ? extra.join(', ') : '없음'}`);
  }

  const okCount = summary.filter((s) => s.items > 0).length;
  console.log(`\n데이터 반환: ${okCount}/9 · 픽스처 저장 위치: packages/ingest/test/fixtures/`);
}

/** T1.2 — 경계 동작. 0건과 오류가 구분되는지 확인한다. */
async function probeEdge(key) {
  const { recent } = months();
  const svc = SERVICES['apartment/sale'];
  const cases = [
    ['정상', '11110', recent, {}],
    ['미래 계약월', '11110', '209912', {}],
    ['존재하지 않는 코드', '99999', recent, {}],
    ['형식 오류 코드', 'ABCDE', recent, {}],
    ['형식 오류 계약월', '11110', '2026', {}],
    ['numOfRows=1 페이지네이션', '11110', recent, { numOfRows: 1 }],
    ['pageNo=9999', '11110', recent, { numOfRows: 10, pageNo: 9999 }],
  ];
  for (const [label, lawd, ym, opt] of cases) {
    const r = await call(key, svc, lawd, ym, opt);
    console.log(`${label.padEnd(24)} ${fmt(r)}`);
    await sleep(250);
  }
}

async function main() {
  const key = loadServiceKey();
  const [mode, ...rest] = process.argv.slice(2);

  if (mode === 'codes') return probeCodes(key);
  if (mode === 'all') return probeAll(key, rest[0], rest[1]);
  if (mode === 'edge') return probeEdge(key);
  if (mode === 'one') {
    const [svcName, lawd, ym] = rest;
    const service = SERVICES[svcName] ?? svcName;
    const r = await call(key, service, lawd, ym);
    console.log(fmt(r));
    console.log(r.xml?.slice(0, 1500));
    return undefined;
  }
  console.log('사용법: probe-api.mjs codes | all | edge | one <서비스> <LAWD_CD> <YYYYMM>');
  return undefined;
}

main().catch((err) => {
  console.error(`[probe-api] ${err.message}`);
  process.exit(1);
});
