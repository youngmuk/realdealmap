import type { GeocodeOutcome, GeocodeProvider, ProviderOptions } from './geocode-provider.js';

/**
 * 카카오 로컬 API (T3.3).
 *
 * 키는 헤더로만 나가고 URL에는 들어가지 않는다.
 */

const ENDPOINT = 'https://dapi.kakao.com/v2/local/search/address.json';

/** 카카오 로컬 API의 앱당 일간 한도. */
export const KAKAO_DAILY_QUOTA = 100_000;

/**
 * 일간 한도를 다 쓴 응답인지 본다.
 *
 * 카카오는 이것을 **429가 아니라 400**으로 알린다:
 * `{"errorType":"BadRequest","message":"API limit has been exceeded.","code":-10}`
 *
 * 429만 보다가 하루치를 통째로 날렸다. 한도 소진이 일반 오류로 분류되면
 * 재시도 3회를 돌고 다음 지역으로 넘어가는데, 호출은 전부 실패하므로 남은
 * 지역이 모두 "성공했지만 0건"으로 조용히 지나간다. 무엇이 빠졌는지도 남지 않는다.
 *
 * 본문 대신 `code`를 본다. 400은 잘못된 질의로도 오기 때문에 상태 코드만으로
 * 판단하면 진짜 오류를 쿼터로 착각해 멀쩡한 실행을 멈춘다.
 */
const isDailyLimit = (statusCode: number, body: string): boolean => {
  if (statusCode !== 400) return false;
  try {
    const parsed = JSON.parse(body) as { code?: unknown };
    return parsed.code === -10;
  } catch {
    return false;
  }
};

export class KakaoProvider implements GeocodeProvider {
  readonly source = 'kakao' as const;
  readonly label = '카카오';
  readonly dailyQuota = KAKAO_DAILY_QUOTA;

  readonly #apiKey: string;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;

  constructor(options: ProviderOptions) {
    if (options.apiKey.trim() === '') throw new Error('카카오 REST 키가 비어 있습니다');
    this.#apiKey = options.apiKey;
    this.#fetch = options.fetchImpl ?? globalThis.fetch;
    this.#timeoutMs = options.timeoutMs ?? 10_000;
  }

  async ask(address: string): Promise<GeocodeOutcome> {
    let res: Response;
    try {
      res = await this.#fetch(`${ENDPOINT}?query=${encodeURIComponent(address)}`, {
        headers: { Authorization: `KakaoAK ${this.#apiKey}` },
        signal: AbortSignal.timeout(this.#timeoutMs),
      });
    } catch (error) {
      return { kind: 'error', detail: error instanceof Error ? error.message : String(error) };
    }

    if (res.status === 429) return { kind: 'quota', reason: 'HTTP 429' };
    if (!res.ok) {
      // 본문을 버리지 않는다. `http:400`만 남겼다가 실패 1,288건의 이유를 알 수 없었다.
      const detail = await res.text().catch(() => '');
      if (isDailyLimit(res.status, detail)) return { kind: 'quota', reason: '일간 한도(code -10)' };
      return { kind: 'error', detail: `HTTP ${res.status} ${detail.slice(0, 120)}` };
    }

    let body: { documents?: { x?: string; y?: string }[] };
    try {
      body = (await res.json()) as typeof body;
    } catch (error) {
      return { kind: 'error', detail: `본문 파싱 실패: ${String(error)}` };
    }

    const doc = body.documents?.[0];
    if (!doc?.x || !doc.y) return { kind: 'nomatch' };
    return { kind: 'found', lat: Number(doc.y), lng: Number(doc.x) };
  }
}
