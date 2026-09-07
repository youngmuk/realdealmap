import type { DatasetKey } from '@realdealmap/shared';

/**
 * 좌표를 얼마나 정밀하게 얻을 수 있는지를 나타낸다.
 * 응답이 주소를 어디까지 공개하느냐로 결정되며, 지도 표현 방식이 여기에 달려 있다.
 */
export type GeocodePrecision =
  /** 법정동코드 + 본번/부번 + 도로명 코드까지 제공 → 지번 주소를 정확히 조합할 수 있다 */
  | 'exact'
  /** 지번 문자열 제공 → 지오코딩으로 건물 단위 좌표를 얻을 수 있다 */
  | 'jibun'
  /** 지번이 마스킹된다(예: `2**`) → 지번 단위 좌표 불가, 법정동 중심점으로 근사 */
  | 'partial'
  /** 지번 자체가 없다 → 법정동 중심점만 가능 */
  | 'umd';

/** 정규화 모델의 필드가 원천의 어떤 항목에서 오는지에 대한 대응. */
export interface FieldMapping {
  /** 단지명·주택유형 등 사람이 읽는 이름 */
  readonly name?: string;
  readonly jibun?: string;
  /** 전용면적 또는 거래면적 */
  readonly area?: string;
  readonly floor?: string;
  readonly builtYear?: string;
  /** 매매가(만원) */
  readonly amount?: string;
  /** 전월세 보증금(만원) */
  readonly deposit?: string;
  /** 전월세 월세(만원) */
  readonly monthlyRent?: string;
}

export interface DatasetSpec {
  /** 공공데이터포털 데이터셋 번호. 활용신청·기술문서 추적용 */
  readonly portalId: string;
  /** apis.data.go.kr/1613000 아래의 서비스명. 오퍼레이션명은 `get` + 서비스명이다 */
  readonly service: string;
  /** Swagger 응답 모델에 선언된 item 항목 전체 */
  readonly fields: readonly string[];
  readonly map: FieldMapping;
  readonly geocode: GeocodePrecision;
  /** 해제(계약 취소) 상태를 제공하는가. 전월세 4종은 제공하지 않는다 */
  readonly cancellable: boolean;
}

/** `get` + 서비스명이 오퍼레이션명이다. 기술문서 요청 예제와 동일한 규칙. */
export const operationOf = (spec: DatasetSpec): string => `get${spec.service}`;

/** 전월세 4종이 공통으로 제공하는 금액 항목. */
const RENT_MONEY = ['deposit', 'monthlyRent'] as const;
/** 전월세 4종이 공통으로 제공하는 계약 항목. 갱신요구권과 종전계약 정보를 포함한다. */
const RENT_CONTRACT = [
  'contractTerm',
  'contractType',
  'useRRRight',
  'preDeposit',
  'preMonthlyRent',
] as const;

const DEAL_DATE = ['dealYear', 'dealMonth', 'dealDay'] as const;
const CANCEL = ['cdealType', 'cdealDay'] as const;
const AGENT = ['dealingGbn', 'estateAgentSggNm'] as const;
const PARTY = ['slerGbn', 'buyerGbn'] as const;

/**
 * 아파트 전월세만 도로명 필드가 **전부 소문자**다(`roadnmcd`, `roadnmbonbun`...).
 * 아파트 매매는 같은 의미의 필드가 camelCase(`roadNmCd`, `roadNmBonbun`)다.
 * 원천의 표기 불일치이므로 파서에서 필드명을 정규화하지 말고 그대로 둔다.
 */
const APT_RENT_ROAD = [
  'roadnm',
  'roadnmsggcd',
  'roadnmcd',
  'roadnmseq',
  'roadnmbcd',
  'roadnmbonbun',
  'roadnmbubun',
] as const;

/**
 * MVP 대상 9종의 응답 스키마.
 *
 * 최초에는 각 API 상세페이지의 Swagger 응답 모델에서 추출했으나(2026-09-07),
 * T1.1 실호출 결과 **Swagger가 4종에서 실제보다 부족**했다:
 * 아파트 전월세 +8(aptSeq·도로명 7), 연립다세대 매매/전월세 +1(houseType),
 * 단독다가구 전월세 +1(houseType). 따라서 아래 목록은 Swagger가 아니라
 * `test/fixtures/*.xml`의 **실응답(11110/202608)**이 기준이다.
 * 토지 매매는 배포된 기술문서(hwp)·Swagger·실응답 셋이 모두 일치한다.
 */
