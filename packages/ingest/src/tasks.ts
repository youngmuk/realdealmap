import { queryableRegions } from '@realdealmap/shared';
import type { DatasetKey } from '@realdealmap/shared';

import { datasetKeys } from './datasets.js';

/**
 * 수집 작업목록 생성.
 *
 * 작업 하나는 원천 호출 한 번의 단위인 (시군구 · 유형 · 계약연월)이다.
 * 전국 1회분이 곧 쿼터 소모량이므로, 무엇을 얼마나 자주 도는지가 §7 비용 산식의 입력이 된다.
 */

export interface Task {
  readonly sggCd: string;
  readonly datasetKey: DatasetKey;
  /** 계약 연월 `YYYYMM` */
  readonly period: string;
  /**
   * 최근 몇 달에 드는가. 원천 갱신주기가 일 1회이므로(§3.1)
   * 오래된 달은 자주 돌 이유가 없다 — AD-2의 hot/cold 구분이다.
   */
  readonly hot: boolean;
}

export class TaskError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TaskError';
  }
}

const pad2 = (value: number): string => String(value).padStart(2, '0');

/**
 * 기준 연월부터 과거로 `count`개의 `YYYYMM`을 만든다.
 * 첫 항목이 기준월이고 뒤로 갈수록 과거다.
 */
/**
 * 한 번에 다룰 수 있는 최대 개월 수.
 *
 * 제품 범위가 12개월이다. 상한이 워크플로 YAML에만 있으면 이 라이브러리를 직접 쓰는
 * 경로(로컬 실행, 다른 워크플로)에서 `--months=999` 같은 값이 그대로 통과해
 * 원천 API를 수천 회 두드린다. R2 쓰기는 `maxUploads`가 막지만 그건 이미
 * 국토부 쿼터를 태운 뒤다. 경계에서 막는다.
 */
export const MAX_MONTHS = 12;

export const recentPeriods = (from: Date, count: number): readonly string[] => {
  if (!Number.isInteger(count) || count < 1) throw new TaskError(`개월 수가 1 이상이 아님: ${count}`);
  if (count > MAX_MONTHS) throw new TaskError(`개월 수가 ${MAX_MONTHS}을 넘음: ${count}`);

  const periods: string[] = [];
  const year = from.getUTCFullYear();
  const month = from.getUTCMonth();
  for (let back = 0; back < count; back += 1) {
    const d = new Date(Date.UTC(year, month - back, 1));
    periods.push(`${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}`);
  }
  return periods;
};

export interface BuildTasksOptions {
  /** 기본값은 조회 가능한 시군구 전체(256개) */
  readonly sggCodes?: readonly string[];
  /** 기본값은 MVP 9종 전체 */
  readonly datasets?: readonly DatasetKey[];
  /** 총 몇 개월치를 볼 것인가 */
  readonly months: number;
  /** 앞의 몇 개월을 hot으로 볼 것인가 */
  readonly hotMonths: number;
  /** 기준 시각. 테스트에서 고정하기 위해 주입한다 */
  readonly now?: Date;
}

/**
 * 작업목록을 만든다. 순서는 (시군구 → 유형 → 최근월) 으로 결정적이다.
 * 결정적이어야 중단된 수집을 같은 지점에서 이어받을 수 있다.
 */
export const buildTasks = (options: BuildTasksOptions): readonly Task[] => {
  const { months, hotMonths, now = new Date() } = options;
  if (hotMonths > months) throw new TaskError(`hot(${hotMonths})이 전체(${months})보다 큼`);

  const codes = options.sggCodes ?? queryableRegions().map((r) => r.sggCd);
  const datasets = options.datasets ?? datasetKeys();
  const periods = recentPeriods(now, months);

  const tasks: Task[] = [];
  for (const sggCd of codes) {
    for (const datasetKey of datasets) {
      periods.forEach((period, index) => {
        tasks.push({ sggCd, datasetKey, period, hot: index < hotMonths });
      });
    }
  }
  return tasks;
};

export const hotTasks = (tasks: readonly Task[]): readonly Task[] => tasks.filter((t) => t.hot);

/** 서비스별 호출 수. 쿼터가 API(상세기능)별로 부여되므로 유형별로 센다(§3.1). */
export const countByDataset = (tasks: readonly Task[]): Readonly<Record<string, number>> => {
  const counts: Record<string, number> = {};
  for (const task of tasks) counts[task.datasetKey] = (counts[task.datasetKey] ?? 0) + 1;
  return counts;
};

/** 작업 하나를 사람이 읽는 문자열로. 로그와 재개 지점 표시에 쓴다. */
export const taskLabel = (task: Task): string =>
  `${task.sggCd}/${task.datasetKey}/${task.period}`;
