import { describe, expect, test, vi } from 'vitest';

import {
  InvalidRequestError,
  MolitClient,
  QuotaExceededError,
  UpstreamError,
} from './client.js';
import type { Task } from './tasks.js';

/** 응답 XML을 만든다. 실제 봉투와 같은 구조다. */
const dataXml = (items: readonly string[], totalCount = items.length, code = '000'): string =>
  `<response><header><resultCode>${code}</resultCode><resultMsg>OK</resultMsg></header>` +
  `<body><items>${items.join('')}</items>` +
  `<numOfRows>1000</numOfRows><pageNo>1</pageNo><totalCount>${totalCount}</totalCount></body></response>`;

const landItem = (jibun: string): string =>
  '<item>' +
  ['sggCd', 'sggNm', 'umdNm', 'jimok', 'landUse', 'dealYear', 'dealMonth', 'dealDay',
   'dealArea', 'dealAmount', 'shareDealingType', 'cdealType', 'cdealDay',
   'dealingGbn', 'estateAgentSggNm']
    .map((f) => `<${f}>v</${f}>`)
    .join('') +
  `<jibun>${jibun}</jibun></item>`;

const faultXml = (code: string): string =>
  `<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>E</errMsg>` +
  `<returnAuthMsg>M</returnAuthMsg><returnReasonCode>${code}</returnReasonCode>` +
  `</cmmMsgHeader></OpenAPI_ServiceResponse>`;

const ok = (body: string, status = 200): Response =>
  ({ status, text: () => Promise.resolve(body) }) as Response;

/** 호출을 기록하는 가짜 fetch. 응답을 순서대로 돌려준다. */
const stubFetch = (responses: readonly (() => Response | Promise<Response>)[]) => {
  const urls: string[] = [];
  let index = 0;
  const impl = vi.fn(async (input: unknown): Promise<Response> => {
    urls.push(String(input));
    const next = responses[Math.min(index, responses.length - 1)];
    index += 1;
    if (!next) throw new Error('응답이 부족하다');
    return next();
  });
  return { impl: impl as unknown as typeof fetch, urls, calls: () => index };
};

const client = (
  responses: readonly (() => Response | Promise<Response>)[],
  overrides: Record<string, unknown> = {},
) => {
  const stub = stubFetch(responses);
  return {
    stub,
    client: new MolitClient({
      serviceKey: 'TEST-KEY',
      fetchImpl: stub.impl,
      sleep: () => Promise.resolve(),
      ...overrides,
    }),
  };
};

describe('생성', () => {
  test('빈 서비스키를 거부한다', () => {
    expect(() => new MolitClient({ serviceKey: '  ' })).toThrow(InvalidRequestError);
  });
});

describe('요청 전 검증 (R-14)', () => {
  const { client: c } = client([() => ok(dataXml([]))]);

  test('폐지된 코드를 현행 코드로 바꿔서 호출한다', () => {
    // 구 코드로 호출하면 오류가 아니라 조용히 0건이 온다.
    expect(c.resolveSggCd('29110')).toBe('12210');
    expect(c.resolveSggCd('42110')).toBe('51110');
  });

  test('카탈로그에 없는 코드는 호출하지 않는다', () => {
    expect(() => c.resolveSggCd('99999')).toThrow(InvalidRequestError);
  });

  test('하위 일반구가 있는 상위 시는 거부한다', () => {
    // 수원시로 조회하면 하위 구와 중복되거나 0건이 온다.
    expect(() => c.resolveSggCd('41110')).toThrow(InvalidRequestError);
  });

  test.each(['1111', '111100', 'abcde', ''])('형식이 깨진 코드 %s를 거부한다', (code) => {
    expect(() => c.resolveSggCd(code)).toThrow(InvalidRequestError);
  });

  test.each(['2026-08', '20268', '', 'abcdef', '202600', '202613', '202699'])(
    '계약 연월 %s를 거부한다',
    async (period) => {
      // 자릿수만 세면 202613이 통과한다. 원천은 이런 요청에도 0건으로 답하므로
      // 오타가 "거래 없음"으로 위장된다(R-14).
      await expect(c.fetchPage('land/sale', '11110', period)).rejects.toThrow(InvalidRequestError);
    },
  );

  test.each([0, -1, 1.5])('pageNo %s를 거부한다', async (pageNo) => {
    await expect(c.fetchPage('land/sale', '11110', '202608', pageNo)).rejects.toThrow(
      InvalidRequestError,
    );
  });

  test.each([0, 1001, 2.5])('numOfRows %s를 거부한다', async (rows) => {
    await expect(c.fetchPage('land/sale', '11110', '202608', 1, rows)).rejects.toThrow(
      InvalidRequestError,
    );
  });

  test('검증 실패는 원천을 호출하지 않는다', async () => {
    const { client: c2, stub } = client([() => ok(dataXml([]))]);
    await expect(c2.fetchPage('land/sale', '99999', '202608')).rejects.toThrow(InvalidRequestError);
    expect(stub.calls()).toBe(0);
  });
});

