/**
 * 행정표준코드관리시스템(code.go.kr)에서 법정동코드 전체자료를 내려받아
 * raw/bjd.txt (UTF-8)로 저장한다.
 *
 *   node packages/shared/scripts/download-bjd.mjs
 *
 * 원본은 CP949(EUC-KR) 인코딩의 탭 구분 텍스트를 담은 zip 파일이다.
 * 의존성 없이 동작하도록 zip 파싱과 인코딩 변환을 직접 처리한다.
 */
import { inflateRawSync } from 'node:zlib';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const RAW_DIR = resolve(HERE, '../raw');
const OUT_FILE = resolve(RAW_DIR, 'bjd.txt');

const ENDPOINT = 'https://www.code.go.kr/etc/codeFullDown.do';
const REFERER = 'https://www.code.go.kr/stdcode/regCodeL.do';

/** 조회 폼의 기본값. disuseAt=0 은 폐지 항목까지 포함한 전체자료를 뜻한다. */
const FORM = {
  cPage: '1',
  regionCd_pk: '',
  chkWantCnt: '0',
  reqSggCd: '',
  reqUmdCd: '',
  reqRiCd: '',
  searchOk: '',
  codeseId: '법정동코드',
  pageSize: '10',
  regionCd: '',
  locataddNm: '',
  sidoCd: '*',
  sggCd: '*',
  umdCd: '*',
  riCd: '*',
  disuseAt: '0',
  stdate: '',
  enddate: '',
};

const EOCD_SIG = 0x06054b50;
const CEN_SIG = 0x02014b50;

/**
 * zip 아카이브에서 첫 번째 엔트리의 내용을 꺼낸다.
 * 중앙 디렉터리를 기준으로 읽으므로 data descriptor 사용 여부와 무관하게 동작한다.
 */
function readFirstZipEntry(buf) {
  let eocd = -1;
  for (let i = buf.length - 22; i >= 0; i -= 1) {
    if (buf.readUInt32LE(i) === EOCD_SIG) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error('zip 중앙 디렉터리(EOCD)를 찾지 못했습니다.');

  const cenOffset = buf.readUInt32LE(eocd + 16);
  if (buf.readUInt32LE(cenOffset) !== CEN_SIG) {
    throw new Error('zip 중앙 디렉터리 시그니처가 올바르지 않습니다.');
  }

  const method = buf.readUInt16LE(cenOffset + 10);
  const compSize = buf.readUInt32LE(cenOffset + 20);
  const flags = buf.readUInt16LE(cenOffset + 8);
  const nameLen = buf.readUInt16LE(cenOffset + 28);
  const localOffset = buf.readUInt32LE(cenOffset + 42);
  // 플래그 비트 11이 서면 파일명이 UTF-8, 아니면 이 사이트 기준 CP949다.
  const nameBytes = buf.subarray(cenOffset + 46, cenOffset + 46 + nameLen);
  const name = new TextDecoder(flags & 0x800 ? 'utf-8' : 'euc-kr').decode(nameBytes);

  // 로컬 헤더는 30바이트 고정부 + 파일명 + extra 필드로 구성된다.
  const localNameLen = buf.readUInt16LE(localOffset + 26);
  const localExtraLen = buf.readUInt16LE(localOffset + 28);
  const dataStart = localOffset + 30 + localNameLen + localExtraLen;
  const raw = buf.subarray(dataStart, dataStart + compSize);

  if (method === 0) return { name, data: raw };
  if (method === 8) return { name, data: inflateRawSync(raw) };
  throw new Error(`지원하지 않는 zip 압축 방식입니다: ${method}`);
}

async function main() {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Referer: REFERER,
      'User-Agent': 'Mozilla/5.0 (compatible; RealDealMap/1.0)',
    },
    body: new URLSearchParams(FORM).toString(),
  });

  if (!res.ok) throw new Error(`다운로드 실패: HTTP ${res.status}`);

  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 1024) {
    throw new Error(`응답이 너무 작습니다(${buf.length}바이트). 폼 파라미터가 바뀌었을 수 있습니다.`);
  }

  const { name, data } = readFirstZipEntry(buf);
  const text = new TextDecoder('euc-kr').decode(data);

  const lineCount = text.split(/\r?\n/).filter((l) => l.trim()).length;
  if (!text.startsWith('법정동코드')) {
    throw new Error('예상한 헤더(법정동코드)로 시작하지 않습니다. 원본 형식이 바뀌었을 수 있습니다.');
  }

  await mkdir(RAW_DIR, { recursive: true });
  await writeFile(OUT_FILE, text, 'utf8');

  console.log(`내려받음: ${name}`);
  console.log(`저장: ${OUT_FILE}`);
  console.log(`행 수: ${lineCount.toLocaleString('ko-KR')} (헤더 포함)`);
}

main().catch((err) => {
  console.error(`[download-bjd] ${err.message}`);
  process.exit(1);
});
