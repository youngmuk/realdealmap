/**
 * 도로명주소 건물DB를 읽는다 (행정안전부, 공공데이터 제1유형).
 *
 * **왜 이 파일이 있나.** 좌표의 원천이 지오코딩 API에서 도로명주소 파일로 바뀌었다
 * (기술검토서 rev.4 · AD-3′). 좌표 자체는 위치정보요약DB에 있고, 그 DB는
 * **도로명 기준**으로만 찾을 수 있다. 우리가 가진 것은 실거래가의 **지번**이다.
 * 건물DB가 그 사이를 잇는다.
 *
 *     실거래가 (법정동명|지번)  →  건물DB  →  건물키  →  위치정보요약DB  →  좌표
 *
 * 여기서는 왼쪽 두 칸만 다룬다. 좌표는 `utmk.ts`가 옮긴다.
 *
 * **형식.** `|` 구분 · CP949 · CRLF. 실제 배포본으로 확인했다(202608 전체분).
 * 파일은 시도별로 쪼개져 온다 — `build_seoul.txt`(건물정보) · `jibun_seoul.txt`(관련지번).
 */

/** 건물DB 파일의 구분자. */
export const JUSO_DELIMITER = '|';

/**
 * 건물DB에서 뽑아낸 한 줄.
 *
 * 원본은 31열(건물정보) 또는 14열(관련지번)이지만 좌표를 붙이는 데 필요한 것은
 * 이만큼이다. 나머지를 들고 다니면 전국 800만 행에서 메모리만 먹는다.
 */
export interface JusoBuilding {
  /** 법정동코드 10자리. 앞 5자리가 시군구코드다 */
  readonly bjdCd: string;
  /** 법정읍면동명 + 법정리명. 실거래가의 `umdNm`과 같은 모양이다 */
  readonly umdNm: string;
  /** 지번. `123` 또는 `123-4`, 산이면 `산 123` */
  readonly jibun: string;
  /** 위치정보요약DB를 찾을 열쇠 */
  readonly buildingKey: string;
}

/**
 * 실거래가의 `umdNm`과 같은 모양으로 잇는다.
 *
 * 건물DB는 읍면동과 리를 **다른 열에** 둔다. 국토부는 둘을 공백으로 이어 준다 —
 * 도시는 `개포동`, 군 지역은 `부안읍 봉덕리`. 실제 응답으로 확인했다.
 */
export const jusoUmdName = (emdNm: string, riNm: string): string =>
  riNm ? `${emdNm} ${riNm}` : emdNm;

/**
 * 지번 문자열. 부번이 0이면 붙이지 않는다 — 실거래가가 그렇게 준다.
 *
 * 산 지번은 `산 ` 접두를 단다. 국토부가 산 지번을 어떤 모양으로 주는지는
 * 표본(강남구·부안군 44,692건)에 한 건도 없어 **아직 확인하지 못했다.**
 * 접두를 달아 두면 표기가 맞을 때만 붙고, 아니면 그냥 안 붙을 뿐이다 —
 * 대지 지번과 뒤섞여 **엉뚱한 건물에 붙는 일은 생기지 않는다.**
 */
export const jusoJibun = (isMountain: boolean, mainNo: number, subNo: number): string => {
  const base = subNo > 0 ? `${mainNo}-${subNo}` : `${mainNo}`;
  return isMountain ? `산 ${base}` : base;
};

/**
 * 위치정보요약DB를 찾는 열쇠.
 *
 * 두 DB의 PK가 `도로명코드(12) + 지하여부(1) + 건물본번(5) + 건물부번(5)`로
 * 정확히 맞물린다. 숫자는 자릿수를 지우고 넣는다 — 한쪽은 `00011`,
 * 다른 쪽은 `11`로 오기 때문이다.
 */
export const jusoBuildingKey = (
  roadCd: string,
  undergroundFlag: string,
  mainNo: number,
  subNo: number,
): string => `${roadCd}|${undergroundFlag}|${mainNo}|${subNo}`;

/** 사전 열쇠와 같은 모양. `geo.ts`의 `geoKey`와 짝이 맞아야 한다. */
export const jusoGeoKey = (umdNm: string, jibun: string): string => `${umdNm}|${jibun}`;

