import { gzipSync } from 'node:zlib';

import { describe, expect, test, vi } from 'vitest';

import {
  amzDate,
  configFromEnv,
  R2Client,
  R2ConfigError,
  signRequest,
  type R2Config,
  type R2Error,
} from './r2.js';

const CONFIG: R2Config = {
  accountId: 'f'.repeat(32),
  accessKeyId: 'AKIAEXAMPLE',
  secretAccessKey: 'secret-example',
  bucket: 'realdealmap-data',
};

const AT = new Date(Date.UTC(2026, 8, 7, 7, 15, 30));

const ok = (body = '', status = 200): Response =>
  ({
    ok: status >= 200 && status < 300,
    status,
    text: () => Promise.resolve(body),
    arrayBuffer: () => Promise.resolve(new TextEncoder().encode(body).buffer),
  }) as Response;

/** 요청을 기록하는 가짜 fetch. */
const stub = (responses: readonly (() => Response)[] = [() => ok()]) => {
  const calls: { url: string; method: string; headers: Record<string, string> }[] = [];
  let i = 0;
  const impl = vi.fn(async (url: unknown, init: unknown): Promise<Response> => {
    const opts = (init ?? {}) as { method?: string; headers?: Record<string, string> };
    calls.push({ url: String(url), method: opts.method ?? 'GET', headers: opts.headers ?? {} });
    const next = responses[Math.min(i, responses.length - 1)];
    i += 1;
    return next ? next() : ok();
  });
  return { impl: impl as unknown as typeof fetch, calls };
};

const clientWith = (responses?: readonly (() => Response)[]) => {
  const s = stub(responses);
  return { s, client: new R2Client({ ...CONFIG, fetchImpl: s.impl }) };
};

describe('설정 검증', () => {
  test.each(['accountId', 'accessKeyId', 'secretAccessKey', 'bucket'] as const)(
    '%s가 비면 거부한다',
    (field) => {
      expect(() => new R2Client({ ...CONFIG, [field]: '  ' })).toThrow(R2ConfigError);
    },
  );

  test('계정 ID가 32자리 hex가 아니면 거부한다', () => {
    // 대시보드 URL에서 잘못 복사하는 실수를 여기서 잡는다.
    expect(() => new R2Client({ ...CONFIG, accountId: 'not-hex' })).toThrow(R2ConfigError);
  });

  test('환경변수에서 설정을 읽는다', () => {
    const config = configFromEnv({
      R2_ACCOUNT_ID: 'a'.repeat(32),
      R2_ACCESS_KEY_ID: 'k',
      R2_SECRET_ACCESS_KEY: 's',
      R2_BUCKET: 'b',
    } as NodeJS.ProcessEnv);
    expect(config.bucket).toBe('b');
  });

  test('빠진 환경변수를 이름과 함께 알린다', () => {
    expect(() => configFromEnv({ R2_ACCOUNT_ID: 'a' } as NodeJS.ProcessEnv))
      .toThrow(/R2_ACCESS_KEY_ID/);
  });
});

