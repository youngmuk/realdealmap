import { findRegion, toCurrentCode } from '@realdealmap/shared';
import type { DatasetKey } from '@realdealmap/shared';

import { PERIOD } from './chunk.js';
import { DATASETS, operationOf } from './datasets.js';
import { fieldDiff, parseResponse, type ParsedResponse, type RawItem } from './parse.js';
import type { Task } from './tasks.js';

/**
 * 국토교통부 실거래가 클라이언트.
 *
 * 이 클래스의 존재 이유 절반은 **R-14 대응**이다. 원천은 잘못된 요청을 오류로 알리지 않고
 * `200 · resultCode=000 · totalCount=0`으로 답한다(§3.1 T1.2). 따라서 응답을 보고
 * 실패를 판정할 수 없고, **요청을 보내기 전에 스스로 검증**해야 한다.
 */

const BASE = 'https://apis.data.go.kr/1613000';

/** §3.1 에러코드 표. 재시도해도 결과가 같은 오류에 백오프를 걸면 쿼터만 태운다. */
const RETRYABLE_RESULT_CODES = new Set(['01', '02', '04', '05']);
const QUOTA_EXCEEDED = '22';

/**
 * 전송 실패 백오프의 상한.
 *
 * 지수적으로만 늘리면 6회째에 64초가 되어 잡 제한(20분)을 위협한다.
 * 관측된 장애가 45초 규모였으므로 30초면 한 번은 그 너머로 넘어간다.
 */
const TRANSPORT_DELAY_CAP_MS = 30_000;

export class QuotaExceededError extends Error {
  constructor(readonly datasetKey: DatasetKey) {
    super(`${datasetKey}의 일일 트래픽을 소진했습니다`);
    this.name = 'QuotaExceededError';
  }
}

export class InvalidRequestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidRequestError';
  }
}

export class UpstreamError extends Error {
  /**
   * @param transport 원천에 **닿지도 못한** 실패인가.
   *   원천이 답을 준 오류(resultCode 01·02·04·05)와 회복 시간이 다르다 —
   *   답을 줬다는 것은 서버가 살아 있다는 뜻이라 수백 ms면 되지만,
   *   연결 자체가 안 붙는 상황은 수십 초 단위로 회복한다. 백오프를 나누는 근거다.
   */
  constructor(message: string, readonly retryable: boolean, readonly transport = false) {
    super(message);
    this.name = 'UpstreamError';
  }
}

/**
 * 오류의 `cause` 사슬을 한 줄로 편다.
 *
 * undici는 전송 실패를 전부 `TypeError: fetch failed`로 감싸고 **진짜 이유는
 * `cause`에 넣는다.** `message`만 담으면 로그에 `fetch failed` 한 줄만 남아
 * 연결 타임아웃인지 ECONNRESET인지 DNS 실패인지 구분할 수 없다.
 * 실제로 CI 실패를 조사할 때 이것 때문에 산술 추정에 의존해야 했다.
 *
 * 깊이를 제한하는 이유는 `cause`가 순환할 수 있기 때문이다.
 */
const CAUSE_DEPTH = 4;

const describeError = (error: unknown): string => {
  const parts: string[] = [];
  let current: unknown = error;
  for (let depth = 0; depth < CAUSE_DEPTH && current !== undefined && current !== null; depth += 1) {
    const message = current instanceof Error ? current.message : String(current);
    const code = (current as { code?: unknown }).code;
    parts.push(typeof code === 'string' ? `${message} (${code})` : message);
    current = current instanceof Error ? current.cause : undefined;
  }
  return parts.join(' ← ');
};

