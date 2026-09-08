import type { GeocodeOutcome, GeocodeProvider, ProviderOptions } from './geocode-provider.js';

/**
 * 국토교통부 공간정보 오픈플랫폼(VWorld) 지오코더 2.0.
 *
 * 카카오가 막힌 날을 메우려고 둔다. 새 계정도 새 비용도 없다 — 배경 지도 타일에
 * 이미 쓰고 있는 키가 그대로 통한다(서버에서 도메인 제한 없이 도는 것을 실측했다).
 *
 * `type=PARCEL`은 지번주소를 받는다. 지번이 없어 법정동까지만 있는 질의
 * (전체 거래의 약 29%가 이 형태다 — 단독다가구 전월세는 원천이 지번을 주지 않는다)
 * 도 받아서 법정동 중심점을 돌려준다. 실측으로 확인했다.
 *
 * **주의: 인증키가 쿼리스트링에 들어간다.** 어떤 경로로도 요청 URL 전체를 밖에
 * 내지 않는다. 오류 본문도 그대로 찍지 않고 코드만 옮긴다.
 */

const ENDPOINT = 'https://api.vworld.kr/req/address';

/** VWorld 지오코더의 일간 무료 한도. */
export const VWORLD_DAILY_QUOTA = 40_000;

/**
 * 요청 사이 최소 간격 — **속도를 스스로 묶는다.**
 *
 * VWorld는 카카오보다 훨씬 빨리 답한다(30ms 안팎). 그래서 같은 동시성 8로 밀면
 * 초당 250건이 나가고, 그러면 얼마 못 가 게이트웨이가 막아 버린다. 실측:
 *   · 동시 8로 300건 — 전부 성공
 *   · 동시 8로 2,246건 — 857건 성공한 뒤 **1,389건이 HTTP 502**
 *   · 그 뒤로는 초당 4건으로 낮춰도, 1분을 쉬어도 계속 502
 * 한 번 막히면 한동안 풀리지 않는다. 그래서 막힌 뒤에 늦추는 것으로는 부족하고
 * **처음부터** 밟지 말아야 한다.
 *
 * 초당 5건이면 하루 한도 4만을 채우는 데 2시간 남짓이다. 잡 제한(300분)에
 * 넉넉히 들어가고, 어차피 하루 한 번 채우면 되는 일이라 빠를 이유가 없다.
 */
export const VWORLD_MIN_INTERVAL_MS = 200;

const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/**
 * "다시 물어도 소용없다"는 응답들.
 *
 * 한도 초과와 인증키 문제를 한 묶음으로 다룬다. 둘 다 이번 실행에서 이 곳을
 * 더 쓸 수 없다는 뜻이라 동작은 같지만, 사유는 그대로 남겨 보고한다 —
 * 키를 잘못 넣어 두고 "쿼터 소진"으로 읽는 일이 없어야 한다.
 */
const UNUSABLE: Readonly<Record<string, string>> = {
  OVER_REQUEST_LIMIT: '일간 한도 초과',
  INVALID_KEY: '등록되지 않은 인증키',
  INCORRECT_KEY: '인증키 정보 불일치(도메인 등)',
  UNAVAILABLE_KEY: '인증키를 임시로 쓸 수 없음',
};

export interface VWorldOptions extends ProviderOptions {
  /** 요청 사이 최소 간격(ms). 0이면 묶지 않는다 — 시험에서만 쓴다 */
  readonly minIntervalMs?: number;
  readonly sleep?: (ms: number) => Promise<void>;
}

interface VWorldBody {
  readonly response?: {
    readonly status?: string;
    readonly result?: { readonly point?: { readonly x?: string; readonly y?: string } };
    readonly error?: { readonly code?: string; readonly text?: string };
  };
}

export class VWorldProvider implements GeocodeProvider {
  readonly source = 'vworld' as const;
  readonly label = 'VWorld';
  readonly dailyQuota = VWORLD_DAILY_QUOTA;

  readonly #apiKey: string;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;
  readonly #minIntervalMs: number;
  readonly #sleep: (ms: number) => Promise<void>;
  /** 다음 요청을 보내도 되는 가장 이른 시각 */
  #nextSlot = 0;

  constructor(options: VWorldOptions) {
    if (options.apiKey.trim() === '') throw new Error('VWorld 인증키가 비어 있습니다');
    this.#apiKey = options.apiKey;
    this.#fetch = options.fetchImpl ?? globalThis.fetch;
    this.#timeoutMs = options.timeoutMs ?? 10_000;
    this.#minIntervalMs = options.minIntervalMs ?? VWORLD_MIN_INTERVAL_MS;
    this.#sleep = options.sleep ?? sleep;
  }

  /**
   * 자기 차례를 받아 그때까지 기다린다.
   *
   * 일꾼이 몇이든 이 간격 아래로는 못 나간다. 자리를 **먼저 잡고** 기다리므로
   * 여럿이 동시에 들어와도 같은 자리를 두 번 쓰지 않는다.
   */
  async #pace(): Promise<void> {
    if (this.#minIntervalMs <= 0) return;
    const now = Date.now();
    const slot = Math.max(now, this.#nextSlot);
    this.#nextSlot = slot + this.#minIntervalMs;
    if (slot > now) await this.#sleep(slot - now);
  }

  #url(address: string): string {
    const url = new URL(ENDPOINT);
    for (const [key, value] of Object.entries({
      service: 'address',
      request: 'getcoord',
      version: '2.0',
      crs: 'EPSG:4326',
      type: 'PARCEL',
      address,
      format: 'json',
      key: this.#apiKey,
    })) {
      url.searchParams.set(key, value);
    }
    return url.toString();
  }

  async ask(address: string): Promise<GeocodeOutcome> {
    await this.#pace();

    let res: Response;
    try {
      res = await this.#fetch(this.#url(address), {
        signal: AbortSignal.timeout(this.#timeoutMs),
      });
    } catch (error) {
      return { kind: 'error', detail: error instanceof Error ? error.message : String(error) };
    }

    // 본문을 오류 메시지에 싣지 않는다. 요청을 되비추는 응답이 오면 키가 딸려 나온다.
    if (!res.ok) return { kind: 'error', detail: `HTTP ${res.status}` };

    let body: VWorldBody;
    try {
      body = (await res.json()) as VWorldBody;
    } catch (error) {
      return { kind: 'error', detail: `본문 파싱 실패: ${String(error)}` };
    }

    // VWorld는 오류도 HTTP 200으로 돌려준다. 상태 코드만 보면 전부 성공으로 읽힌다.
    const status = body.response?.status;
    if (status === 'NOT_FOUND') return { kind: 'nomatch' };
    if (status !== 'OK') {
      const code = body.response?.error?.code ?? '(코드 없음)';
      const known = UNUSABLE[code];
      if (known !== undefined) return { kind: 'quota', reason: `${code} — ${known}` };
      return { kind: 'error', detail: `status=${status ?? '(없음)'} code=${code}` };
    }

    const point = body.response?.result?.point;
    if (!point?.x || !point.y) return { kind: 'nomatch' };
    const lat = Number(point.y);
    const lng = Number(point.x);
    // 숫자가 아닌 좌표를 사전에 넣으면 그 지역의 마커가 통째로 사라진다.
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return { kind: 'error', detail: '좌표를 숫자로 읽지 못했다' };
    }
    return { kind: 'found', lat, lng };
  }
}