/** 숫자 열을 읽는다. 빈 칸·비숫자는 실패로 본다 — 0으로 눙치면 엉뚱한 지번이 생긴다. */
const num = (value: string | undefined): number | null => {
  if (value === undefined || value.trim() === '') return null;
  const n = Number(value);
  return Number.isInteger(n) && n >= 0 ? n : null;
};

/** 열 배치. 두 표가 다르다 — 관련지번에는 도로명·건물명 열이 없다. */
const LAYOUT = {
  /** 건물정보 (31열) */
  building: { cols: 31, road: 8, under: 10, bMain: 11, bSub: 12 },
  /** 관련지번 (14열) */
  jibun: { cols: 14, road: 8, under: 9, bMain: 10, bSub: 11 },
} as const;

export type JusoTable = keyof typeof LAYOUT;

/**
 * 한 줄을 읽는다. 모양이 안 맞으면 `null`.
 *
 * **조용히 넘기는 것이 맞다.** 800만 행 중 몇 줄이 깨졌다고 전체 적재를 멈추면
 * 좌표가 하나도 안 붙는다. 대신 부르는 쪽이 건너뛴 수를 세어 밖으로 낸다 —
 * 그 수가 갑자기 커지면 형식이 바뀐 것이다.
 */
export const parseJusoRow = (line: string, table: JusoTable): JusoBuilding | null => {
  const c = line.split(JUSO_DELIMITER);
  const at = LAYOUT[table];
  // 줄 끝에 구분자가 하나 더 붙어 오므로 열 수는 규정치 이상이면 된다.
  if (c.length < at.cols) return null;

  const bjdCd = c[0] ?? '';
  if (!/^\d{10}$/.test(bjdCd)) return null;

  const mainNo = num(c[6]);
  const subNo = num(c[7]);
  const bMain = num(c[at.bMain]);
  const bSub = num(c[at.bSub]);
  const roadCd = c[at.road] ?? '';
  const under = c[at.under] ?? '';
  if (mainNo === null || subNo === null || bMain === null || bSub === null) return null;
  if (!/^\d{12}$/.test(roadCd) || under === '') return null;

  return {
    bjdCd,
    umdNm: jusoUmdName(c[3] ?? '', c[4] ?? ''),
    jibun: jusoJibun(c[5] === '1', mainNo, subNo),
    buildingKey: jusoBuildingKey(roadCd, under, bMain, bSub),
  };
};

export interface JusoIndexReport {
  /** 색인에 들어간 열쇠 수 */
  readonly keys: number;
  /** 모양이 안 맞아 건너뛴 줄 수 */
  readonly skipped: number;
  /**
   * 같은 열쇠에 **다른 건물**이 걸린 횟수.
   *
   * 한 지번에 건물이 여러 채인 경우다(단지형 아파트). 먼저 온 것을 남긴다 —
   * 어느 동인지는 실거래가만으로 알 수 없고, 같은 지번 안이라 수십 미터 차이다.
   * 이 수가 폭증하면 열쇠 설계가 잘못된 것이므로 밖으로 낸다.
   */
  readonly collisions: number;
}

/**
 * 시군구별 `법정동명|지번 → 건물키` 색인을 쌓는다.
 *
 * 전국 800만 행을 한 번에 들 수 없으므로 부르는 쪽이 파일을 나눠 흘려 넣고,
 * 여기서는 받은 줄만 누적한다.
 */
export const addJusoRows = (
  index: Map<string, Map<string, string>>,
  lines: Iterable<string>,
  table: JusoTable,
): JusoIndexReport => {
  let keys = 0;
  let skipped = 0;
  let collisions = 0;

  for (const line of lines) {
    if (line === '') continue;
    const row = parseJusoRow(line, table);
    if (row === null) {
      skipped += 1;
      continue;
    }

    const sggCd = row.bjdCd.slice(0, 5);
    let bucket = index.get(sggCd);
    if (bucket === undefined) {
      bucket = new Map();
      index.set(sggCd, bucket);
    }

    const key = jusoGeoKey(row.umdNm, row.jibun);
    const seen = bucket.get(key);
    if (seen === undefined) {
      bucket.set(key, row.buildingKey);
      keys += 1;
    } else if (seen !== row.buildingKey) {
      collisions += 1;
    }
  }

  return { keys, skipped, collisions };
};