describe('요청 구성', () => {
  test('오퍼레이션 경로와 파라미터가 규격대로다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([landItem('1')]))]);
    await c.fetchPage('land/sale', '11110', '202608', 2, 500);

    const url = stub.urls[0] ?? '';
    expect(url).toContain('/1613000/RTMSDataSvcLandTrade/getRTMSDataSvcLandTrade');
    expect(url).toContain('LAWD_CD=11110');
    expect(url).toContain('DEAL_YMD=202608');
    expect(url).toContain('pageNo=2');
    expect(url).toContain('numOfRows=500');
  });

  test('디코딩된 서비스키는 인코딩해서 넣는다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([]))], { serviceKey: 'a+b/c=' });
    await c.fetchPage('land/sale', '11110', '202608');
    expect(stub.urls[0]).toContain('serviceKey=a%2Bb%2Fc%3D');
  });

  test('이미 인코딩된 서비스키는 그대로 쓴다 — 이중 인코딩이면 에러 30이 난다', async () => {
    // 포털은 인코딩·디코딩 키를 함께 준다. 인코딩된 쪽을 .env에 넣는 경우가 많다.
    const { client: c, stub } = client([() => ok(dataXml([]))], { serviceKey: 'a%2Bb%2Fc%3D' });
    await c.fetchPage('land/sale', '11110', '202608');
    expect(stub.urls[0]).toContain('serviceKey=a%2Bb%2Fc%3D');
    expect(stub.urls[0]).not.toContain('%252B');
  });

  test('%XX 모양이 섞였어도 온전히 인코딩된 게 아니면 인코딩한다', async () => {
    // 키에 &가 들어간 채 그대로 붙으면 쿼리 파라미터가 갈라진다.
    const { client: c, stub } = client([() => ok(dataXml([]))], {
      serviceKey: 'ab%2Fcd&LAWD_CD=99999',
    });
    await c.fetchPage('land/sale', '11110', '202608');

    const url = stub.urls[0] ?? '';
    expect(url).toContain('serviceKey=ab%252Fcd%26LAWD_CD%3D99999');
    // 주입 시도가 진짜 파라미터를 덮어쓰지 못한다.
    expect(url.match(/LAWD_CD=/g)).toHaveLength(1);
    expect(url).toContain('LAWD_CD=11110');
  });

  test.each([
    ['샵으로 잘림', 'abc%2Fdef#frag'],
    ['공백 포함', 'abc%2F def'],
  ])('%s 키도 안전하게 인코딩된다', async (_label, key) => {
    const { client: c, stub } = client([() => ok(dataXml([]))], { serviceKey: key });
    await c.fetchPage('land/sale', '11110', '202608');
    expect(stub.urls[0]).not.toContain('#');
    expect(stub.urls[0]).not.toContain(' ');
  });
});

