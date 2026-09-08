/**
 * 갱신할 지역을 고르는 규칙 (T4.7).
 *
 * 두 워크플로가 쓴다.
 *
 * - `prewarm-hot` — 사람이 많이 볼 지역을 미리 데워 둔다. 그러지 않으면
 *   그 지역을 처음 연 사람이 갱신을 기다린다.
 * - `resync-cold` — 오래 손대지 않은 지역을 다시 맞춘다. 갱신은 사용자가
 *   열어야 걸리므로, 아무도 안 여는 지역은 영영 낡은 채로 남는다.
 *
 * **어느 쪽도 "전부"를 고르지 않는다.** 한 실행이 쓰는 호출 수가 입력으로
 * 묶여 있어야 쿼터를 넘길 수가 없다 — 적재(backfill)와 같은 원칙이다.
 */
import type { RegionIndex } from './region-index.js';

/**
 * 이보다 최근에 갱신됐으면 건너뛴다.
 *
 * 앱의 TTL이 1시간이라 그보다 짧게 잡으면 방금 갱신된 것을 또 부른다.
 * 여유를 조금 둬서 예열이 사용자 갱신과 엇갈려 겹치는 것을 줄인다.
 */
export const HOT_MIN_AGE_HOURS = 3;

/**
 * 재동기는 이보다 오래된 것만 본다.
 *
 * 하루 안에 갱신된 지역은 다시 맞출 이유가 없다. 이 문턱이 없으면 전국이
 * 신선한 날에도 40개 지역을 헛돈다.
 */
export const COLD_MIN_AGE_HOURS = 24;

/** 갱신 시각을 밀리초로. 읽을 수 없으면 **가장 오래된 것**으로 친다. */
const refreshedMs = (value: string): number => {
  const ms = Date.parse(value);
  // 깨진 값을 "지금"으로 읽으면 그 지역이 영영 안 골라진다. 반대로 쳐야
  // 고장난 지역이 먼저 손질된다.
  return Number.isNaN(ms) ? Number.NEGATIVE_INFINITY : ms;
};

const olderThan = (index: RegionIndex, now: Date, hours: number) => {
  const cutoff = now.getTime() - hours * 3_600_000;
  return index.regions.filter((r) => refreshedMs(r.refreshedAt) < cutoff);
};

/**
 * 거래가 많은 지역부터 [limit]개.
 *
 * 사용량을 서버에 남기지 않기로 했으므로 진짜 인기는 알 수 없다. 거래 건수를
 * 대리 지표로 쓴다 — 정확하지 않지만, 아무 근거 없이 지역을 손으로 적어 두는
 * 것보다는 낫고 지역이 바뀌어도 저절로 따라간다.
 */
export const pickHot = (
  index: RegionIndex,
  limit: number,
  now: Date = new Date(),
): string[] =>
  olderThan(index, now, HOT_MIN_AGE_HOURS)
    // 건수가 같을 때 코드로 가른다. 실행할 때마다 다른 지역이 뽑히면
    // "어제 무엇이 돌았는지"를 로그 없이는 알 수 없다.
    .toSorted((a, b) => b.records - a.records || a.sggCd.localeCompare(b.sggCd))
    .slice(0, Math.max(0, limit))
    .map((r) => r.sggCd);

/** 갱신이 오래된 지역부터 [limit]개. */
export const pickCold = (
  index: RegionIndex,
  limit: number,
  now: Date = new Date(),
): string[] =>
  olderThan(index, now, COLD_MIN_AGE_HOURS)
    .toSorted(
      (a, b) =>
        refreshedMs(a.refreshedAt) - refreshedMs(b.refreshedAt) ||
        a.sggCd.localeCompare(b.sggCd),
    )
    .slice(0, Math.max(0, limit))
    .map((r) => r.sggCd);
