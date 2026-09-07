import { describe, expect, test } from 'vitest';

import {
  budgetDay,
  DAILY_TRIGGER_BUDGET,
  decide,
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
    expect(decide(idle, NOW, 0)).toEqual({ kind: 'accept' });
  });

  test('이미 돌고 있으면 실패가 아니라 running이다', () => {
    expect(decide({ lastTriggeredAt: NOW, running: true }, NOW, 0)).toEqual({ kind: 'running' });
  });

  test('최소 간격 안이면 남은 시간을 알려준다', () => {
    const d = decide(ago(600), NOW, 0);
    expect(d.kind).toBe('fresh');
    expect(d.kind === 'fresh' && d.retryAfterSeconds).toBe(MIN_INTERVAL_SECONDS - 600);
  });

  test('최소 간격을 넘기면 다시 받아들인다', () => {
    expect(decide(ago(MIN_INTERVAL_SECONDS + 1), NOW, 0)).toEqual({ kind: 'accept' });
  });

  test('경계값에서 받아들인다', () => {
    expect(decide(ago(MIN_INTERVAL_SECONDS), NOW, 0)).toEqual({ kind: 'accept' });
  });

  test('예산을 다 쓰면 거절한다', () => {
    expect(decide(idle, NOW, DAILY_TRIGGER_BUDGET)).toEqual({ kind: 'budget' });
  });

  // 순서가 뒤집히면, 이미 신선한 지역에 대한 무의미한 요청이 예산을 갉아먹는다.
  // 그렇게 되면 공격자가 한 지역만 두드려도 전국 갱신을 멈출 수 있다.
  test('신선한 지역은 예산을 건드리기 전에 걸러진다', () => {
    expect(decide(ago(10), NOW, DAILY_TRIGGER_BUDGET).kind).toBe('fresh');
  });

  test('실행 중 판정이 예산보다 앞선다', () => {
    expect(decide({ lastTriggeredAt: NOW, running: true }, NOW, DAILY_TRIGGER_BUDGET).kind).toBe(
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
