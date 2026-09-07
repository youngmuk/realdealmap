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
  usedToday: number,
  minIntervalSeconds = MIN_INTERVAL_SECONDS,
  budget = DAILY_TRIGGER_BUDGET,
): Decision => {
  if (state.running) return { kind: 'running' };

  if (state.lastTriggeredAt !== undefined) {
    const elapsed = (now - state.lastTriggeredAt) / 1000;
    if (elapsed < minIntervalSeconds) {
      return { kind: 'fresh', retryAfterSeconds: Math.ceil(minIntervalSeconds - elapsed) };
    }
  }

  if (usedToday >= budget) return { kind: 'budget' };
  return { kind: 'accept' };
};

/** 예산이 초기화되는 날짜 키. UTC 기준으로 두어 서버 위치에 흔들리지 않게 한다. */
export const budgetDay = (now: number): string => new Date(now).toISOString().slice(0, 10);
