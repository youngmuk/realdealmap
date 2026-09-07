import { DurableObject } from 'cloudflare:workers';

import { budgetDay, decide, type Decision, type RegionState } from './policy.js';

/**
 * 지역 하나의 갱신 상태를 쥔 Durable Object.
 *
 * 시군구 코드를 DO 이름으로 삼아 지역당 인스턴스가 하나만 존재하게 한다(§AD-3).
 * **중복 차단이 성립하려면 판정과 기록이 원자적이어야 한다.** Worker 안에서 KV를
 * 읽고 쓰면 두 요청이 같은 값을 읽고 둘 다 통과하는 창이 생긴다. DO는 요청을
 * 직렬화하므로 그 창이 없다 — 이게 DO를 쓰는 유일한 이유다.
 *
 * 저장은 SQLite 백엔드를 쓴다. Workers Free에서 동작하고 무료 한도 안에 들어간다.
 */
export class RegionTrigger extends DurableObject<Env> {
  /**
   * 트리거를 판정하고, 받아들이면 그 사실을 같은 호출 안에서 기록한다.
   *
   * 예산은 전역이라 이 DO가 가질 수 없다. 호출자가 현재 사용량을 넘겨주고,
   * 받아들여진 경우에만 호출자가 예산을 올린다.
   */
  async claim(usedToday: number): Promise<Decision> {
    const now = Date.now();
    const state = await this.#read();
    const decision = decide(state, now, usedToday);

    if (decision.kind === 'accept') {
      await this.ctx.storage.put({ lastTriggeredAt: now, running: true });
    }
    return decision;
  }

  /**
   * 갱신이 끝났다고 표시한다.
   *
   * Actions가 끝나면 이걸 불러 줘야 다음 트리거가 통과한다. 다만 **부르지 않아도
   * 영구히 막히지는 않는다** — `running`은 최소 간격이 지나면 무의미해지고,
   * 워크플로가 죽어 콜백이 영영 안 올 수도 있기 때문이다(아래 `#read` 참조).
   */
  async finish(): Promise<void> {
    await this.ctx.storage.put({ running: false });
  }

  async state(): Promise<RegionState> {
    return this.#read();
  }

  /**
   * `running`을 시간으로 만료시킨다.
   *
   * 완료 콜백에만 의존하면 워크플로가 취소·크래시했을 때 그 지역이 **영구히 잠긴다.**
   * 사람이 손댈 방법도 없다. 최소 간격이 지나면 갱신이 끝났든 아니든 잠금을 푼다 —
   * 최악의 경우 중복 실행이 한 번 생기지만, 그건 concurrency 그룹이 막아 준다.
   */
  async #read(): Promise<RegionState> {
    const lastTriggeredAt = await this.ctx.storage.get<number>('lastTriggeredAt');
    const running = (await this.ctx.storage.get<boolean>('running')) ?? false;
    if (!running || lastTriggeredAt === undefined) return { lastTriggeredAt, running: false };

    const stale = Date.now() - lastTriggeredAt > LOCK_TTL_MS;
    return { lastTriggeredAt, running: stale ? false : true };
  }
}

/** 완료 콜백이 오지 않아도 이 시간이 지나면 잠금을 푼다. */
const LOCK_TTL_MS = 30 * 60 * 1000;

/**
 * 전역 일일 예산을 세는 Durable Object.
 *
 * 인스턴스가 하나뿐이라 전 세계 요청이 여기로 모인다. 그래서 **받아들여진 트리거만**
 * 세고, 거절은 세지 않는다 — 거절까지 여기로 보내면 이 DO가 병목이자 공격 표적이 된다.
 */
export class TriggerBudget extends DurableObject<Env> {
  async used(): Promise<number> {
    return this.#today();
  }

  /** 사용량을 1 올리고 올린 뒤 값을 돌려준다. */
  async consume(): Promise<number> {
    const day = budgetDay(Date.now());
    const next = (await this.#today()) + 1;
    await this.ctx.storage.put({ day, count: next });
    return next;
  }

  /** 날짜가 바뀌면 0부터 다시 센다. 만료 작업을 따로 두지 않기 위해서다. */
  async #today(): Promise<number> {
    const day = budgetDay(Date.now());
    const stored = await this.ctx.storage.get<string>('day');
    if (stored !== day) return 0;
    return (await this.ctx.storage.get<number>('count')) ?? 0;
  }
}

export interface Env {
  readonly REGION_TRIGGER: DurableObjectNamespace<RegionTrigger>;
  readonly TRIGGER_BUDGET: DurableObjectNamespace<TriggerBudget>;
  /** repository_dispatch용 GitHub 토큰. wrangler secret으로만 넣는다 */
  readonly GITHUB_DISPATCH_TOKEN: string;
  readonly GITHUB_REPO: string;
}
