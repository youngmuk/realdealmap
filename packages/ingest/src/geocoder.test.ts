import { describe, expect, test, vi } from 'vitest';

import type { MissingAddress } from './geo.js';
import { Geocoder, KAKAO_DAILY_QUOTA } from './geocoder.js';

const ok = (lat: string, lng: string): Response =>
  ({
    ok: true,
    status: 200,
    json: () => Promise.resolve({ documents: [{ x: lng, y: lat }] }),
  }) as Response;

const empty = (): Response =>
  ({ ok: true, status: 200, json: () => Promise.resolve({ documents: [] }) }) as Response;

const status = (code: number, body = ''): Response =>
  ({ ok: false, status: code, text: () => Promise.resolve(body) }) as Response;

/** 응답을 순서대로 돌려주는 가짜 fetch. 모자라면 마지막 것을 반복한다. */
const stub = (responses: readonly (() => Response | Promise<Response>)[]) => {
  const urls: string[] = [];
  const headers: Record<string, string>[] = [];
  let index = 0;
  const impl = vi.fn(async (url: unknown, init: unknown) => {
    urls.push(String(url));
    headers.push(((init as RequestInit)?.headers ?? {}) as Record<string, string>);
    const next = responses[Math.min(index, responses.length - 1)];
    index += 1;
    if (!next) throw new Error('응답이 부족하다');
    return next();
  });
  return { impl: impl as unknown as typeof fetch, urls, headers, calls: () => index };
};

const geocoder = (
  responses: readonly (() => Response | Promise<Response>)[],
  over: Record<string, unknown> = {},
) => {
  const s = stub(responses);
  return {
    stub: s,
    geocoder: new Geocoder({
      apiKey: 'TEST-KEY',
      regionName: '서울특별시 강남구',
      fetchImpl: s.impl,
      sleep: () => Promise.resolve(),
      today: '2026-09-07',
      concurrency: 1,
      ...over,
    }),
  };
};

const missing = (n: number): MissingAddress[] =>
  Array.from({ length: n }, (_, i) => ({
    key: `동${i}|${i}`,
    umdNm: `동${i}`,
    jibun: String(i),
    deals: n - i,
  }));

describe('생성', () => {
  test('빈 키를 거부한다', () => {
    expect(() => new Geocoder({ apiKey: '  ', regionName: '구' })).toThrow();
  });
});

describe('요청 형태', () => {
  test('키는 헤더로만 나가고 URL에는 없다', async () => {
    const { geocoder: g, stub: s } = geocoder([() => ok('37.5', '127.0')]);
    await g.run(missing(1));

    expect(s.headers[0]?.Authorization).toBe('KakaoAK TEST-KEY');
    expect(s.urls[0]).not.toContain('TEST-KEY');
  });

  test('지역명과 법정동·지번을 합쳐 묻는다', async () => {
    const { geocoder: g, stub: s } = geocoder([() => ok('37.5', '127.0')]);
    await g.run([{ key: '논현동|1', umdNm: '논현동', jibun: '1', deals: 1 }]);
    expect(decodeURIComponent(s.urls[0] ?? '')).toContain('서울특별시 강남구 논현동 1');
  });

  test('지번이 없으면 법정동까지만 묻는다', async () => {
    const { geocoder: g, stub: s } = geocoder([() => ok('37.5', '127.0')]);
    await g.run([{ key: '논현동|', umdNm: '논현동', jibun: null, deals: 1 }]);
    const url = decodeURIComponent(s.urls[0] ?? '');
    expect(url).toContain('서울특별시 강남구 논현동');
    expect(url).not.toMatch(/논현동\s+\S/);
  });
});

describe('결과 분류', () => {
  test('좌표를 찾으면 사전 항목이 된다', async () => {
    const { geocoder: g } = geocoder([() => ok('37.512345678', '127.098765432')]);
    const result = await g.run(missing(1));

    expect(result.found).toBe(1);
    // 6자리로 자른다. 지도에서 6자리는 약 10cm라 그 아래는 의미가 없고 파일만 커진다.
    expect(result.entries['동0|0']).toEqual({
      lat: 37.512346,
      lng: 127.098765,
      source: 'kakao',
      checkedOn: '2026-09-07',
    });
  });

  // 실패를 기록하지 않으면 원천이 모르는 주소를 갱신할 때마다 다시 묻는다.
  test('미매칭도 사전에 기록한다', async () => {
    const { geocoder: g } = geocoder([empty]);
    const result = await g.run(missing(1));

    expect(result.nomatch).toBe(1);
    expect(result.entries['동0|0']?.source).toBe('nomatch');
  });

  test('미매칭은 재시도하지 않는다', async () => {
    const { geocoder: g, stub: s } = geocoder([empty], { maxAttempts: 3 });
    await g.run(missing(1));
    expect(s.calls()).toBe(1);
  });
});