describe('오류 분류', () => {
  test.each(['01', '02', '04', '05'])('resultCode %s는 재시도한다', async (code) => {
    const { client: c, stub } = client(
      [() => ok(dataXml([], 0, code)), () => ok(dataXml([landItem('1')]))],
      { maxRetries: 3 },
    );
    const result = await c.fetchPage('land/sale', '11110', '202608');
    expect(result.attempts).toBe(2);
    expect(stub.calls()).toBe(2);
  });

  test.each(['10', '11', '20', '30'])('resultCode %s는 재시도하지 않는다', async (code) => {
    const { client: c, stub } = client([() => ok(dataXml([], 0, code))]);
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(stub.calls()).toBe(1);
  });

  test('네트워크 실패는 재시도한다', async () => {
    let first = true;
    const { client: c } = client([
      () => {
        if (first) {
          first = false;
          throw new Error('ECONNRESET');
        }
        return ok(dataXml([landItem('1')]));
      },
    ]);
    expect((await c.fetchPage('land/sale', '11110', '202608')).attempts).toBe(2);
  });

  test('재시도를 다 쓰면 마지막 오류를 던진다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([], 0, '01'))], { maxRetries: 3 });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(stub.calls()).toBe(3);
  });

  test('백오프가 지수적으로 늘어난다', async () => {
    const delays: number[] = [];
    const { client: c } = client([() => ok(dataXml([], 0, '01'))], {
      maxRetries: 4,
      baseDelayMs: 100,
      sleep: (ms: number) => {
        delays.push(ms);
        return Promise.resolve();
      },
    });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(delays).toEqual([100, 200, 400]);
  });

  test('인증 오류 봉투는 재시도하지 않는다', async () => {
    const { client: c, stub } = client([() => ok(faultXml('30'), 403)]);
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(stub.calls()).toBe(1);
  });

  test('결과 0건은 오류가 아니다', async () => {
    const { client: c } = client([() => ok(dataXml([], 0))]);
    const { response } = await c.fetchPage('land/sale', '11110', '202608');
    expect(response.items).toEqual([]);
    expect(response.totalCount).toBe(0);
  });
});

/**
 * 전송 실패는 원천이 답을 준 오류와 **다르게 다룬다.**
 *
 * 이 구분이 없던 시절 CI가 세 번 연속 죽었다. 원천에 연결 자체가 45초 동안
 * 안 붙었는데 재시도 창이 3.5초라 무조건 졌고, 첫 작업이 죽으면서 지역 27개
 * 조합이 통째로 버려졌다.
 */
describe('전송 실패 처리', () => {
  /** 항상 전송 계층에서 죽는 fetch. undici가 감싸는 모양을 흉내낸다. */
  const dead = (cause?: unknown) => () => {
    throw Object.assign(new TypeError('fetch failed'), cause === undefined ? {} : { cause });
  };

  test('원천이 답한 오류보다 많이 시도한다', async () => {
    const { client: c, stub } = client([dead()], { maxRetries: 4, transportRetries: 6 });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(stub.calls()).toBe(6);
  });

  // 두 일정이 실제로 갈라져 있는지 잠근다. 한쪽만 고치고 다른 쪽을 잊으면 여기서 걸린다.
  test('원천이 답한 오류는 좁은 한도를 그대로 쓴다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([], 0, '01'))], {
      maxRetries: 4,
      transportRetries: 6,
    });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(stub.calls()).toBe(4);
  });

  test('지터가 지수 백오프의 0.5~1.0배 안에 든다', async () => {
    const delays: number[] = [];
    const { client: c } = client([dead()], {
      transportRetries: 4,
      transportDelayMs: 1000,
      random: () => 0, // 하한
      sleep: (ms: number) => {
        delays.push(ms);
        return Promise.resolve();
      },
    });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(delays).toEqual([500, 1000, 2000]);
  });

  test('지터 상한은 지수값 그대로다', async () => {
    const delays: number[] = [];
    const { client: c } = client([dead()], {
      transportRetries: 4,
      transportDelayMs: 1000,
      random: () => 1, // 상한
      sleep: (ms: number) => {
        delays.push(ms);
        return Promise.resolve();
      },
    });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(delays).toEqual([1000, 2000, 4000]);
  });

  // 상한이 없으면 6회째가 64초가 되어 잡 제한을 위협한다.
  test('백오프가 30초를 넘지 않는다', async () => {
    const delays: number[] = [];
    const { client: c } = client([dead()], {
      transportRetries: 8,
      transportDelayMs: 2000,
      random: () => 1,
      sleep: (ms: number) => {
        delays.push(ms);
        return Promise.resolve();
      },
    });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(Math.max(...delays)).toBe(30_000);
  });

  // undici는 진짜 이유를 message가 아니라 cause에 넣는다.
  // 이것을 버리면 로그에 `fetch failed` 한 줄만 남아 원인을 알 수 없다.
  test('cause 사슬을 메시지에 편다', async () => {
    const inner = Object.assign(new Error('connect ETIMEDOUT 1.2.3.4:443'), {
      code: 'UND_ERR_CONNECT_TIMEOUT',
    });
    const { client: c } = client([dead(inner)], { transportRetries: 1 });

    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(
      /fetch failed ← connect ETIMEDOUT 1\.2\.3\.4:443 \(UND_ERR_CONNECT_TIMEOUT\)/,
    );
  });

  test('cause가 순환해도 멈춘다', async () => {
    const a = new Error('a');
    const b = new Error('b');
    Object.assign(a, { cause: b });
    Object.assign(b, { cause: a });
    const { client: c } = client([dead(a)], { transportRetries: 1 });

    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(/fetch failed ← a/);
  });
});

