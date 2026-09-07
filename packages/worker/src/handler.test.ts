import { describe, expect, test } from 'vitest';

import { dispatchRefresh, DispatchError } from './dispatch.js';
import { decide, type RegionState } from './policy.js';

/**
 * 핸들러 로직을 DO 런타임 없이 검증한다.
 *
 * `index.ts`의 `fetch`는 `cloudflare:workers`에 의존해 Node에서 import할 수 없다.
 * 진짜 런타임 검증은 `wrangler dev`로 하고, 여기서는 런타임과 무관한 부분 —
 * 판정 순서와 dispatch 호출 형태 — 을 잠근다.
 */

const idle: RegionState = { lastTriggeredAt: undefined, running: false };

describe('repository_dispatch 호출', () => {
  const capture = () => {
    const calls: { url: string; init: RequestInit }[] = [];
    const fetchImpl = (async (url: unknown, init: unknown) => {
      calls.push({ url: String(url), init: init as RequestInit });
      return new Response(null, { status: 204 });
    }) as unknown as typeof fetch;
    return { calls, fetchImpl };
  };

  test('계약대로 된 요청을 보낸다', async () => {
    const { calls, fetchImpl } = capture();
    await dispatchRefresh({ repo: 'owner/repo', token: 't', sggCd: '11680', fetchImpl });

    expect(calls).toHaveLength(1);
    expect(calls[0]?.url).toBe('https://api.github.com/repos/owner/repo/dispatches');
    const body = JSON.parse(String(calls[0]?.init.body)) as Record<string, unknown>;
    expect(body.event_type).toBe('refresh-region');
    expect(body.client_payload).toEqual({ sggCd: '11680', months: '3' });
  });

  // GitHub은 User-Agent가 없으면 403으로 답한다. 빠뜨리면 배포 후에야 드러난다.
  test('User-Agent를 반드시 보낸다', async () => {
    const { calls, fetchImpl } = capture();
    await dispatchRefresh({ repo: 'o/r', token: 't', sggCd: '11680', fetchImpl });
    const headers = calls[0]?.init.headers as Record<string, string>;
    expect(headers['user-agent']).toBeTruthy();
  });

  test('실패하면 상태코드를 담아 던진다', async () => {
    const fetchImpl = (async () =>
      new Response('{"message":"Bad credentials"}', { status: 401 })) as unknown as typeof fetch;

    await expect(
      dispatchRefresh({ repo: 'o/r', token: 'bad', sggCd: '11680', fetchImpl }),
    ).rejects.toThrow(DispatchError);
  });

  // 응답 본문을 그대로 올리면 나중에 누군가 그것을 로그로 내보낼 때
  // 무엇이 섞여 있을지 보장할 수 없다.
  test('오류에 토큰도 응답 본문도 넣지 않는다', async () => {
    const fetchImpl = (async () =>
      new Response('{"token":"ghp_secret"}', { status: 403 })) as unknown as typeof fetch;

    let message = '';
    try {
      await dispatchRefresh({ repo: 'o/r', token: 'ghp_secret', sggCd: '11680', fetchImpl });
      throw new Error('던지지 않았다');
    } catch (error) {
      message = error instanceof Error ? error.message : String(error);
    }

    expect(message).not.toContain('ghp_secret');
    expect(message).toContain('403');
  });
});

describe('판정과 응답의 대응', () => {
  // §5.2의 계약: 이미 돌고 있는 것은 오류가 아니라 202 + alreadyRunning 이다.
  test('running은 실패가 아니다', () => {
    expect(decide({ lastTriggeredAt: Date.now(), running: true }, Date.now(), 0).kind).toBe(
      'running',
    );
  });

  test('예산 소진만 429로 간다', () => {
    expect(decide(idle, Date.now(), 99999).kind).toBe('budget');
  });
});