export interface ClientOptions {
  readonly serviceKey: string;
  readonly fetchImpl?: typeof fetch;
  /** 기술문서 30 tps · 평균 500ms 기준으로 6이면 약 12 tps다 */
  readonly concurrency?: number;
  /** 원천이 답을 준 재시도 가능 오류의 시도 횟수 */
  readonly maxRetries?: number;
  readonly baseDelayMs?: number;
  /** 전송 실패(연결 자체가 안 붙음)의 시도 횟수 */
  readonly transportRetries?: number;
  readonly transportDelayMs?: number;
  /** 지터용. 테스트에서 고정한다 */
  readonly random?: () => number;
  /** API(상세기능)별 일일 한도 */
  readonly dailyQuota?: number;
  readonly pageSize?: number;
  readonly sleep?: (ms: number) => Promise<void>;
  /** 한 요청의 제한 시간. 응답 본문을 다 읽을 때까지 포함한다 */
  readonly timeoutMs?: number;
  /** 응답 본문 상한. 넘으면 읽기를 중단한다 */
  readonly maxResponseBytes?: number;
}

/**
 * 응답 본문을 상한을 두고 읽는다.
 *
 * 상한이 없으면 오작동하는(혹은 탈취된) 원천이 끝없이 흘려보내는 본문에
 * CI 러너의 메모리가 소진된다. 제한 시간만으로는 부족하다 —
 * 빠른 회선에서는 제한 시간 안에도 수 GB가 들어올 수 있다.
 */
const readBounded = async (res: Response, maxBytes: number): Promise<string> => {
  const declared = Number(res.headers?.get?.('content-length') ?? Number.NaN);
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new UpstreamError(`응답이 상한을 넘음: ${declared} > ${maxBytes} bytes`, false);
  }

  const body = res.body;
  // 스트림이 없는 구현(테스트 더블 등)은 그대로 읽되 길이만 확인한다.
  if (!body?.getReader) {
    const text = await res.text();
    if (text.length > maxBytes) {
      throw new UpstreamError(`응답이 상한을 넘음: ${text.length} > ${maxBytes}`, false);
    }
    return text;
  }

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw new UpstreamError(`응답이 상한을 넘음: ${total} > ${maxBytes} bytes`, false);
    }
    chunks.push(value);
  }
  return new TextDecoder('utf-8').decode(Buffer.concat(chunks));
};

const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/**
 * 이미 퍼센트 인코딩이 끝난 문자열의 모양.
 * 비예약문자(RFC 3986 unreserved)와 올바른 `%XX`만으로 이루어져야 한다.
 */
const FULLY_ENCODED = /^(?:[A-Za-z0-9\-._~]|%[0-9A-Fa-f]{2})+$/;

/**
 * 서비스키를 요청에 넣을 형태로 만든다.
 *
 * 공공데이터포털은 **인코딩된 키와 디코딩된 키를 함께** 발급한다.
 * 기술문서는 "URL Encode된 값을 쓰라"고만 하는데, 인코딩된 키를 받아 다시 인코딩하면
 * `%2B` → `%252B`가 되어 에러코드 30이 난다. 어느 쪽을 넣어도 동작하게 한다.
 *
 * 판정은 "`%XX`가 하나라도 있으면 인코딩된 것"으로 하면 안 된다.
 * 원본 키에 우연히 `%XX` 모양이 섞여 있고 동시에 `&`나 `#`이 들어 있으면
 * 그대로 쿼리스트링에 붙어 **파라미터가 갈라지거나 `#` 이후가 잘린다.**
 * 전체가 인코딩된 모양일 때만 그대로 쓰고, 아니면 인코딩한다.
 */
export const encodeServiceKey = (key: string): string =>
  /%[0-9A-Fa-f]{2}/.test(key) && FULLY_ENCODED.test(key) ? key : encodeURIComponent(key);

export interface PageResult {
  readonly response: ParsedResponse;
  readonly attempts: number;
}

export interface FetchAllResult {
  readonly datasetKey: DatasetKey;
  /** 실제로 호출에 쓴 시군구 코드. 폐지 코드를 넣으면 현행 코드로 바뀐다 */
  readonly sggCd: string;
  readonly period: string;
  readonly items: readonly RawItem[];
  readonly totalCount: number;
  readonly pages: number;
  readonly calls: number;
  /** 스키마 변화가 감지된 페이지의 필드명 (R-14) */
  readonly drift: { readonly unknown: readonly string[]; readonly missing: readonly string[] };
}

