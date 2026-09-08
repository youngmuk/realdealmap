import {
  geoQuery,
  type GeoEntry,
  type MissingAddress,
} from './geo.js';
import type { GeocodeOutcome, GeocodeProvider } from './geocode-provider.js';
import { KAKAO_DAILY_QUOTA, KakaoProvider } from './geocoder-kakao.js';
import { VWorldProvider } from './geocoder-vworld.js';

/**
 * 여러 지오코더를 순서대로 쓰는 변환기 (T3.3).
 *
 * 네 가지를 지킨다.
 *   1. **예산을 넘지 않는다** — 넘으면 그날 나머지 지역이 통째로 막힌다.
 *   2. **한 곳이 막히면 다음 곳으로 넘어간다** — 카카오 하나만 쓰던 동안
 *      하루치를 태운 이튿날을 통째로 놀렸다.
 *   3. **일시적 실패는 재시도한다** — 재시도가 없던 첫 판에서 26%가 실패했는데,
 *      본문을 버려서 이유조차 알 수 없었다. 재시도만 붙이니 0%가 됐다.
 *   4. **영구 실패를 기록한다** — 안 그러면 원천이 모르는 주소를 매번 다시 묻는다.
 *
 * 곳마다의 규약과 구현은 [geocode-provider.ts]와 `geocoder-*.ts`에 있다.
 * 여기에는 어느 API도 등장하지 않는다 — 예산·동시성·이월만 다룬다.
 */

export type { GeocodeOutcome, GeocodeProvider } from './geocode-provider.js';
export { KAKAO_DAILY_QUOTA, KakaoProvider } from './geocoder-kakao.js';
export { VWORLD_DAILY_QUOTA, VWorldProvider } from './geocoder-vworld.js';

export interface GeocoderOptions {
  /** 카카오 REST 키. `providers`를 직접 넘기면 필요 없다 */
  readonly apiKey?: string;
  /** VWorld 인증키. 있으면 카카오가 막힌 뒤 이어받는다 */
  readonly vworldKey?: string;
  /** 쓸 곳을 직접 정한다. 시험과 특수한 운용에만 쓴다 */
  readonly providers?: readonly GeocodeProvider[];
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
  /**
   * 한 곳이 이만큼 내리 실패하면 그 곳을 접는다.
   *
   * 접지 않으면 병든 곳 하나가 예산을 통째로 오류로 태운다 — 실제로 VWorld가
   * 게이트웨이에 막힌 실행에서 **1,389회를 버렸다.** 그 사이 멀쩡한 다른 곳은
   * 한 번도 불리지 않았다.
   */
  readonly errorStreakLimit?: number;
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
  /** 곳마다 몇 번 불렀는지. 어느 쿼터를 얼마나 썼는지 보려면 이것뿐이다 */
  readonly callsBySource: Readonly<Record<string, number>>;
  /** **모든** 곳이 막혀 멈췄는가 */
  readonly quotaExhausted: boolean;
  /** 막힌 곳과 그 사유. `["카카오: 일간 한도(code -10)"]` */
  readonly exhausted: readonly string[];
  readonly errors: readonly string[];
}

/**
 * 옵션에서 쓸 곳들을 만든다.
 *
 * **순서가 곧 우선순위다.** 한도가 큰 카카오(10만)를 먼저 태우고 VWorld(4만)로
 * 넘어간다. 순서를 바꿔도 하루 총량은 같지만, 큰 쪽을 먼저 쓰면 작은 쪽이
 * 남아 있어 "조금 모자란 날"을 메울 여지가 생긴다.
 */
const buildProviders = (options: GeocoderOptions): readonly GeocodeProvider[] => {
  if (options.providers) return options.providers;

  // 정해지지 않은 값은 **키 자체를 만들지 않는다.** `exactOptionalPropertyTypes`
  // 아래에서 `undefined`를 넘기는 것과 안 넘기는 것은 다른 일이다.
  const shared = {
    ...(options.fetchImpl === undefined ? {} : { fetchImpl: options.fetchImpl }),
    ...(options.timeoutMs === undefined ? {} : { timeoutMs: options.timeoutMs }),
  };
  const providers: GeocodeProvider[] = [];
  if (options.apiKey !== undefined) {
    providers.push(new KakaoProvider({ ...shared, apiKey: options.apiKey }));
  }
  if (options.vworldKey !== undefined && options.vworldKey.trim() !== '') {
    providers.push(new VWorldProvider({ ...shared, apiKey: options.vworldKey }));
  }
  if (providers.length === 0) throw new Error('쓸 수 있는 지오코더가 하나도 없습니다');
  return providers;
};

export class Geocoder {
  readonly #providers: readonly GeocodeProvider[];
  readonly #regionName: string;
  readonly #concurrency: number;
  readonly #maxAttempts: number;
  readonly #baseDelayMs: number;
  readonly #sleep: (ms: number) => Promise<void>;
  readonly #budget: number;
  readonly #today: string;
  readonly #errorStreakLimit: number;

  constructor(options: GeocoderOptions) {
    this.#providers = buildProviders(options);
    this.#regionName = options.regionName;
    this.#concurrency = options.concurrency ?? 8;
    this.#maxAttempts = options.maxAttempts ?? 3;
    this.#baseDelayMs = options.baseDelayMs ?? 300;
    this.#sleep = options.sleep ?? wait;
    this.#budget = options.budget ?? KAKAO_DAILY_QUOTA;
    this.#today = options.today ?? new Date().toISOString().slice(0, 10);
    this.#errorStreakLimit = options.errorStreakLimit ?? 20;
  }

