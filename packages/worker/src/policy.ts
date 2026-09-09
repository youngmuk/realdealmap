// 배럴(`@realdealmap/shared`)이 아니라 생성 모듈을 직접 가리킨다.
// 배럴은 `regions.ts`를 재수출하고 그건 node:fs를 쓴다 — Worker에는 파일시스템이 없다.
// 지금은 번들러가 트리셰이킹으로 걷어내 주지만, 그건 보장이 아니라 우연이다.
// 배럴에 side-effect 있는 모듈이 하나만 추가돼도 조용히 깨진다.
import { isQueryableSggCd } from '@realdealmap/shared/codes';

/**
 * 트리거 정책 — 순수 함수만 둔다.
 *
 * `POST /v1/refresh`는 **부수효과가 있는 공개 엔드포인트**다. 인증이 없으므로
 * 누구나 부를 수 있고, 남용되면 국토부 쿼터가 소진되어 서비스 전체가 갱신을 멈춘다(R-11).
 * 방어가 셋인데, 전부 여기 모아 두고 DO·핸들러는 이 판정을 쓰기만 한다 —
 * 정책이 여기저기 흩어지면 한 군데만 고쳐 놓고 막았다고 착각하게 된다.
 */

/** 지역별 최소 트리거 간격. 매니페스트 TTL과 같아야 한다 — 더 자주 불러도 새 데이터가 없다. */
export const MIN_INTERVAL_SECONDS = 3600;

/** 하루 전역 트리거 예산. 국토부 일일 쿼터에서 역산한 상한이다. */
export const DAILY_TRIGGER_BUDGET = 500;

/**
 * 한 시간 전역 트리거 예산.
 *
 * **일일 예산만으로는 한 사람이 하루치를 몇 초 만에 비울 수 있다.** 지역별 최소
 * 간격은 *같은* 지역의 반복만 막는다. 시군구 코드는 5자리 공공 코드이고 카탈로그도
 * 이 저장소에 공개돼 있어, 서로 다른 500개 지역으로 한 번씩만 쏘면 셋 다 통과한다.
 * 그러면 남은 하루 동안 **실제 사용자의 갱신이 전부 429**가 된다.
 *
 * IP로 세지 않는 이유는 국내 이동통신이 NAT를 크게 묶기 때문이다. 한 IP 뒤에
 * 수천 명이 있을 수 있어, IP당 상한은 공격자보다 실사용자를 먼저 막는다.
 * 대신 **시간 단위로 회복**시킨다 — 몰아친 요청은 그 시간대만 소진하고,
 * 다음 시간에는 정상으로 돌아온다. 하루를 통째로 잃지 않는 것이 목적이다.
 *
 * 60은 일일 예산(500)보다 크게 잡을 이유가 없으면서, 이 앱 규모에서 정상
 * 트래픽이 한 시간에 닿을 일이 없는 수다.
 */
export const HOURLY_TRIGGER_BUDGET = 60;

/** 갱신 1회의 예상 소요. 앱이 재조회 시점을 잡는 데 쓴다. */
export const ETA_SECONDS = 120;

export type Decision =
  | { readonly kind: 'accept' }
  /** 이미 같은 지역이 돌고 있다. 실패가 아니라 정상 응답이다(§5.2) */
  | { readonly kind: 'running' }
  /** 최근에 갱신했다. TTL 안이라 새로 부를 이유가 없다 */
  | { readonly kind: 'fresh'; readonly retryAfterSeconds: number }
  /** 오늘 예산을 다 썼다 */
  | { readonly kind: 'budget' }
  /** 조회 대상 시군구가 아니다 */
  | { readonly kind: 'unknownRegion' };

/** 지금까지 쓴 전역 예산. 두 창을 함께 본다. */
export interface BudgetUsage {
  readonly today: number;
  readonly thisHour: number;
}

export interface RegionState {
  /** 마지막으로 트리거가 받아들여진 시각 (epoch ms). 없으면 한 번도 없다 */
  readonly lastTriggeredAt: number | undefined;
  readonly running: boolean;
}

/**
 * 시군구 코드 검증.
 *
 * 형식만 보면 부족하다. 원천은 실재하지 않는 코드에도 `200 · 0건`으로 답하므로(R-14),
 * 오타가 "거래 없음"으로 위장되어 그 지역이 조용히 빈 채로 남는다.
 * 카탈로그에 있는 코드만 통과시킨다.
 */
export const isValidSggCd = (value: unknown): value is string =>
  typeof value === 'string' && /^\d{5}$/.test(value) && isQueryableSggCd(value);

/**
 * 트리거를 받아들일지 판정한다.
 *
 * 순서가 의미를 갖는다. 예산을 지역 상태보다 **먼저** 보면, 이미 신선한 지역에 대한
 * 무의미한 요청이 예산을 갉아먹는다. 반대로 두면 그런 요청은 예산을 건드리지 않는다.
 */
export const decide = (
  state: RegionState,
  now: number,
  used: BudgetUsage,
  minIntervalSeconds = MIN_INTERVAL_SECONDS,
  budget = DAILY_TRIGGER_BUDGET,
  hourlyBudget = HOURLY_TRIGGER_BUDGET,
): Decision => {
  if (state.running) return { kind: 'running' };

  if (state.lastTriggeredAt !== undefined) {
    const elapsed = (now - state.lastTriggeredAt) / 1000;
    if (elapsed < minIntervalSeconds) {
      return { kind: 'fresh', retryAfterSeconds: Math.ceil(minIntervalSeconds - elapsed) };
    }
  }

  if (used.today >= budget) return { kind: 'budget' };
  // 시간 예산이 먼저 차면 하루를 잃는 대신 그 시간만 잃는다. 앱에는 같은
  // `budget`으로 답하되 다시 물어볼 시각을 다르게 준다.
  if (used.thisHour >= hourlyBudget) return { kind: 'budget' };
  return { kind: 'accept' };
};

/** 예산이 초기화되는 날짜 키. UTC 기준으로 두어 서버 위치에 흔들리지 않게 한다. */
export const budgetDay = (now: number): string => new Date(now).toISOString().slice(0, 10);

/** 시간 예산이 초기화되는 키. 날짜 키와 같은 이유로 UTC다. */
export const budgetHour = (now: number): string => new Date(now).toISOString().slice(0, 13);
