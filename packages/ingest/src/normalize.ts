import type { DatasetKey, PropertyType, TradeType } from '@realdealmap/shared';

import { DATASETS, type GeocodePrecision } from './datasets.js';
import type { RawItem } from './parse.js';

/**
 * 정규화된 거래 한 건.
 *
 * 금액은 원천과 같은 **만원 단위 정수**로 둔다. 원 단위로 바꾸면
 * 자릿수만 늘고 원천과 대조가 어려워진다.
 * `raw`에 원문을 통째로 보존해 유형별 고유 항목까지 상세화면에 낼 수 있다(FR-3).
 */
export interface Transaction {
  readonly datasetKey: DatasetKey;
  readonly propertyType: PropertyType;
  readonly tradeType: TradeType;

  readonly sggCd: string;
  readonly umdNm: string;
  /** 지번 원문. 마스킹된 값(`2**`)도 그대로 둔다 */
  readonly jibun: string | null;
  readonly jibunMasked: boolean;
  /** 단지명·주택유형 등 사람이 읽는 이름 */
  readonly name: string | null;

  readonly contractedOn: string;
  readonly areaSqm: number | null;
  /** 지하는 음수다 (실응답에 `-1`이 있다) */
  readonly floor: number | null;
  readonly builtYear: number | null;

  /** 매매가(만원). 전월세는 null */
  readonly amount: number | null;
  /** 보증금(만원). 매매는 null */
  readonly deposit: number | null;
  /** 월세(만원). 전세는 0이며 이는 결측이 아니다 */
  readonly monthlyRent: number | null;

  readonly cancelled: boolean;
  /** 해제일. 형식을 해석하지 못하면 null이고 원문은 `raw`에 남는다 */
  readonly cancelledOn: string | null;

  /** 이 **레코드**의 좌표 정밀도. 유형 기본값을 실제 지번 값으로 보정한 결과다 */
  readonly precision: GeocodePrecision;
  readonly raw: RawItem;
}

export class NormalizeError extends Error {
  constructor(readonly field: string, readonly value: string, reason: string) {
    super(`${field}: ${reason} (${JSON.stringify(value)})`);
    this.name = 'NormalizeError';
  }
}

const blank = (raw: string | undefined): boolean => raw === undefined || raw.trim() === '';

/** 쉼표가 섞인 만원 단위 금액. 빈 값은 null이고 `"0"`은 유효한 0이다. */
const money = (raw: string | undefined, field: string): number | null => {
  if (blank(raw)) return null;
  const digits = (raw as string).replace(/,/g, '').trim();
  if (!/^\d+$/.test(digits)) throw new NormalizeError(field, raw as string, '금액 형식이 아님');
  return Number(digits);
};

const decimal = (raw: string | undefined, field: string): number | null => {
  if (blank(raw)) return null;
  const value = (raw as string).trim();
  if (!/^\d+(\.\d+)?$/.test(value)) throw new NormalizeError(field, value, '실수 형식이 아님');
  return Number(value);
};

/** 층수. 지하를 음수로 주므로 부호를 허용한다. */
const integer = (raw: string | undefined, field: string): number | null => {
  if (blank(raw)) return null;
  const value = (raw as string).trim();
  if (!/^-?\d+$/.test(value)) throw new NormalizeError(field, value, '정수 형식이 아님');
  return Number(value);
};

const pad = (value: number): string => String(value).padStart(2, '0');

/**
 * 계약일 3분할을 `YYYY-MM-DD`로 합친다.
 * 달력에 없는 날짜(2월 30일 등)는 오류다 — 자동 보정하면 잘못된 날이 조용히 들어간다.
 */
const contractDate = (item: RawItem): string => {
  const year = integer(item['dealYear'], 'dealYear');
  const month = integer(item['dealMonth'], 'dealMonth');
  const day = integer(item['dealDay'], 'dealDay');
  if (year === null || month === null || day === null) {
    throw new NormalizeError('dealYear/Month/Day', JSON.stringify([year, month, day]), '계약일 누락');
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new NormalizeError('dealDate', `${year}-${month}-${day}`, '달력에 없는 날짜');
  }
  return `${year}-${pad(month)}-${pad(day)}`;
};

/**
 * 해제일 원문을 `YYYY-MM-DD`로 바꾼다.
 *
 * **미검증 경로.** 25개 조합을 훑었으나 해제건이 하나도 없어 실제 형식을 확인하지 못했다.
 * 그럴듯한 형식만 받아들이고, 모르면 **날짜를 지어내지 않고 null**을 돌려준다.
 * 원문은 `raw.cdealDay`에 남으므로 나중에 형식이 확인되면 재처리할 수 있다.
 */