describe('재시도', () => {
  test('일시적 실패는 다시 시도한다', async () => {
    let first = true;
    const { geocoder: g, stub: s } = geocoder([
      () => {
        if (first) {
          first = false;
          return status(500);
        }
        return ok('37.5', '127.0');
      },
    ]);
    const result = await g.run(missing(1));
    expect(s.calls()).toBe(2);
    expect(result.found).toBe(1);
  });

  test('전송 실패도 다시 시도한다', async () => {
    let first = true;
    const { geocoder: g, stub: s } = geocoder([
      () => {
        if (first) {
          first = false;
          throw new TypeError('fetch failed');
        }
        return ok('37.5', '127.0');
      },
    ]);
    await g.run(missing(1));
    expect(s.calls()).toBe(2);
  });

  // 첫 판에서 응답 본문을 버려 실패 1,288건의 이유를 알 수 없었다.
  test('실패 사유에 응답 본문을 담는다', async () => {
    const { geocoder: g } = geocoder([() => status(400, '{"msg":"bad query"}')], {
      maxAttempts: 1,
    });
    const result = await g.run(missing(1));
    expect(result.errors[0]).toContain('bad query');
    expect(result.errors[0]).toContain('400');
  });

  test('끝내 실패하면 사전에 넣지 않고 이월한다', async () => {
    const { geocoder: g } = geocoder([() => status(500)], { maxAttempts: 2 });
    const result = await g.run(missing(1));

    expect(result.entries).toEqual({});
    expect(result.deferred.map((d) => d.key)).toEqual(['동0|0']);
  });
});

describe('쿼터', () => {
  test('예산을 넘겨 호출하지 않는다', async () => {
    const { geocoder: g, stub: s } = geocoder([() => ok('37.5', '127.0')], { budget: 3 });
    const result = await g.run(missing(10));

    expect(s.calls()).toBe(3);
    expect(result.calls).toBe(3);
    expect(result.deferred).toHaveLength(7);
  });

  // 잘려도 커버리지가 가장 많이 오르는 순서로 채워져야 한다.
  test('예산이 모자라면 앞에서부터 처리한다', async () => {
    const { geocoder: g } = geocoder([() => ok('37.5', '127.0')], { budget: 2 });
    const result = await g.run(missing(5));
    expect(Object.keys(result.entries).sort()).toEqual(['동0|0', '동1|1']);
  });

  test('429가 오면 즉시 멈추고 나머지를 이월한다', async () => {
    const { geocoder: g } = geocoder([() => status(429)]);
    const result = await g.run(missing(5));

    expect(result.quotaExhausted).toBe(true);
    expect(result.deferred).toHaveLength(5);
  });

  // 실전에서 하루치를 태우고 알았다. 카카오는 한도를 429가 아니라 400으로 알린다.
  // 이것을 일반 오류로 두면 재시도 3회를 돌고 다음 지역으로 넘어가며, 남은 지역
  // 전부가 "성공했지만 0건"으로 조용히 지나간다. 실제로 그렇게 6개 지역을 잃었다.
  test('한도 초과는 400으로 온다 — 이것도 쿼터로 읽는다', async () => {
    const body = JSON.stringify({
      errorType: 'BadRequest',
      message: 'API limit has been exceeded.',
      code: -10,
    });
    const { geocoder: g, stub: s } = geocoder([() => status(400, body)]);
    const result = await g.run(missing(5));

    expect(result.quotaExhausted).toBe(true);
    expect(result.deferred).toHaveLength(5);
    // 다시 물어도 같은 답이다. 재시도로 호출을 더 태우면 안 된다.
    expect(s.calls()).toBe(1);
  });

  test('한도와 무관한 400은 그냥 오류다', async () => {
    const { geocoder: g } = geocoder([() => status(400, '{"message":"query is required"}')]);
    const result = await g.run(missing(2));

    expect(result.quotaExhausted).toBe(false);
    expect(result.errors).toHaveLength(2);
  });

  test('기본 예산은 카카오 일간 한도다', async () => {
    expect(KAKAO_DAILY_QUOTA).toBe(100_000);
  });

  test('대상이 없으면 아무것도 호출하지 않는다', async () => {
    const { geocoder: g, stub: s } = geocoder([() => ok('37.5', '127.0')]);
    const result = await g.run([]);
    expect(s.calls()).toBe(0);
    expect(result.deferred).toEqual([]);
  });
});

describe('동시 실행', () => {
  test('여러 개를 동시에 처리해도 결과가 온전하다', async () => {
    const { geocoder: g } = geocoder([() => ok('37.5', '127.0')], { concurrency: 4 });
    const result = await g.run(missing(12));

    expect(result.found).toBe(12);
    expect(Object.keys(result.entries)).toHaveLength(12);
    expect(result.deferred).toEqual([]);
  });

  // cursor는 동시 실행 때문에 실제 처리분보다 앞서 있을 수 있다.
  // 이월 목록을 cursor로 계산하면 처리된 것이 이월되거나 그 반대가 된다.
  test('동시 실행에서도 이월 목록이 정확하다', async () => {
    const { geocoder: g } = geocoder([() => ok('37.5', '127.0')], {
      concurrency: 4,
      budget: 5,
    });
    const result = await g.run(missing(12));

    expect(Object.keys(result.entries)).toHaveLength(result.found + result.nomatch);
    expect(result.deferred).toHaveLength(12 - Object.keys(result.entries).length);
    for (const d of result.deferred) {
      expect(result.entries[d.key]).toBeUndefined();
    }
  });
});
