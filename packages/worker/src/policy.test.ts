import { describe, expect, test } from 'vitest';

import {
  type BudgetUsage,
  budgetDay,
  budgetHour,
  DAILY_TRIGGER_BUDGET,
  decide,
  HOURLY_TRIGGER_BUDGET,
  isValidSggCd,
  MIN_INTERVAL_SECONDS,
  type RegionState,
} from './policy.js';

const NOW = Date.UTC(2026, 8, 7, 12, 0, 0);
const idle: RegionState = { lastTriggeredAt: undefined, running: false };
const ago = (seconds: number): RegionState => ({
  lastTriggeredAt: NOW - seconds * 1000,
  running: false,
});

/** 일일 사용량만 신경 쓰는 검사에서 쓰는 지름길. 시간 사용량은 0으로 둔다. */
const used = (today: number): BudgetUsage => ({ today, thisHour: 0 });

describe('시군구 검증', () => {
  test('카탈로그에 있는 코드만 통과한다', () => {
    expect(isValidSggCd('11680')).toBe(true);
  });

  // 형식만 보면 통과하지만 실재하지 않는 코드들. 원천은 이런 요청에도
  // 오류가 아니라 0건으로 답하므로(R-14) 여기서 막지 않으면 조용히 빈 지역이 된다.
  test.each(['99999', '00000', '41110'])('형식은 맞지만 조회 대상이 아닌 %s는 거부한다', (code) => {
    expect(isValidSggCd(code)).toBe(false);
  });

  test.each(['1168', '116800', '', 'abcde', '11-68', ' 11680'])(
    '형식이 틀린 %s는 거부한다',
    (code) => {
      expect(isValidSggCd(code)).toBe(false);
    },
  );

  test.each([null, undefined, 11680, {}, [], true])('문자열이 아닌 %s는 거부한다', (value) => {
    expect(isValidSggCd(value)).toBe(false);
  });
});

describe('트리거 판정', () => {
  test('처음이면 받아들인다', () => {
    expect(decide(idle, NOW, used(0))).toEqual({ kind: 'accept' });
  });

  test('이미 돌고 있으면 실패가 아니라 running이다', () => {
    expect(decide({ lastTriggeredAt: NOW, running: true }, NOW, used(0))).toEqual({ kind: 'running' });
  });

  test('최소 간격 안이면 남은 시간을 알려준다', () => {
    const d = decide(ago(600), NOW, used(0));
    expect(d.kind).toBe('fresh');
    expect(d.kind === 'fresh' && d.retryAfterSeconds).toBe(MIN_INTERVAL_SECONDS - 600);
  });

  test('최소 간격을 넘기면 다시 받아들인다', () => {
    expect(decide(ago(MIN_INTERVAL_SECONDS + 1), NOW, used(0))).toEqual({ kind: 'accept' });
  });

  test('경계값에서 받아들인다', () => {
    expect(decide(ago(MIN_INTERVAL_SECONDS), NOW, used(0))).toEqual({ kind: 'accept' });
  });

  test('예산을 다 쓰면 거절한다', () => {
    expect(decide(idle, NOW, used(DAILY_TRIGGER_BUDGET))).toEqual({ kind: 'budget' });
  });

  // 순서가 뒤집히면, 이미 신선한 지역에 대한 무의미한 요청이 예산을 갉아먹는다.
  // 그렇게 되면 공격자가 한 지역만 두드려도 전국 갱신을 멈출 수 있다.
  test('신선한 지역은 예산을 건드리기 전에 걸러진다', () => {
    expect(decide(ago(10), NOW, used(DAILY_TRIGGER_BUDGET)).kind).toBe('fresh');
  });

  test('실행 중 판정이 예산보다 앞선다', () => {
    expect(decide({ lastTriggeredAt: NOW, running: true }, NOW, used(DAILY_TRIGGER_BUDGET)).kind).toBe(
      'running',
    );
  });
});

describe('예산 날짜 키', () => {
  test('UTC 날짜로 끊는다', () => {
    expect(budgetDay(Date.UTC(2026, 8, 7, 23, 59, 59))).toBe('2026-09-07');
    expect(budgetDay(Date.UTC(2026, 8, 8, 0, 0, 0))).toBe('2026-09-08');
  });

  test('같은 날의 다른 시각은 같은 키다', () => {
    expect(budgetDay(Date.UTC(2026, 8, 7, 0, 0, 0))).toBe(budgetDay(Date.UTC(2026, 8, 7, 18, 0, 0)));
  });
});

describe('한 사람이 하루치를 비우지 못하게 한다', () => {
  // 지역별 최소 간격은 **같은** 지역의 반복만 막는다. 시군구 코드는 공개된
  // 5자리 값이라, 서로 다른 지역으로 한 번씩만 쏘면 그 게이트를 전부 통과한다.
  // 시간 예산이 없으면 하루 예산 500이 몇 초 만에 비고, 남은 하루 동안
  // 실제 사용자의 갱신이 전부 429가 된다.
  test('처음 보는 지역이라도 시간 예산이 차면 막는다', () => {
    expect(decide(idle, NOW, { today: 100, thisHour: HOURLY_TRIGGER_BUDGET })).toEqual({
      kind: 'budget',
    });
  });

  test('한 시간이 지나면 다시 열린다 — 하루를 통째로 잃지 않는다', () => {
    // 창이 바뀌면 사용량은 0부터 다시 센다(budgetHour). 그 상태를 흉내낸다.
    expect(decide(idle, NOW, { today: 100, thisHour: 0 })).toEqual({ kind: 'accept' });
  });

  test('시간 예산이 남아도 하루 예산이 차면 막는다', () => {
    expect(decide(idle, NOW, { today: DAILY_TRIGGER_BUDGET, thisHour: 0 })).toEqual({
      kind: 'budget',
    });
  });

  test('시간 예산은 하루 예산보다 작다 — 크면 있으나 마나다', () => {
    expect(HOURLY_TRIGGER_BUDGET).toBeLessThan(DAILY_TRIGGER_BUDGET);
  });
});

describe('시간 예산의 창', () => {
  test('같은 시간 안에서는 같은 키다', () => {
    expect(budgetHour(Date.UTC(2026, 8, 7, 13, 0, 0))).toBe(
      budgetHour(Date.UTC(2026, 8, 7, 13, 59, 59)),
    );
  });

  test('시간이 넘어가면 키가 바뀐다', () => {
    expect(budgetHour(Date.UTC(2026, 8, 7, 13, 59, 59))).not.toBe(
      budgetHour(Date.UTC(2026, 8, 7, 14, 0, 0)),
    );
  });

  // 날짜 키와 시간 키를 따로 두는 이유. 시간 키만으로 날짜를 유추하면
  // 하루가 지난 뒤에도 같은 시각이면 옛 합계를 되살린다.
  test('날짜가 달라도 시각이 같으면 키가 달라야 한다', () => {
    expect(budgetHour(Date.UTC(2026, 8, 7, 13, 0, 0))).not.toBe(
      budgetHour(Date.UTC(2026, 8, 8, 13, 0, 0)),
    );
  });
});
