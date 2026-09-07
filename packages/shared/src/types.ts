/** MVP에서 다루는 부동산 유형. 국토부 API의 서비스 분리 단위와 일치한다. */
export type PropertyType = 'apartment' | 'officetel' | 'rowhouse' | 'detached' | 'land';

/** 거래 유형. 토지는 매매만 존재한다. */
export type TradeType = 'sale' | 'rent';

/**
 * 부동산 유형과 거래 유형의 조합. 국토부 서비스 1종에 대응한다.
 *
 * 토지는 매매만 존재하므로 `land/rent`는 타입 수준에서 배제한다.
 * 단순 템플릿 조합으로 두면 없는 서비스를 참조하는 코드가 컴파일된다.
 */
export type DatasetKey = `${Exclude<PropertyType, 'land'>}/${TradeType}` | 'land/sale';

/**
 * 시군구 한 곳. `sggCd`가 실거래가 API의 `LAWD_CD`다.
 *
 * `queryable`이 false인 항목은 하위 일반구로 나뉘는 상위 시(예: 경기도 수원시)로,
 * 하위 구와 중복 조회가 되므로 수집 대상에서 제외한다.
 */
export interface Region {
  readonly sggCd: string;
  readonly name: string;
  readonly sidoCd: string;
  readonly sidoName: string;
  readonly sggName: string;
  readonly queryable: boolean;
  /** 이 항목이 일반구일 때 상위 시의 코드 */
  readonly parentCd?: string;
  /** 이 항목이 하위 일반구를 가진 상위 시일 때 true */
  readonly hasSubGu?: boolean;
}

export interface RegionCatalog {
  readonly generatedAt: string;
  readonly source: string;
  readonly note: string;
  readonly totalSggLevel: number;
  readonly queryableCount: number;
  readonly regions: readonly Region[];
}

/** 폐지된 시군구 코드와 현행 코드의 대응. */
export interface LegacyCodeMapping {
  readonly legacyCd: string;
  readonly legacyName: string;
  readonly currentCd: string;
  readonly currentName: string;
}

export interface LegacyCodeCatalog {
  readonly generatedAt: string;
  readonly note: string;
  readonly sidoSuccessor: Readonly<Record<string, string>>;
  readonly count: number;
  readonly mappings: readonly LegacyCodeMapping[];
}
