import {
  geoQuery,
  type GeoEntry,
  type MissingAddress,
} from './geo.js';

/**
 * 카카오 로컬 API 지오코더 (T3.3).
 *
 * 세 가지를 지킨다.
 *   1. **일일 쿼터를 넘지 않는다** — 넘으면 그날 나머지 지역이 통째로 막힌다.
 *   2. **일시적 실패는 재시도한다** — 재시도가 없던 첫 판에서 26%가 실패했는데,
 *      본문을 버려서 이유조차 알 수 없었다. 재시도만 붙이니 0%가 됐다.
 *   3. **영구 실패를 기록한다** — 안 그러면 원천이 모르는 주소를 매번 다시 묻는다.
 *
 * 키는 헤더로만 나가고 URL에는 들어가지 않는다.
 */

const ENDPOINT = 'https://dapi.kakao.com/v2/local/search/address.json';

/** 카카오 로컬 API의 앱당 일간 한도. */
export const KAKAO_DAILY_QUOTA = 100_000;

export type GeocodeOutcome =
  | { readonly kind: 'found'; readonly lat: number; readonly lng: number }
  | { readonly kind: 'nomatch' }
  /** 원천 잘못이 아니라 우리 쪽 한도. 남은 작업은 다음 날로 넘긴다 */
  | { readonly kind: 'quota' }
  | { readonly kind: 'error'; readonly detail: string };

export interface GeocoderOptions {
  readonly apiKey: string;
  readonly regionName: string;
  readonly fetchImpl?: typeof fetch;
  readonly concurrency?: number;
  readonly maxAttempts?: number;
  readonly baseDelayMs?: number;
  readonly timeoutMs?: number;
  readonly sleep?: (ms: number) => Promise<void>;
  /** 이번 실행에서 쓸 수 있는 호출 수의 상한 */
  readonly budget?: number;
  readonly today?: string;
}

const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

export interface GeocodeResult {
  /** 사전에 얹을 항목. 성공과 영구 실패를 모두 담는다 */
  readonly entries: Readonly<Record<string, GeoEntry>>;
  readonly found: number;
  readonly nomatch: number;
  /** 이번에 처리하지 못하고 남은 주소. 다음 실행으로 이월된다 */
  readonly deferred: readonly MissingAddress[];
  readonly calls: number;
  /** 쿼터에 막혀 멈췄는가 */
  readonly quotaExhausted: boolean;
  readonly errors: readonly string[];
}

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

export class Geocoder {
  readonly #apiKey: string;
  readonly #regionName: string;
  readonly #fetch: typeof fetch;
  readonly #concurrency: number;
  readonly #maxAttempts: number;
  readonly #baseDelayMs: number;
  readonly #timeoutMs: number;
  readonly #sleep: (ms: number) => Promise<void>;
  readonly #budget: number;
  readonly #today: string;

  constructor(options: GeocoderOptions) {
    if (options.apiKey.trim() === '') throw new Error('카카오 REST 키가 비어 있습니다');
    this.#apiKey = options.apiKey;
    this.#regionName = options.regionName;
    this.#fetch = options.fetchImpl ?? globalThis.fetch;
    this.#concurrency = options.concurrency ?? 8;
    this.#maxAttempts = options.maxAttempts ?? 3;
    this.#baseDelayMs = options.baseDelayMs ?? 300;
    this.#timeoutMs = options.timeoutMs ?? 10_000;
    this.#sleep = options.sleep ?? wait;
    this.#budget = options.budget ?? KAKAO_DAILY_QUOTA;
    this.#today = options.today ?? new Date().toISOString().slice(0, 10);
  }

  /** 한 주소를 한 번 물어본다. */
  async #ask(address: string): Promise<GeocodeOutcome> {
    let res: Response;
    try {
      res = await this.#fetch(`${ENDPOINT}?query=${encodeURIComponent(address)}`, {
        headers: { Authorization: `KakaoAK ${this.#apiKey}` },
        signal: AbortSignal.timeout(this.#timeoutMs),
      });
    } catch (error) {
      return { kind: 'error', detail: error instanceof Error ? error.message : String(error) };
    }

    if (res.status === 429) return { kind: 'quota' };
    if (!res.ok) {
      // 본문을 버리지 않는다. `http:400`만 남겼다가 실패 1,288건의 이유를 알 수 없었다.
      const detail = await res.text().catch(() => '');
      if (isDailyLimit(res.status, detail)) return { kind: 'quota' };
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

  /**
   * 일시적 실패만 다시 시도한다.
   *
   * `nomatch`와 `quota`는 다시 물어도 같은 답이다. 재시도하면 쿼터만 태운다.
   */
  async #askWithRetry(address: string): Promise<GeocodeOutcome> {
    let last: GeocodeOutcome = { kind: 'error', detail: '시도하지 않음' };
    for (let attempt = 1; attempt <= this.#maxAttempts; attempt += 1) {
      last = await this.#ask(address);
      if (last.kind !== 'error') return last;
      if (attempt < this.#maxAttempts) {
        await this.#sleep(this.#baseDelayMs * 2 ** (attempt - 1));
      }
    }
    return last;
  }

  /**
   * 주소 목록을 예산 안에서 처리한다.
   *
   * 예산이 모자라면 **앞에서부터** 처리하고 나머지를 `deferred`로 돌려준다.
   * 호출자가 정렬해서 넘기므로(거래 수 많은 순) 잘려도 커버리지가 가장 많이 오른다.
   */
  async run(missing: readonly MissingAddress[]): Promise<GeocodeResult> {
    const entries: Record<string, GeoEntry> = {};
    const errors: string[] = [];
    let found = 0;
    let nomatch = 0;
    let calls = 0;
    let quotaExhausted = false;
    let cursor = 0;

    const worker = async (): Promise<void> => {
      for (;;) {
        if (quotaExhausted) return;
        const index = cursor;
        // 예산을 **꺼내기 전에** 본다. 꺼낸 뒤에 보면 한도를 한 번 넘긴 뒤에 멈춘다.
        if (index >= missing.length || calls >= this.#budget) return;
        cursor += 1;
        const item = missing[index];
        if (!item) return;

        calls += 1;
        const outcome = await this.#askWithRetry(
          geoQuery(this.#regionName, item.umdNm, item.jibun),
        );

        switch (outcome.kind) {
          case 'found':
            found += 1;
            entries[item.key] = {
              lat: Number(outcome.lat.toFixed(6)),
              lng: Number(outcome.lng.toFixed(6)),
              source: 'kakao',
              checkedOn: this.#today,
            };
            break;
          case 'nomatch':
            nomatch += 1;
            // 좌표가 없다는 사실 자체를 기록한다. 안 그러면 매번 다시 묻는다.
            entries[item.key] = { lat: 0, lng: 0, source: 'nomatch', checkedOn: this.#today };
            break;
          case 'quota':
            quotaExhausted = true;
            return;
          case 'error':
            errors.push(`${item.key}: ${outcome.detail}`);
            break;
        }
      }
    };

    const size = Math.min(this.#concurrency, Math.max(1, missing.length));
    await Promise.all(Array.from({ length: size }, worker));

    // 처리하지 못한 것을 정확히 집는다. `cursor`는 동시 실행 때문에 실제 처리분보다
    // 앞서 있을 수 있으므로, 결과가 없는 항목을 기준으로 삼는다.
    const deferred = missing.filter((m) => entries[m.key] === undefined);

    return { entries, found, nomatch, deferred, calls, quotaExhausted, errors };
  }
}
