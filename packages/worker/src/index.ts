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

    // 기본 상태코드가 202인 이유는 트리거 응답이 전부 "접수됨"이기 때문이다.
    // 헬스체크는 그 의미가 아니므로 200을 명시한다.
    if (url.pathname === '/health') return json({ ok: true }, 200);
    if (url.pathname === '/v1/refresh/done') return done(request, env);

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
        // 시간 예산이 찼을 때가 대부분이다 — 한 시간 뒤에는 다시 열린다.
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
      await region.finish('dispatch_failed');
      const status = error instanceof DispatchError ? 502 : 500;
      return json({ error: 'dispatch_failed' }, status);
    }

    // 예산은 실제로 깨운 뒤에 센다. 실패한 시도까지 세면 하루 예산이 헛되이 준다.
    await budget.consume();
    return json({ accepted: true, alreadyRunning: false, etaSeconds: ETA_SECONDS });
  },
} satisfies ExportedHandler<Env>;

/**
 * 갱신 완료 콜백. Actions가 끝나면서 부른다.
 *
 * **상태를 바꾸는 엔드포인트라 인증이 필요하다.** 인증이 없으면 아무나 `running`을
 * 내릴 수 있고, 그 자체로 큰 피해는 없지만(최소 간격 게이트가 따로 있다)
 * 상태를 남이 조작할 수 있게 두는 것은 그 자체로 결함이다.
 *
 * 비밀이 설정돼 있지 않으면 **경로를 아예 닫는다.** 인증 없는 상태 변경 엔드포인트를
 * 열어 두느니 기능을 끄는 편이 낫다 — 콜백이 없어도 잠금은 시간으로 만료된다.
 */
const done = async (request: Request, env: Env): Promise<Response> => {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, { allow: 'POST' });
  if (!env.CALLBACK_SECRET) return json({ error: 'not_found' }, 404);

  const presented = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!timingSafeEqual(presented, env.CALLBACK_SECRET)) {
    return json({ error: 'unauthorized' }, 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  const record = (body ?? {}) as Record<string, unknown>;
  if (!isValidSggCd(record.sggCd)) return json({ error: 'invalid_sgg' }, 400);

  const outcome = typeof record.outcome === 'string' ? record.outcome.slice(0, 32) : 'unknown';
  await env.REGION_TRIGGER.get(env.REGION_TRIGGER.idFromName(record.sggCd)).finish(outcome);
  return json({ ok: true }, 200);
};

/**
 * 길이와 내용을 상수 시간에 비교한다.
 *
 * `===`로 비교하면 앞에서부터 다른 지점에 따라 반환 시간이 달라져, 원격에서도
 * 한 글자씩 맞춰 갈 여지가 생긴다. 실제로 짜내기 어렵더라도 비밀 비교는
 * 상수 시간으로 두는 것이 기본이다.
 */
const timingSafeEqual = (a: string, b: string): boolean => {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
};

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
