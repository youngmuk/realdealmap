import { queryableRegions } from '@realdealmap/shared';
import { describe, expect, test } from 'vitest';

import { datasetKeys } from './datasets.js';
import { buildTasks, countByDataset, hotTasks, recentPeriods, TaskError, taskLabel } from './tasks.js';

const AT = new Date(Date.UTC(2026, 8, 7));

describe('최근 연월', () => {
  test('기준월부터 과거로 나열한다', () => {
    expect(recentPeriods(AT, 4)).toEqual(['202609', '202608', '202607', '202606']);
  });

  test('연도 경계를 넘는다', () => {
    expect(recentPeriods(new Date(Date.UTC(2026, 1, 15)), 3)).toEqual(['202602', '202601', '202512']);
  });

  test('한 달만 요청할 수 있다', () => {
    expect(recentPeriods(AT, 1)).toEqual(['202609']);
  });

  test.each([0, -1, 1.5])('개월 수 %s는 거부한다', (count) => {
    expect(() => recentPeriods(AT, count)).toThrow(TaskError);
  });
});

describe('작업목록 생성', () => {
  const options = { months: 12, hotMonths: 3, now: AT };

  test('전국 · 9종 · 12개월의 총량이 계산과 맞는다', () => {
    const tasks = buildTasks(options);
    const regions = queryableRegions().length;
    expect(regions).toBe(256);
    expect(tasks).toHaveLength(regions * 9 * 12);
    // 선행 문서의 27,000건은 250개 지역 기준 추정치였다. 실제 카탈로그로는 27,648건이다.
    expect(tasks).toHaveLength(27_648);
  });

  test('hot은 최근 3개월분이다', () => {
    const hot = hotTasks(buildTasks(options));
    expect(hot).toHaveLength(256 * 9 * 3);
    expect(hot).toHaveLength(6_912);
    expect(new Set(hot.map((t) => t.period))).toEqual(new Set(['202609', '202608', '202607']));
  });

  test('쿼터는 유형별로 부여되므로 유형별로 센다', () => {
    const counts = countByDataset(hotTasks(buildTasks(options)));
    expect(Object.keys(counts)).toHaveLength(9);
    // 유형 하나당 768건이면 일일 한도 10,000에 한참 못 미친다.
    for (const key of datasetKeys()) expect(counts[key], key).toBe(768);
  });

  test('순서가 결정적이다 — 중단된 수집을 이어받을 수 있다', () => {
    const a = buildTasks(options).map(taskLabel);
    const b = buildTasks(options).map(taskLabel);
    expect(b).toEqual(a);
  });

  test('작업이 중복되지 않는다', () => {
    const labels = buildTasks(options).map(taskLabel);
    expect(new Set(labels).size).toBe(labels.length);
  });

  test('대상 지역과 유형을 좁힐 수 있다', () => {
    const tasks = buildTasks({
      ...options,
      sggCodes: ['11110'],
      datasets: ['land/sale'],
      months: 2,
      hotMonths: 1,
    });
    expect(tasks.map(taskLabel)).toEqual([
      '11110/land/sale/202609',
      '11110/land/sale/202608',
    ]);
    expect(tasks.map((t) => t.hot)).toEqual([true, false]);
  });

  test('조회 불가 상위 시는 기본 목록에 없다', () => {
    const codes = new Set(buildTasks({ ...options, months: 1, hotMonths: 1 }).map((t) => t.sggCd));
    // 수원시(41110)는 하위 일반구로 조회해야 한다.
    expect(codes.has('41110')).toBe(false);
    expect(codes.has('41111')).toBe(true);
  });

  test('hot이 전체보다 크면 거부한다', () => {
    expect(() => buildTasks({ months: 3, hotMonths: 6, now: AT })).toThrow(TaskError);
  });
});