describe('SigV4 서명', () => {
  const sign = (method = 'GET', path = '/b/k', body?: Uint8Array) =>
    signRequest(CONFIG, method, path, '', body, AT);

  test('시각을 ISO8601 basic으로 만든다', () => {
    expect(amzDate(AT)).toBe('20260907T071530Z');
  });

  test('서명이 결정적이다', () => {
    expect(sign().headers['authorization']).toBe(sign().headers['authorization']);
  });

  test('Credential 범위가 R2 규칙(auto/s3)을 따른다', () => {
    const auth = sign().headers['authorization'] ?? '';
    expect(auth).toContain('AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/20260907/auto/s3/aws4_request');
    expect(auth).toMatch(/Signature=[0-9a-f]{64}$/);
  });

  test('본문이 바뀌면 서명이 바뀐다', () => {
    const a = sign('PUT', '/b/k', new TextEncoder().encode('one'));
    const b = sign('PUT', '/b/k', new TextEncoder().encode('two'));
    expect(a.headers['authorization']).not.toBe(b.headers['authorization']);
  });

  test('본문 해시를 실제로 계산한다 — UNSIGNED-PAYLOAD를 쓰지 않는다', () => {
    // 전송 중 본문이 바뀌면 서버가 거부한다. 무결성 검사가 딸려 온다.
    const signed = sign('PUT', '/b/k', new TextEncoder().encode('x'));
    expect(signed.headers['x-amz-content-sha256']).toMatch(/^[0-9a-f]{64}$/);
    expect(signed.headers['x-amz-content-sha256']).not.toBe('UNSIGNED-PAYLOAD');
  });

  test('빈 본문은 빈 문자열의 해시를 쓴다', () => {
    expect(sign().headers['x-amz-content-sha256']).toBe(
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('경로의 특수문자를 인코딩하되 슬래시는 보존한다', () => {
    const signed = signRequest(CONFIG, 'GET', '/b/chunks/11110/a b+c.json', '', undefined, AT);
    expect(signed.url).toContain('/b/chunks/11110/a%20b%2Bc.json');
    expect(signed.url.split('/').length).toBeGreaterThan(4);
  });

  test('호스트가 계정 하위 도메인이다', () => {
    expect(sign().url.startsWith(`https://${'f'.repeat(32)}.r2.cloudflarestorage.com`)).toBe(true);
  });

  test('메서드가 다르면 서명이 다르다', () => {
    expect(sign('GET').headers['authorization']).not.toBe(sign('DELETE').headers['authorization']);
  });
});

describe('객체 연산', () => {
  const body = new TextEncoder().encode('hello');

  test('PUT이 본문과 헤더를 함께 보낸다', async () => {
    const { s, client } = clientWith();
    await client.put('chunks/x.json.gz', body, {
      contentType: 'application/json',
      contentEncoding: 'gzip',
      cacheControl: 'public, max-age=31536000, immutable',
    });

    const [call] = s.calls;
    expect(call?.method).toBe('PUT');
    expect(call?.url).toContain('/realdealmap-data/chunks/x.json.gz');
    expect(call?.headers['content-type']).toBe('application/json');
    expect(call?.headers['content-encoding']).toBe('gzip');
    expect(call?.headers['cache-control']).toBe('public, max-age=31536000, immutable');
    expect(call?.headers['content-length']).toBe('5');
  });

  test('GET이 본문을 돌려준다', async () => {
    const { client } = clientWith([() => ok('payload')]);
    const got = await client.get('k');
    expect(new TextDecoder().decode(got ?? new Uint8Array())).toBe('payload');
  });

  test('없는 객체는 null이다', async () => {
    const { client } = clientWith([() => ok('', 404)]);
    expect(await client.get('missing')).toBeNull();
  });

  test('gzip으로 올린 객체는 GET에서 자동으로 압축이 풀린다', async () => {
    // 실호출로 확인한 동작(2026-09-07). content-encoding을 붙이면 fetch가 받으면서 푼다.
    // put한 바이트와 get한 바이트가 다른 것이 정상이므로, 대조는 압축 전 내용으로 해야 한다.
    const json = new TextEncoder().encode('{"hello":"realdealmap"}');
    const gz = gzipSync(Buffer.from(json));
    expect(gz.byteLength).not.toBe(json.byteLength);

    // fetch가 이미 푼 뒤의 응답을 흉내낸다.
    const { client } = clientWith([() => ok('{"hello":"realdealmap"}')]);
    const got = await client.get('k.json.gz');
    expect(Buffer.from(got ?? new Uint8Array()).equals(Buffer.from(json))).toBe(true);
  });

  test('exists가 HEAD를 쓴다 — 본문을 받지 않는다', async () => {
    const { s, client } = clientWith([() => ok('', 200)]);
    expect(await client.exists('k')).toBe(true);
    expect(s.calls[0]?.method).toBe('HEAD');
  });

  test('없는 객체 삭제는 오류가 아니다', async () => {
    const { client } = clientWith([() => ok('', 404)]);
    await expect(client.delete('missing')).resolves.toBeUndefined();
  });

  test('오류 응답에서 S3 코드를 뽑는다', async () => {
    const xml = '<Error><Code>AccessDenied</Code><Message>no</Message></Error>';
    const { client } = clientWith([() => ok(xml, 403)]);
    await expect(client.put('k', body)).rejects.toMatchObject({
      name: 'R2Error',
      status: 403,
      code: 'AccessDenied',
    });
  });

  test('코드가 없으면 상태코드로 대신한다', async () => {
    const { client } = clientWith([() => ok('gateway down', 502)]);
    await expect(client.get('k')).rejects.toMatchObject({ code: 'HTTP_502' });
  });

  test('오류 메시지에 자격증명이 섞이지 않는다', async () => {
    const { client } = clientWith([() => ok('<Error><Code>X</Code></Error>', 403)]);
    try {
      await client.put('k', body);
      expect.unreachable('던져야 한다');
    } catch (error) {
      const message = (error as R2Error).message;
      expect(message).not.toContain(CONFIG.secretAccessKey);
      expect(message).not.toContain(CONFIG.accessKeyId);
    }
  });
});

describe('목록 조회', () => {
  const listXml = (keys: readonly string[], next?: string): string =>
    `<ListBucketResult>${keys.map((k) => `<Contents><Key>${k}</Key></Contents>`).join('')}` +
    (next ? `<NextContinuationToken>${next}</NextContinuationToken>` : '') +
    `</ListBucketResult>`;

  // 저장 용량은 여기서만 잴 수 있다. 매니페스트의 bytes를 더하면 살아 있는
  // 데이터만 세게 되어, 실제 R2에 쌓인 낡은 청크가 빠진다 (T6.5).
  test('객체 크기를 더해 돌려준다', async () => {
    const xml =
      '<ListBucketResult>' +
      '<Contents><Key>a</Key><Size>100</Size></Contents>' +
      '<Contents><Key>b</Key><Size>250</Size></Contents>' +
      '</ListBucketResult>';
    const { client } = clientWith([() => ok(xml)]);

    expect((await client.list()).bytes).toBe(350);
  });

  test('크기가 없는 응답은 0으로 센다', async () => {
    const { client } = clientWith([() => ok(listXml(['a']))]);

    expect((await client.list()).bytes).toBe(0);
  });

  test('접두사로 키를 나열한다', async () => {
    const { s, client } = clientWith([() => ok(listXml(['chunks/a', 'chunks/b']))]);
    const result = await client.list('chunks/');

    expect(result.keys).toEqual(['chunks/a', 'chunks/b']);
    expect(result.nextToken).toBeUndefined();
    expect(s.calls[0]?.url).toContain('list-type=2');
    expect(s.calls[0]?.url).toContain('prefix=chunks%2F');
  });

  test('이어받기 토큰을 돌려준다', async () => {
    const { client } = clientWith([() => ok(listXml(['a'], 'TOKEN123'))]);
    expect((await client.list()).nextToken).toBe('TOKEN123');
  });

  test('쿼리 파라미터가 정렬된다 — 정렬이 어긋나면 서명이 깨진다', async () => {
    const { s, client } = clientWith([() => ok(listXml([]))]);
    await client.list('p/', 'T');
    const query = (s.calls[0]?.url ?? '').split('?')[1] ?? '';
    const names = query.split('&').map((kv) => kv.split('=')[0] ?? '');
    expect(names).toEqual([...names].sort());
  });

  test('빈 버킷은 빈 목록이다', async () => {
    const { client } = clientWith([() => ok('<ListBucketResult></ListBucketResult>')]);
    expect((await client.list()).keys).toEqual([]);
  });
});
