import { createHash, createHmac } from 'node:crypto';

/**
 * R2(S3 호환) 최소 클라이언트.
 *
 * AWS SDK를 넣지 않고 SigV4를 직접 서명한다. 이 저장소는 public이고 GitHub Actions에서 도는데,
 * 우리가 쓰는 연산은 PUT · GET · HEAD · DELETE · list 다섯 개뿐이다.
 * 그 다섯 개를 위해 수십 MB의 의존성 트리를 끌어들이면 공급망 표면만 넓어진다.
 *
 * R2는 리전이 하나뿐이라 서명 리전은 항상 `auto`다.
 */

const SERVICE = 's3';
const REGION = 'auto';

const sha256Hex = (data: string | Uint8Array): string =>
  createHash('sha256').update(data).digest('hex');

const hmac = (key: Uint8Array | string, data: string): Buffer =>
  createHmac('sha256', key).update(data).digest();

/**
 * URI 경로 인코딩. S3 서명은 `encodeURIComponent`보다 넓게 인코딩하고
 * 비예약문자만 남긴다. 슬래시는 경로 구분자이므로 보존한다.
 */
const encodePath = (path: string): string =>
  path
    .split('/')
    .map((segment) =>
      encodeURIComponent(segment).replace(
        /[!'()*]/g,
        (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
      ),
    )
    .join('/');

export interface R2Config {
  readonly accountId: string;
  readonly accessKeyId: string;
  readonly secretAccessKey: string;
  readonly bucket: string;
  readonly fetchImpl?: typeof fetch;
  readonly timeoutMs?: number;
}

export class R2Error extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
  ) {
    super(message);
    this.name = 'R2Error';
  }
}

export class R2ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'R2ConfigError';
  }
}

interface SignedRequest {
  readonly url: string;
  readonly headers: Record<string, string>;
}

/** `20260907T071530Z` 형태의 ISO8601 basic. */
export const amzDate = (at: Date): string =>
  `${at.toISOString().replace(/[-:]/g, '').slice(0, 15)}Z`;

/**
 * SigV4 서명을 계산해 요청 헤더를 만든다.
 *
 * 페이로드 해시를 실제로 계산해 넣는다(`UNSIGNED-PAYLOAD` 대신).
 * 전송 중 본문이 바뀌면 서명이 깨져 서버가 거부하므로, 무결성 검사가 공짜로 딸려 온다.
 */