/**
 * 오류 메시지는 로그·CI 요약·잡 주석으로 흘러 나간다. 이 저장소는 public이다.
 * 어떤 오류가 URL을 통째로 담아 올지 보장할 수 없으므로 내보내기 직전에 지운다.
 */
describe('오류 메시지의 서비스키 제거', () => {
  const leak = (text: string) => () => {
    throw new Error(text);
  };
  const attempt = async (text: string, serviceKey = 'TEST-KEY'): Promise<string> => {
    const { client: c } = client([leak(text)], { serviceKey, transportRetries: 1 });
    try {
      await c.fetchPage('land/sale', '11110', '202608');
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }
    throw new Error('던지지 않았다');
  };

  test('키 원문을 지운다', async () => {
    expect(await attempt('보낸 곳: ...?serviceKey=TEST-KEY&LAWD_CD=11110')).not.toContain(
      'TEST-KEY',
    );
  });

  test('퍼센트 인코딩된 키도 지운다', async () => {
    const message = await attempt('...serviceKey=a%2Bb%2Fc&x=1', 'a+b/c');
    expect(message).not.toContain('a%2Bb%2Fc');
    expect(message).not.toContain('a+b/c');
  });

  // 키를 모르는 형태로 흘려도 파라미터 이름은 남는다. 값 쪽을 통째로 지운다.
  test('키를 못 알아봐도 serviceKey 값은 지운다', async () => {
    const message = await attempt('URL: https://x/y?serviceKey=WHATEVER-ELSE&pageNo=1');
    expect(message).toContain('serviceKey=***');
    expect(message).not.toContain('WHATEVER-ELSE');
    // 나머지 파라미터는 남아야 진단에 쓸모가 있다.
    expect(message).toContain('pageNo=1');
  });
});

