import { dispatchRefresh, DispatchError } from './dispatch.js';
import { isValidSggCd, ETA_SECONDS } from './policy.js';
import { type Env } from './region-do.js';

export { RegionTrigger, TriggerBudget } from './region-do.js';
export type { Env } from './region-do.js';

/**
 * 트리거 Worker.
 *
 * 경로가 하나뿐이다. 매니페스트도 청크도 앱이 R2에서 직접 받으므로 Worker를 거치지 않는다(AD-1).
 * 평상시 트래픽이 여기로 오지 않는다는 것이 무료 한도를 지키는 핵심이고,
 * 그래서 이 파일에 경로를 추가하는 일은 설계 변경으로 취급해야 한다.
 *
 * subrequest는 요청당 최대 3개다 — 예산 DO 1, 지역 DO 1, GitHub 1. 한도 50에 한참 못 미친다.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/health') return json({ ok: true });
    if (url.pathname !== '/v1/refresh') return json({ error: 'not_found' }, 404);
    if (request.method !== 'POST') {
      return json({ error: 'method_not_allowed' }, 405, { allow: 'POST' });
    }

    const sggCd = await readSggCd(request);
    if (sggCd === undefined) {
      // 어떤 코드가 왜 거절됐는지 밝히지 않는다. 카탈로그를 훑는 데 쓰일 이유가 없다.
      return json({ error: 'invalid_sgg' }, 400);
    }

    const budget = env.TRIGGER_BUDGET.get(env.TRIGGER_BUDGET.idFromName('global'));
    const region = env.REGION_TRIGGER.get(env.REGION_TRIGGER.idFromName(sggCd));

    const decision = await region.claim(await budget.used());

    switch (decision.kind) {
      case 'running':
        return json({ accepted: false, alreadyRunning: true });
      case 'fresh':
        return json({ accepted: false, alreadyRunning: false, retryAfterSeconds: decision.retryAfterSeconds });
      case 'budget':
        return json({ error: 'quota_exhausted' }, 429, { 'retry-after': '3600' });
      case 'unknownRegion':
        return json({ error: 'invalid_sgg' }, 400);
      case 'accept':
        break;
    }

    try {
      await dispatchRefresh({ repo: env.GITHUB_REPO, token: env.GITHUB_DISPATCH_TOKEN, sggCd });
    } catch (error) {
      // 깨우기에 실패했으면 잠금을 즉시 푼다. 안 그러면 아무 일도 안 일어난 채
      // 그 지역이 최소 간격 동안 막힌다.
      await region.finish();
      const status = error instanceof DispatchError ? 502 : 500;
      return json({ error: 'dispatch_failed' }, status);
    }

    // 예산은 실제로 깨운 뒤에 센다. 실패한 시도까지 세면 하루 예산이 헛되이 준다.
    await budget.consume();
    return json({ accepted: true, alreadyRunning: false, etaSeconds: ETA_SECONDS });
  },
} satisfies ExportedHandler<Env>;

/**
 * 본문에서 시군구 코드를 꺼낸다.
 *
 * 본문이 JSON이 아니거나 코드가 카탈로그에 없으면 `undefined`. 형식만 보고 통과시키면
 * 실재하지 않는 지역에 대해 Actions가 깨어나 원천 쿼터만 태운다 — 원천은 그런 요청에도
 * 오류가 아니라 0건으로 답하므로(R-14) 아무도 이상을 눈치채지 못한다.
 */
const readSggCd = async (request: Request): Promise<string | undefined> => {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return undefined;
  }
  if (typeof body !== 'object' || body === null) return undefined;
  const value = (body as Record<string, unknown>).sggCd;
  return isValidSggCd(value) ? value : undefined;
};

const json = (
  payload: unknown,
  status = 202,
  headers: Record<string, string> = {},
): Response =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