  /** 쓸 수 있는 곳의 이름. 계획을 찍을 때 쓴다 */
  get sources(): readonly string[] {
    return this.#providers.map((p) => p.label);
  }

  /**
   * 일시적 실패만 다시 시도한다.
   *
   * `nomatch`와 `quota`는 다시 물어도 같은 답이다. 재시도하면 쿼터만 태운다.
   */
  async #askWithRetry(provider: GeocodeProvider, address: string): Promise<GeocodeOutcome> {
    let last: GeocodeOutcome = { kind: 'error', detail: '시도하지 않음' };
    for (let attempt = 1; attempt <= this.#maxAttempts; attempt += 1) {
      last = await provider.ask(address);
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
    const callsBySource: Record<string, number> = {};
    /** 막힌 곳 → 사유. 여기 실린 곳은 이번 실행에서 다시 부르지 않는다 */
    const exhausted = new Map<string, string>();
    /** 곳마다 마지막 성공 이후 내리 실패한 횟수 */
    const streak = new Map<string, number>();
    let found = 0;
    let nomatch = 0;
    let calls = 0;
    let cursor = 0;

    const usable = (): GeocodeProvider | null =>
      this.#providers.find((p) => !exhausted.has(p.label)) ?? null;

    const worker = async (): Promise<void> => {
      for (;;) {
        // 매 건마다 다시 고른다. 다른 일꾼이 방금 이 곳을 소진시켰을 수 있다.
        const provider = usable();
        if (provider === null) return;

        const index = cursor;
        // 예산을 **꺼내기 전에** 본다. 꺼낸 뒤에 보면 한도를 한 번 넘긴 뒤에 멈춘다.
        if (index >= missing.length || calls >= this.#budget) return;
        cursor += 1;
        const item = missing[index];
        if (!item) return;

        const query = geoQuery(this.#regionName, item.umdNm, item.jibun);

        // 막힌 곳에 걸린 항목은 **붙잡은 채** 다음 곳으로 넘긴다.
        //
        // 예전에는 여기서 곧바로 이월했다. 동시 실행 중에 같은 항목을 두 번 세는
        // 경로를 만들지 않으려던 것인데, 항목을 이 일꾼이 계속 쥐고 있으면 그런
        // 경로는 애초에 생기지 않는다. 이월의 대가는 작지 않다 — 한 지역에서
        // 동시성 개수만큼(기본 8건) 밀리고, 그 8건 때문에 다음 실행이 그 지역
        // 청크를 통째로 다시 받는다(지역당 약 12초 실측).
        //
        // 되묻기는 곳이 막혔을 때만이다. 미매칭은 되묻지 않는다 — 실측 0.1% 미만이라
        // 얻을 것이 거의 없는데, 되물으면 **가장 어려운 주소들에만** 두 곳의 쿼터를
        // 나란히 태우게 된다.
        for (let p: GeocodeProvider | null = provider; p !== null; p = usable()) {
          // 되묻는 만큼 예산을 넘길 수 있다. 곳이 둘이므로 항목당 최대 한 번,
          // 그것도 막힌 순간에만이다. 한도를 한 건 넘기는 것보다 이월이 비싸다.
          calls += 1;
          callsBySource[p.label] = (callsBySource[p.label] ?? 0) + 1;
          const outcome = await this.#askWithRetry(p, query);

          if (outcome.kind === 'quota') {
            exhausted.set(p.label, outcome.reason);
            continue;
          }

          if (outcome.kind === 'found') {
            found += 1;
            streak.set(p.label, 0);
            entries[item.key] = {
              lat: Number(outcome.lat.toFixed(6)),
              lng: Number(outcome.lng.toFixed(6)),
              source: p.source,
              checkedOn: this.#today,
            };
          } else if (outcome.kind === 'nomatch') {
            nomatch += 1;
            // 미매칭도 "그 곳이 살아 있다"는 답이다. 연속 실패를 끊는다.
            streak.set(p.label, 0);
            // 좌표가 없다는 사실 자체를 기록한다. 안 그러면 매번 다시 묻는다.
            entries[item.key] = { lat: 0, lng: 0, source: 'nomatch', checkedOn: this.#today };
          } else {
            errors.push(`${item.key}: ${outcome.detail}`);
            // 병든 곳 하나가 예산을 통째로 오류로 태우게 두지 않는다. 실제로
            // VWorld가 게이트웨이에 막힌 실행에서 1,389회를 버렸고, 그 사이
            // 멀쩡한 다른 곳은 한 번도 불리지 않았다.
            const n = (streak.get(p.label) ?? 0) + 1;
            streak.set(p.label, n);
            if (n >= this.#errorStreakLimit) {
              exhausted.set(p.label, `연속 오류 ${n}회 — ${outcome.detail}`);
            }
          }
          break;
        }
      }
    };

    const size = Math.min(this.#concurrency, Math.max(1, missing.length));
    await Promise.all(Array.from({ length: size }, worker));

    // 처리하지 못한 것을 정확히 집는다. `cursor`는 동시 실행 때문에 실제 처리분보다
    // 앞서 있을 수 있으므로, 결과가 없는 항목을 기준으로 삼는다.
    const deferred = missing.filter((m) => entries[m.key] === undefined);

    return {
      entries,
      found,
      nomatch,
      deferred,
      calls,
      callsBySource,
      quotaExhausted: exhausted.size === this.#providers.length,
      exhausted: [...exhausted].map(([label, reason]) => `${label}: ${reason}`),
      errors,
    };
  }
}