export class MolitClient {
  readonly #serviceKey: string;
  readonly #fetch: typeof fetch;
  readonly #concurrency: number;
  readonly #maxRetries: number;
  readonly #baseDelayMs: number;
  readonly #transportRetries: number;
  readonly #transportDelayMs: number;
  readonly #random: () => number;
  readonly #dailyQuota: number;
  readonly #pageSize: number;
  readonly #sleep: (ms: number) => Promise<void>;
  readonly #timeoutMs: number;
  readonly #maxResponseBytes: number;
  readonly #used = new Map<DatasetKey, number>();

  constructor(options: ClientOptions) {
    if (options.serviceKey.trim() === '') {
      throw new InvalidRequestError('serviceKey가 비어 있습니다');
    }
    this.#serviceKey = options.serviceKey;
    this.#fetch = options.fetchImpl ?? globalThis.fetch;
    this.#concurrency = options.concurrency ?? 6;
    this.#maxRetries = options.maxRetries ?? 4;
    this.#baseDelayMs = options.baseDelayMs ?? 500;
    this.#transportRetries = options.transportRetries ?? 6;
    this.#transportDelayMs = options.transportDelayMs ?? 2_000;
    this.#random = options.random ?? Math.random;
    this.#dailyQuota = options.dailyQuota ?? 10_000;
    this.#pageSize = options.pageSize ?? 1000;
    this.#sleep = options.sleep ?? wait;
    this.#timeoutMs = options.timeoutMs ?? 30_000;
    this.#maxResponseBytes = options.maxResponseBytes ?? 32 * 1024 * 1024;
  }

  /** 유형별 소모량. 쿼터가 API별로 부여되므로 합산하지 않는다. */
  usage(key: DatasetKey): number {
    return this.#used.get(key) ?? 0;
  }

  remaining(key: DatasetKey): number {
    return Math.max(0, this.#dailyQuota - this.usage(key));
  }

  /**
   * 요청 전 검증 — R-14의 핵심.
   *
   * 폐지된 코드는 오류가 아니라 0건으로 오므로 여기서 현행 코드로 바꾼다.
   * 카탈로그에 없는 코드는 아예 호출하지 않는다. 호출해 봐야 0건과 구분되지 않는다.
   */
  resolveSggCd(sggCd: string): string {
    if (!/^\d{5}$/.test(sggCd)) {
      throw new InvalidRequestError(`시군구 코드가 5자리 숫자가 아님: ${sggCd}`);
    }
    const current = toCurrentCode(sggCd);
    const region = findRegion(current);
    if (!region) {
      throw new InvalidRequestError(`카탈로그에 없는 시군구 코드: ${sggCd}`);
    }
    if (!region.queryable) {
      throw new InvalidRequestError(
        `하위 일반구로 조회해야 하는 상위 시입니다: ${sggCd} (${region.name})`,
      );
    }
    return current;
  }

  #url(key: DatasetKey, sggCd: string, period: string, pageNo: number, rows: number): string {
    const spec = DATASETS[key];
    const params = new URLSearchParams({
      LAWD_CD: sggCd,
      DEAL_YMD: period,
      pageNo: String(pageNo),
      numOfRows: String(rows),
    });
    // serviceKey는 URLSearchParams에 넣지 않는다. 이미 인코딩된 키를 다시 인코딩하면
    // `%2B`가 `%252B`가 되어 에러코드 30(등록되지 않은 서비스키)이 난다.
    return `${BASE}/${spec.service}/${operationOf(spec)}?serviceKey=${encodeServiceKey(this.#serviceKey)}&${params.toString()}`;
  }