export const parseCancelDate = (raw: string | undefined): string | null => {
  if (blank(raw)) return null;
  const digits = (raw as string).replace(/[^\d]/g, '');
  if (digits.length === 8) {
    const iso = `${digits.slice(0, 4)}-${digits.slice(4, 6)}-${digits.slice(6, 8)}`;
    return Number.isNaN(Date.parse(iso)) ? null : iso;
  }
  if (digits.length === 6) {
    // YY.MM.DD로 본다. 실거래 데이터는 2006년 이후이므로 20xx로 편다.
    const iso = `20${digits.slice(0, 2)}-${digits.slice(2, 4)}-${digits.slice(4, 6)}`;
    return Number.isNaN(Date.parse(iso)) ? null : iso;
  }
  return null;
};

/** 유형 기본 등급을 이 레코드의 실제 지번 값으로 보정한다. */
const precisionOf = (base: GeocodePrecision, jibun: string | null): GeocodePrecision => {
  if (jibun === null) return 'umd';
  if (jibun.includes('*')) return 'partial';
  return base;
};

const textOrNull = (item: RawItem, field: string | undefined): string | null => {
  if (field === undefined) return null;
  const value = item[field];
  return blank(value) ? null : (value as string).trim();
};

/** item 하나를 정규화한다. 값이 규칙에 맞지 않으면 {@link NormalizeError}. */
export const normalizeItem = (key: DatasetKey, item: RawItem): Transaction => {
  const spec = DATASETS[key];
  const [propertyType, tradeType] = key.split('/') as [PropertyType, TradeType];

  const sggCd = item['sggCd']?.trim() ?? '';
  if (!/^\d{5}$/.test(sggCd)) throw new NormalizeError('sggCd', sggCd, '5자리 숫자가 아님');

  const jibun = textOrNull(item, spec.map.jibun);
  const cancelled = !blank(item['cdealType']);

  return {
    datasetKey: key,
    propertyType,
    tradeType,
    sggCd,
    umdNm: item['umdNm']?.trim() ?? '',
    jibun,
    jibunMasked: jibun !== null && jibun.includes('*'),
    name: textOrNull(item, spec.map.name),
    contractedOn: contractDate(item),
    areaSqm: decimal(spec.map.area ? item[spec.map.area] : undefined, spec.map.area ?? 'area'),
    floor: integer(spec.map.floor ? item[spec.map.floor] : undefined, spec.map.floor ?? 'floor'),
    builtYear: integer(
      spec.map.builtYear ? item[spec.map.builtYear] : undefined,
      spec.map.builtYear ?? 'builtYear',
    ),
    amount: money(spec.map.amount ? item[spec.map.amount] : undefined, spec.map.amount ?? 'amount'),
    deposit: money(
      spec.map.deposit ? item[spec.map.deposit] : undefined,
      spec.map.deposit ?? 'deposit',
    ),
    monthlyRent: money(
      spec.map.monthlyRent ? item[spec.map.monthlyRent] : undefined,
      spec.map.monthlyRent ?? 'monthlyRent',
    ),
    // 전월세 4종은 해제 항목 자체가 없으므로 항상 false다(§3.1).
    cancelled: spec.cancellable && cancelled,
    cancelledOn: spec.cancellable && cancelled ? parseCancelDate(item['cdealDay']) : null,
    precision: precisionOf(spec.geocode, jibun),
    raw: item,
  };
};

export interface NormalizeFailure {
  readonly index: number;
  readonly message: string;
  readonly item: RawItem;
}

export interface NormalizeReport {
  readonly transactions: readonly Transaction[];
  readonly failures: readonly NormalizeFailure[];
}

/**
 * 여러 item을 정규화한다. 한 건이 깨져도 나머지를 살리되,
 * 실패를 조용히 버리지 않고 `failures`로 돌려준다.
 */
export const normalizeAll = (key: DatasetKey, items: readonly RawItem[]): NormalizeReport => {
  const transactions: Transaction[] = [];
  const failures: NormalizeFailure[] = [];

  items.forEach((item, index) => {
    try {
      transactions.push(normalizeItem(key, item));
    } catch (error) {
      failures.push({
        index,
        message: error instanceof Error ? error.message : String(error),
        item,
      });
    }
  });

  return { transactions, failures };
};
