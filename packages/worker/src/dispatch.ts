/**
 * GitHub `repository_dispatch` 호출.
 *
 * Worker는 무거운 일을 하지 않는다. 수집·파싱·업로드는 전부 Actions가 하고,
 * Worker는 깨우기만 한다(§AD-5). 이 파일이 그 경계다.
 */

export class DispatchError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = 'DispatchError';
  }
}

export interface DispatchOptions {
  readonly repo: string;
  readonly token: string;
  readonly sggCd: string;
  readonly months?: number;
  readonly fetchImpl?: typeof fetch;
}

/**
 * 한 지역의 갱신을 요청한다.
 *
 * 주의: 토큰이 헤더에 들어간다. 실패해도 **응답 본문을 그대로 흘리지 않는다** —
 * GitHub의 오류 응답은 토큰을 되비추지 않지만, 여기서 본문을 통째로 상위로 올리면
 * 나중에 누군가 그것을 로그로 내보낼 때 무엇이 섞여 있을지 보장할 수 없다.
 * 상태 코드와 짧은 문구만 남긴다.
 */
export const dispatchRefresh = async (options: DispatchOptions): Promise<void> => {
  const { repo, token, sggCd, months = 3, fetchImpl = fetch } = options;

  const res = await fetchImpl(`https://api.github.com/repos/${repo}/dispatches`, {
    method: 'POST',
    headers: {
      accept: 'application/vnd.github+json',
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      // GitHub API는 User-Agent가 없으면 403으로 답한다.
      'user-agent': 'realdealmap-worker',
      'x-github-api-version': '2022-11-28',
    },
    body: JSON.stringify({
      event_type: 'refresh-region',
      client_payload: { sggCd, months: String(months) },
    }),
    signal: AbortSignal.timeout(8_000),
  });

  // 204가 정상이다. 200을 주는 경우는 없지만 2xx는 받아들인다.
  if (res.ok) return;
  throw new DispatchError(`갱신 요청이 거절되었습니다 (${res.status})`, res.status);
};