  /** 한 페이지를 가져온다. 재시도 가능한 실패는 지수 백오프로 다시 시도한다. */
  async fetchPage(
    key: DatasetKey,
    sggCd: string,
    period: string,
    pageNo = 1,
    rows = this.#pageSize,
  ): Promise<PageResult> {
    if (!PERIOD.test(period)) {
      throw new InvalidRequestError(`계약 연월이 YYYYMM(월 01~12)이 아님: ${period}`);
    }
    if (!Number.isInteger(pageNo) || pageNo < 1) {
      throw new InvalidRequestError(`pageNo가 1 이상의 정수가 아님: ${pageNo}`);
    }
    if (!Number.isInteger(rows) || rows < 1 || rows > 1000) {
      throw new InvalidRequestError(`numOfRows가 1~1000 범위가 아님: ${rows}`);
    }
    const resolved = this.resolveSggCd(sggCd);

    // 시도 한도는 **그 시도가 어떻게 실패했는지**에 따라 달라진다.
    // 그래서 `for`의 조건이 아니라 catch 안에서 판정한다.
    for (let attempt = 1; ; attempt += 1) {
      if (this.remaining(key) <= 0) throw new QuotaExceededError(key);
      this.#used.set(key, this.usage(key) + 1);

      try {
        const response = await this.#attempt(key, resolved, period, pageNo, rows);
        return { response, attempts: attempt };
      } catch (error) {
        if (error instanceof QuotaExceededError) throw error;
        if (!(error instanceof UpstreamError) || !error.retryable) throw error;
        if (attempt >= (error.transport ? this.#transportRetries : this.#maxRetries)) throw error;
        await this.#sleep(this.#backoff(attempt, error.transport));
      }
    }
  }

  /**
   * 다음 재시도까지 기다릴 시간.
   *
   * 전송 실패에만 **지터**를 넣는다. 여러 러너가 같은 순간 같은 원천에 막히면
   * 백오프가 결정적일 때 전원이 같은 오프셋에 다시 몰려 또 부딪힌다.
   * 절반 지터(0.5~1.0배)를 쓰는 이유는 하한을 남기기 위해서다 —
   * 연결 타임아웃 직후 100ms 만에 다시 붙어 봐야 결과가 같다.
   *
   * 원천이 답을 준 오류는 결정적으로 둔다. 서버가 살아 있어 금방 회복하고,
   * 예측 가능한 편이 테스트와 운영 양쪽에서 읽기 쉽다.
   */
  #backoff(attempt: number, transport: boolean): number {
    if (!transport) return this.#baseDelayMs * 2 ** (attempt - 1);
    const capped = Math.min(this.#transportDelayMs * 2 ** (attempt - 1), TRANSPORT_DELAY_CAP_MS);
    return Math.round(capped * (0.5 + this.#random() * 0.5));
  }

  /**
   * 요청 URL과 서비스키를 메시지에서 지운다.
   *
   * 오류 메시지는 로그·CI 요약·잡 주석으로 흘러 나간다. 어떤 오류가 URL을
   * 통째로 담아 올지 보장할 수 없으므로(예: URL 파싱 오류) **내보내기 직전에**
   * 한 번 더 지운다. §보안: 이 저장소는 public이다.
   */
  #scrub(text: string): string {
    return text
      .split(this.#serviceKey)
      .join('***')
      .split(encodeServiceKey(this.#serviceKey))
      .join('***')
      .replace(/serviceKey=[^&\s]*/gi, 'serviceKey=***');
  }

  async #attempt(
    key: DatasetKey,
    sggCd: string,
    period: string,
    pageNo: number,
    rows: number,
  ): Promise<ParsedResponse> {
    // 주의: 요청 URL에 serviceKey가 들어간다. 어떤 경로로도 URL 전체를 밖에 내지 않는다.
    let body: string;
    let status: number;
    try {
      const res = await this.#fetch(this.#url(key, sggCd, period, pageNo, rows), {
        // 제한 시간이 없으면 응답을 흘려보내지 않는 원천에 CI 잡이 무한정 매달린다.
        signal: AbortSignal.timeout(this.#timeoutMs),
      });
      status = res.status;
      body = await readBounded(res, this.#maxResponseBytes);
    } catch (error) {
      if (error instanceof UpstreamError) throw error;
      throw new UpstreamError(
        this.#scrub(`네트워크 실패 (${key} ${sggCd} ${period}): ${describeError(error)}`),
        true,
        true,
      );
    }

    const parsed = parseResponse(key, body);
    if (parsed.kind === 'fault') {
      if (parsed.code === QUOTA_EXCEEDED) throw new QuotaExceededError(key);
      throw new UpstreamError(`인증·권한 오류 ${parsed.code} ${parsed.errMsg}`, false);
    }
    if (parsed.resultCode === QUOTA_EXCEEDED) throw new QuotaExceededError(key);
    if (RETRYABLE_RESULT_CODES.has(parsed.resultCode)) {
      throw new UpstreamError(`원천 일시 오류 ${parsed.resultCode} ${parsed.resultMsg}`, true);
    }
    if (parsed.resultCode !== '00' && parsed.resultCode !== '000' && parsed.resultCode !== '03') {
      throw new UpstreamError(`처리 불가 ${parsed.resultCode} ${parsed.resultMsg}`, false);
    }
    if (status >= 500) throw new UpstreamError(`HTTP ${status}`, true);
    return parsed;
  }

  /**
   * 한 (유형 · 시군구 · 연월)의 전 페이지를 가져온다.
   *
   * 페이지 수는 응답에 의존하지 않고 `totalCount`로 직접 계산한다.
   * `pageNo`를 범위 밖으로 넣어도 원천이 오류를 주지 않기 때문이다(§3.1 T1.2).
   */
  async fetchAll(key: DatasetKey, sggCd: string, period: string): Promise<FetchAllResult> {
    const head = await this.fetchPage(key, sggCd, period, 1);
    const first = head.response;
    const pages = Math.max(1, Math.ceil(first.totalCount / this.#pageSize));

    const items: RawItem[] = [...first.items];
    let calls = 1;

    for (let pageNo = 2; pageNo <= pages; pageNo += 1) {
      const next = await this.fetchPage(key, sggCd, period, pageNo);
      calls += 1;
      items.push(...next.response.items);
    }

    // 드리프트는 페이지마다 따로 계산해 합치면 안 된다. 어떤 필드가 1페이지 항목에는
    // 없고 2페이지 항목에만 있으면, 페이지별 missing을 합집합했을 때 실제로는 존재하는
    // 필드가 "누락"으로 보고된다. 전 페이지를 모은 뒤 한 번에 계산한다.
    const drift = fieldDiff(key, items);

    return {
      datasetKey: key,
      sggCd: this.resolveSggCd(sggCd),
      period,
      items,
      totalCount: first.totalCount,
      pages,
      calls,
      drift: { unknown: drift.unknownFields, missing: drift.missingFields },
    };
  }

  /**
   * 작업목록을 동시성 제한 아래 실행한다.
   * 한 작업이 실패해도 나머지를 계속하되, 쿼터 소진은 그 유형의 남은 작업을 건너뛴다.
   */
  async runTasks(tasks: readonly Task[]): Promise<RunReport> {
    const results: FetchAllResult[] = [];
    const failures: TaskFailure[] = [];
    const exhausted = new Set<DatasetKey>();
    let cursor = 0;

    const worker = async (): Promise<void> => {
      for (;;) {
        const index = cursor;
        cursor += 1;
        const task = tasks[index];
        if (!task) return;

        if (exhausted.has(task.datasetKey)) {
          failures.push({ task, message: '쿼터 소진으로 건너뜀', quotaExceeded: true });
          continue;
        }
        try {
          results.push(await this.fetchAll(task.datasetKey, task.sggCd, task.period));
        } catch (error) {
          const quota = error instanceof QuotaExceededError;
          if (quota) exhausted.add(task.datasetKey);
          failures.push({
            task,
            message: error instanceof Error ? error.message : String(error),
            quotaExceeded: quota,
          });
        }
      }
    };

    const size = Math.min(this.#concurrency, Math.max(1, tasks.length));
    await Promise.all(Array.from({ length: size }, worker));
    return { results, failures };
  }
}

export interface TaskFailure {
  readonly task: Task;
  readonly message: string;
  readonly quotaExceeded: boolean;
}

export interface RunReport {
  readonly results: readonly FetchAllResult[];
  readonly failures: readonly TaskFailure[];
}