describe('응답 상한과 제한 시간', () => {
  /** 지정한 바이트만큼 흘려보내는 스트림 응답. 본문 상한 검증용. */
  const streaming = (totalBytes: number, chunkSize = 1024): Response => {
    let sent = 0;
    return {
      status: 200,
      headers: { get: () => null },
      body: {
        getReader: () => ({
          read: () => {
            if (sent >= totalBytes) return Promise.resolve({ done: true, value: undefined });
            const size = Math.min(chunkSize, totalBytes - sent);
            sent += size;
            return Promise.resolve({ done: false, value: new Uint8Array(size) });
          },
          cancel: () => Promise.resolve(),
        }),
      },
    } as unknown as Response;
  };

  test('본문이 상한을 넘으면 읽기를 중단한다', async () => {
    // 상한이 없으면 끝없이 흘려보내는 원천에 CI 러너 메모리가 소진된다.
    const { client: c } = client([() => streaming(50_000)], { maxResponseBytes: 4_096 });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(/상한을 넘음/);
  });

  test('상한 초과는 재시도하지 않는다 — 다시 불러도 같은 결과다', async () => {
    const { client: c, stub } = client([() => streaming(50_000)], {
      maxResponseBytes: 4_096,
      maxRetries: 3,
    });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(stub.calls()).toBe(1);
  });

  test('content-length가 상한을 넘으면 본문을 읽기도 전에 거부한다', async () => {
    const res = {
      status: 200,
      headers: { get: (n: string) => (n === 'content-length' ? '999999999' : null) },
      text: () => Promise.reject(new Error('본문을 읽으면 안 된다')),
    } as unknown as Response;
    const { client: c } = client([() => res], { maxResponseBytes: 1_024 });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(/상한을 넘음/);
  });

  test('상한 안이면 정상 처리한다', async () => {
    const { client: c } = client([() => ok(dataXml([landItem('1')]))], {
      maxResponseBytes: 1024 * 1024,
    });
    const { response } = await c.fetchPage('land/sale', '11110', '202608');
    expect(response.items).toHaveLength(1);
  });

  test('요청에 중단 신호를 붙인다', async () => {
    let signal: unknown;
    const stub = vi.fn(async (_url: unknown, init: unknown): Promise<Response> => {
      signal = (init as { signal?: unknown } | undefined)?.signal;
      return ok(dataXml([]));
    });
    const c = new MolitClient({
      serviceKey: 'K',
      fetchImpl: stub as unknown as typeof fetch,
      sleep: () => Promise.resolve(),
    });
    await c.fetchPage('land/sale', '11110', '202608');
    expect(signal).toBeInstanceOf(AbortSignal);
  });
});

describe('쿼터', () => {
  test('유형별로 따로 센다', async () => {
    const { client: c } = client([() => ok(dataXml([landItem('1')]))]);
    await c.fetchPage('land/sale', '11110', '202608');
    expect(c.usage('land/sale')).toBe(1);
    expect(c.usage('apartment/sale')).toBe(0);
    expect(c.remaining('land/sale')).toBe(9_999);
  });

  test('한도를 넘으면 호출하지 않고 던진다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([]))], { dailyQuota: 1 });
    await c.fetchPage('land/sale', '11110', '202608');
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(QuotaExceededError);
    expect(stub.calls()).toBe(1);
  });

  test('원천이 코드 22를 주면 즉시 중단한다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([], 0, '22'))], { maxRetries: 3 });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(QuotaExceededError);
    expect(stub.calls()).toBe(1);
  });

  test('재시도도 쿼터를 소모한다', async () => {
    const { client: c } = client([() => ok(dataXml([], 0, '01'))], { maxRetries: 3 });
    await expect(c.fetchPage('land/sale', '11110', '202608')).rejects.toThrow(UpstreamError);
    expect(c.usage('land/sale')).toBe(3);
  });
});