export const signRequest = (
  config: R2Config,
  method: string,
  path: string,
  query: string,
  body: Uint8Array | undefined,
  at: Date,
  extraHeaders: Readonly<Record<string, string>> = {},
): SignedRequest => {
  const host = `${config.accountId}.r2.cloudflarestorage.com`;
  const stamp = amzDate(at);
  const day = stamp.slice(0, 8);
  const payloadHash = body === undefined ? sha256Hex('') : sha256Hex(body);

  const headers: Record<string, string> = {
    host,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': stamp,
    ...Object.fromEntries(Object.entries(extraHeaders).map(([k, v]) => [k.toLowerCase(), v])),
  };

  const signedNames = Object.keys(headers).sort();
  const canonicalHeaders = signedNames.map((n) => `${n}:${headers[n]?.trim()}\n`).join('');
  const signedHeaders = signedNames.join(';');

  const canonicalRequest = [
    method,
    encodePath(path),
    query,
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const scope = `${day}/${REGION}/${SERVICE}/aws4_request`;
  const toSign = ['AWS4-HMAC-SHA256', stamp, scope, sha256Hex(canonicalRequest)].join('\n');

  const signingKey = hmac(
    hmac(hmac(hmac(`AWS4${config.secretAccessKey}`, day), REGION), SERVICE),
    'aws4_request',
  );
  const signature = createHmac('sha256', signingKey).update(toSign).digest('hex');

  return {
    url: `https://${host}${encodePath(path)}${query ? `?${query}` : ''}`,
    headers: {
      ...headers,
      authorization:
        `AWS4-HMAC-SHA256 Credential=${config.accessKeyId}/${scope}, ` +
        `SignedHeaders=${signedHeaders}, Signature=${signature}`,
    },
  };
};

/** 오류 응답의 XML에서 S3 오류 코드를 뽑는다. 없으면 상태코드로 대신한다. */
const errorCodeOf = (body: string, status: number): string =>
  /<Code>([^<]*)<\/Code>/.exec(body)?.[1] ?? `HTTP_${status}`;

export interface PutOptions {
  readonly contentType?: string;
  readonly contentEncoding?: string;
  readonly cacheControl?: string;
}

export class R2Client {
  readonly #config: R2Config;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;

  constructor(config: R2Config) {
    for (const field of ['accountId', 'accessKeyId', 'secretAccessKey', 'bucket'] as const) {
      if (!config[field] || config[field].trim() === '') {
        throw new R2ConfigError(`${field}가 비어 있습니다`);
      }
    }
    if (!/^[0-9a-f]{32}$/.test(config.accountId)) {
      throw new R2ConfigError(`accountId가 32자리 hex가 아닙니다: ${config.accountId}`);
    }
    this.#config = config;
    this.#fetch = config.fetchImpl ?? globalThis.fetch;
    this.#timeoutMs = config.timeoutMs ?? 30_000;
  }

  get bucket(): string {
    return this.#config.bucket;
  }

  async #send(
    method: string,
    key: string,
    body?: Uint8Array,
    extraHeaders: Readonly<Record<string, string>> = {},
    query = '',
  ): Promise<Response> {
    const path = `/${this.#config.bucket}/${key}`.replace(/\/+$/, key === '' ? '' : '');
    const signed = signRequest(this.#config, method, path, query, body, new Date(), extraHeaders);

    // 주의: 서명 헤더에 자격증명이 들어간다. 어떤 경로로도 헤더를 로그에 내지 않는다.
    const res = await this.#fetch(signed.url, {
      method,
      headers: signed.headers,
      ...(body === undefined ? {} : { body }),
      signal: AbortSignal.timeout(this.#timeoutMs),
    });
    return res;
  }

  /** 객체를 올린다. 이미 있으면 덮어쓴다. */
  async put(key: string, body: Uint8Array, options: PutOptions = {}): Promise<void> {
    const headers: Record<string, string> = { 'content-length': String(body.byteLength) };
    if (options.contentType) headers['content-type'] = options.contentType;
    if (options.contentEncoding) headers['content-encoding'] = options.contentEncoding;
    if (options.cacheControl) headers['cache-control'] = options.cacheControl;

    const res = await this.#send('PUT', key, body, headers);
    if (!res.ok) {
      const text = await res.text();
      throw new R2Error(`PUT ${key} 실패 (${res.status})`, res.status, errorCodeOf(text, res.status));
    }
  }

  /**
   * 객체를 받는다. 없으면 null.
   *
   * **주의 — 올린 바이트와 다를 수 있다.** `content-encoding: gzip`으로 올린 객체는
   * `fetch`가 응답을 받으면서 **자동으로 압축을 푼다.** 즉 gzip 43바이트를 올려도
   * 여기서는 원본 JSON 23바이트가 나온다. 실호출로 확인한 동작이다.
   *
   * 이것은 손상이 아니라 의도된 경로다. 앱과 CDN도 같은 방식으로 투명하게 받으며,
   * 우리 콘텐츠 해시가 **압축 전 JSON** 기준이므로(§5.3) 오히려 대조에 바로 쓸 수 있다.
   * 저장된 gzip 바이트 그대로가 필요하면 `content-encoding`을 붙이지 말고 올려야 한다.
   */
  async get(key: string): Promise<Uint8Array | null> {
    const res = await this.#send('GET', key);
    if (res.status === 404) return null;
    if (!res.ok) {
      const text = await res.text();
      throw new R2Error(`GET ${key} 실패 (${res.status})`, res.status, errorCodeOf(text, res.status));
    }
    return new Uint8Array(await res.arrayBuffer());
  }

  /** 객체 존재 여부. 본문을 받지 않으므로 Class B 비용이 저렴하다. */
  async exists(key: string): Promise<boolean> {
    const res = await this.#send('HEAD', key);
    if (res.status === 404) return false;
    if (!res.ok) {
      throw new R2Error(`HEAD ${key} 실패 (${res.status})`, res.status, `HTTP_${res.status}`);
    }
    return true;
  }

  async delete(key: string): Promise<void> {
    const res = await this.#send('DELETE', key);
    // S3는 없는 키를 지워도 204를 준다.
    if (!res.ok && res.status !== 404) {
      const text = await res.text();
      throw new R2Error(`DELETE ${key} 실패 (${res.status})`, res.status, errorCodeOf(text, res.status));
    }
  }

  /**
   * 접두사로 키를 나열한다. 1000건씩 끊어 오므로 `continuationToken`으로 이어받는다.
   */
  async list(prefix = '', continuationToken?: string): Promise<{
    readonly keys: readonly string[];
    readonly nextToken: string | undefined;
  }> {
    const params = new URLSearchParams({ 'list-type': '2' });
    if (prefix) params.set('prefix', prefix);
    if (continuationToken) params.set('continuation-token', continuationToken);
    // S3 정규 쿼리는 키 순으로 정렬해야 서명이 맞는다.
    const query = [...params.entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&');

    const path = `/${this.#config.bucket}`;
    const signed = signRequest(this.#config, 'GET', path, query, undefined, new Date());
    const res = await this.#fetch(signed.url, {
      method: 'GET',
      headers: signed.headers,
      signal: AbortSignal.timeout(this.#timeoutMs),
    });

    const text = await res.text();
    if (!res.ok) {
      throw new R2Error(`LIST 실패 (${res.status})`, res.status, errorCodeOf(text, res.status));
    }
    return {
      keys: [...text.matchAll(/<Key>([^<]*)<\/Key>/g)].map((m) => m[1] ?? ''),
      nextToken: /<NextContinuationToken>([^<]*)<\/NextContinuationToken>/.exec(text)?.[1],
    };
  }
}

/** 환경변수에서 설정을 읽는다. 빠진 값은 즉시 실패로 알린다. */
export const configFromEnv = (env: NodeJS.ProcessEnv = process.env): R2Config => {
  const get = (name: string): string => {
    const value = env[name];
    if (!value || value.trim() === '') {
      throw new R2ConfigError(`환경변수 ${name}이(가) 없습니다. .env를 확인하세요.`);
    }
    return value.trim();
  };
  return {
    accountId: get('R2_ACCOUNT_ID'),
    accessKeyId: get('R2_ACCESS_KEY_ID'),
    secretAccessKey: get('R2_SECRET_ACCESS_KEY'),
    bucket: get('R2_BUCKET'),
  };
};