export const DATASETS: Readonly<Record<DatasetKey, DatasetSpec>> = {
  'apartment/sale': {
    portalId: '15126468',
    service: 'RTMSDataSvcAptTradeDev',
    fields: [
      'sggCd', 'umdCd', 'landCd', 'bonbun', 'bubun',
      'roadNm', 'roadNmSggCd', 'roadNmCd', 'roadNmSeq', 'roadNmbCd',
      'roadNmBonbun', 'roadNmBubun',
      'umdNm', 'aptNm', 'jibun', 'excluUseAr',
      ...DEAL_DATE, 'dealAmount', 'floor', 'buildYear', 'aptSeq',
      ...CANCEL, ...AGENT, 'rgstDate', 'aptDong', ...PARTY, 'landLeaseholdGbn',
    ],
    map: {
      name: 'aptNm', jibun: 'jibun', area: 'excluUseAr',
      floor: 'floor', builtYear: 'buildYear', amount: 'dealAmount',
    },
    // 본번·부번과 도로명 코드가 모두 있어 지번 주소를 정확히 조합할 수 있다.
    geocode: 'exact',
    cancellable: true,
  },

  'apartment/rent': {
    portalId: '15126474',
    service: 'RTMSDataSvcAptRent',
    fields: [
      'sggCd', 'umdNm', 'aptNm', 'aptSeq', 'jibun', 'excluUseAr',
      ...APT_RENT_ROAD,
      ...DEAL_DATE, ...RENT_MONEY, 'floor', 'buildYear', ...RENT_CONTRACT,
    ],
    map: {
      name: 'aptNm', jibun: 'jibun', area: 'excluUseAr',
      floor: 'floor', builtYear: 'buildYear',
      deposit: 'deposit', monthlyRent: 'monthlyRent',
    },
    // 도로명코드 + 건물번호 본번/부번이 모두 있어 도로명주소를 완전히 조합할 수 있다.
    // Swagger에는 없던 필드로, 실호출로만 확인됐다.
    geocode: 'exact',
    cancellable: false,
  },

  'officetel/sale': {
    portalId: '15126464',
    service: 'RTMSDataSvcOffiTrade',
    fields: [
      'sggCd', 'sggNm', 'umdNm', 'jibun', 'offiNm', 'excluUseAr',
      ...DEAL_DATE, 'dealAmount', 'floor', 'buildYear',
      ...CANCEL, ...AGENT, ...PARTY,
    ],
    map: {
      name: 'offiNm', jibun: 'jibun', area: 'excluUseAr',
      floor: 'floor', builtYear: 'buildYear', amount: 'dealAmount',
    },
    geocode: 'jibun',
    cancellable: true,
  },

  'officetel/rent': {
    portalId: '15126475',
    service: 'RTMSDataSvcOffiRent',
    fields: [
      'sggCd', 'sggNm', 'umdNm', 'jibun', 'offiNm', 'excluUseAr',
      ...DEAL_DATE, ...RENT_MONEY, 'floor', 'buildYear', ...RENT_CONTRACT,
    ],
    map: {
      name: 'offiNm', jibun: 'jibun', area: 'excluUseAr',
      floor: 'floor', builtYear: 'buildYear',
      deposit: 'deposit', monthlyRent: 'monthlyRent',
    },
    geocode: 'jibun',
    cancellable: false,
  },

  'rowhouse/sale': {
    portalId: '15126467',
    service: 'RTMSDataSvcRHTrade',
    fields: [
      'sggCd', 'umdNm', 'mhouseNm', 'houseType', 'jibun', 'buildYear', 'excluUseAr', 'landAr',
      ...DEAL_DATE, 'dealAmount', 'floor',
      ...CANCEL, ...AGENT, 'rgstDate', ...PARTY,
    ],
    map: {
      name: 'mhouseNm', jibun: 'jibun', area: 'excluUseAr',
      floor: 'floor', builtYear: 'buildYear', amount: 'dealAmount',
    },
    geocode: 'jibun',
    cancellable: true,
  },

  'rowhouse/rent': {
    portalId: '15126473',
    service: 'RTMSDataSvcRHRent',
    fields: [
      'sggCd', 'umdNm', 'mhouseNm', 'houseType', 'jibun', 'buildYear', 'excluUseAr',
      ...DEAL_DATE, ...RENT_MONEY, 'floor', ...RENT_CONTRACT,
    ],
    map: {
      name: 'mhouseNm', jibun: 'jibun', area: 'excluUseAr',
      floor: 'floor', builtYear: 'buildYear',
      deposit: 'deposit', monthlyRent: 'monthlyRent',
    },
    geocode: 'jibun',
    cancellable: false,
  },

  'detached/sale': {
    portalId: '15126465',
    service: 'RTMSDataSvcSHTrade',
    fields: [
      'sggCd', 'umdNm', 'houseType', 'jibun', 'totalFloorAr', 'plottageAr',
      ...DEAL_DATE, 'dealAmount', 'buildYear',
      ...CANCEL, ...AGENT, ...PARTY,
    ],
    map: {
      name: 'houseType', jibun: 'jibun', area: 'totalFloorAr',
      builtYear: 'buildYear', amount: 'dealAmount',
    },
    // 단독/다가구는 지번이 일부만 공개된다.
    geocode: 'partial',
    cancellable: true,
  },

  'detached/rent': {
    portalId: '15126472',
    service: 'RTMSDataSvcSHRent',
    fields: [
      'sggCd', 'umdNm', 'houseType', 'totalFloorAr',
      ...DEAL_DATE, ...RENT_MONEY, 'buildYear', ...RENT_CONTRACT,
    ],
    map: {
      // houseType은 "다가구"처럼 주택 종류일 뿐 건물 식별자가 아니다.
      name: 'houseType',
      area: 'totalFloorAr', builtYear: 'buildYear',
      deposit: 'deposit', monthlyRent: 'monthlyRent',
    },
    // 지번이 없다. 위치 필드가 sggCd·umdNm뿐이라 법정동 중심점 외에는 특정할 수 없다.
    geocode: 'umd',
    cancellable: false,
  },

  'land/sale': {
    portalId: '15126466',
    service: 'RTMSDataSvcLandTrade',
    fields: [
      'sggCd', 'sggNm', 'umdNm', 'jibun', 'jimok', 'landUse',
      ...DEAL_DATE, 'dealArea', 'dealAmount', 'shareDealingType',
      ...CANCEL, ...AGENT,
    ],
    map: {
      name: 'jimok', jibun: 'jibun', area: 'dealArea', amount: 'dealAmount',
    },
    // 기술문서 응답 예제의 지번이 `2**`로 마스킹되어 있다.
    geocode: 'partial',
    cancellable: true,
  },
};

export const datasetKeys = (): readonly DatasetKey[] =>
  Object.keys(DATASETS) as readonly DatasetKey[];