describe('페이지네이션', () => {
  test('totalCount로 페이지 수를 직접 계산한다', async () => {
    // pageNo를 범위 밖으로 넣어도 원천이 오류를 주지 않으므로 응답에 의존하지 않는다.
    const { client: c, stub } = client([() => ok(dataXml([landItem('1')], 2_500))], {
      pageSize: 1000,
    });
    const result = await c.fetchAll('land/sale', '11110', '202608');
    expect(result.pages).toBe(3);
    expect(stub.calls()).toBe(3);
    expect(result.calls).toBe(3);
  });

  test('0건이어도 한 번은 부른다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([], 0))]);
    const result = await c.fetchAll('land/sale', '11110', '202608');
    expect(result.pages).toBe(1);
    expect(stub.calls()).toBe(1);
    expect(result.items).toEqual([]);
  });

  test('페이지를 이어붙인다', async () => {
    const { client: c } = client([() => ok(dataXml([landItem('1'), landItem('2')], 4))], {
      pageSize: 2,
    });
    expect((await c.fetchAll('land/sale', '11110', '202608')).items).toHaveLength(4);
  });

  test('폐지 코드로 부르면 결과에 현행 코드가 담긴다', async () => {
    const { client: c } = client([() => ok(dataXml([], 0))]);
    expect((await c.fetchAll('land/sale', '29110', '202608')).sggCd).toBe('12210');
  });

  test('스키마 변화를 페이지 전체에서 모은다', async () => {
    const extra = landItem('1').replace('</item>', '<newField>x</newField></item>');
    const { client: c } = client([() => ok(dataXml([extra], 1))]);
    const result = await c.fetchAll('land/sale', '11110', '202608');
    expect(result.drift.unknown).toEqual(['newField']);
  });

  test('한 페이지에만 없는 필드를 누락으로 오인하지 않는다', async () => {
    // 페이지별 missing을 합집합하면, 1페이지 항목에 없고 2페이지에만 있는 필드가
    // 실제로는 존재하는데도 "누락"으로 보고되어 거짓 경보가 난다.
    const complete = landItem('1');
    const withoutJimok = complete.replace('<jimok>v</jimok>', '');
    let page = 0;
    const { client: c } = client([
      () => {
        page += 1;
        return ok(dataXml([page === 1 ? withoutJimok : complete], 2));
      },
    ], { pageSize: 1 });

    const result = await c.fetchAll('land/sale', '11110', '202608');
    expect(result.pages).toBe(2);
    expect(result.drift.missing).toEqual([]);
  });

  test('모든 페이지에서 사라진 필드는 누락으로 잡는다', async () => {
    const withoutJimok = landItem('1').replace('<jimok>v</jimok>', '');
    const { client: c } = client([() => ok(dataXml([withoutJimok], 2))], { pageSize: 1 });
    const result = await c.fetchAll('land/sale', '11110', '202608');
    expect(result.drift.missing).toEqual(['jimok']);
  });
});

describe('작업 실행', () => {
  const task = (sggCd: string, period = '202608'): Task => ({
    sggCd,
    datasetKey: 'land/sale',
    period,
    hot: true,
  });

  test('여러 작업을 동시성 제한 아래 실행한다', async () => {
    const { client: c } = client([() => ok(dataXml([landItem('1')]))], { concurrency: 2 });
    const report = await c.runTasks([task('11110'), task('11140'), task('11170')]);
    expect(report.results).toHaveLength(3);
    expect(report.failures).toEqual([]);
  });

  test('동시 실행 수가 상한을 넘지 않는다', async () => {
    let active = 0;
    let peak = 0;
    const { client: c } = client(
      [
        async () => {
          active += 1;
          peak = Math.max(peak, active);
          await Promise.resolve();
          active -= 1;
          return ok(dataXml([]));
        },
      ],
      { concurrency: 2 },
    );
    await c.runTasks([task('11110'), task('11140'), task('11170'), task('11200')]);
    expect(peak).toBeLessThanOrEqual(2);
  });

  test('한 작업이 실패해도 나머지를 계속한다', async () => {
    const { client: c } = client([() => ok(dataXml([]))], { concurrency: 1 });
    const report = await c.runTasks([task('11110'), task('99999'), task('11140')]);
    expect(report.results).toHaveLength(2);
    expect(report.failures).toHaveLength(1);
    expect(report.failures[0]?.task.sggCd).toBe('99999');
    expect(report.failures[0]?.quotaExceeded).toBe(false);
  });

  test('쿼터가 소진되면 그 유형의 남은 작업을 건너뛴다', async () => {
    const { client: c, stub } = client([() => ok(dataXml([]))], {
      dailyQuota: 1,
      concurrency: 1,
    });
    const report = await c.runTasks([task('11110'), task('11140'), task('11170')]);

    expect(report.results).toHaveLength(1);
    expect(report.failures).toHaveLength(2);
    expect(report.failures.every((f) => f.quotaExceeded)).toBe(true);
    // 건너뛴 작업은 호출하지 않는다.
    expect(stub.calls()).toBe(1);
  });

  test('빈 작업목록은 빈 결과다', async () => {
    const { client: c } = client([() => ok(dataXml([]))]);
    expect(await c.runTasks([])).toEqual({ results: [], failures: [] });
  });
});
