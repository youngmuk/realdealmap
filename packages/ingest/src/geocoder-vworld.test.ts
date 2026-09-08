import { describe, expect, test, vi } from 'vitest';

import { VWORLD_DAILY_QUOTA, VWorldProvider } from './geocoder-vworld.js';

const KEY = 'SECRET-VWORLD-KEY';

/** VWorld는 오류도 HTTP 200으로 돌려준다. 그 형태를 그대로 흉내 낸다. */
const body = (payload: unknown, status = 200): Response =>
  ({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(payload),
    text: () => Promise.resolve(JSON.stringify(payload)),
  }) as Response;

const provider = (responses: readonly (() => Response | Promise<Response>)[]) => {
  const urls: string[] = [];
  let index = 0;
  const impl = vi.fn(async (url: unknown) => {
    urls.push(String(url));
    const next = responses[Math.min(index, responses.length - 1)];
    index += 1;
    if (!next) throw new Error('응답이 부족하다');
    return next();
  });
  return {
    urls,
    provider: new VWorldProvider({ apiKey: KEY, fetchImpl: impl as unknown as typeof fetch }),
  };
};

const okPoint = () => body({ response: { status: 'OK', result: { point: { x: '127.02', y: '37.57' } } } });

describe('생성', () => {
  test('빈 키를 거부한다', () => {
    expect(() => new VWorldProvider({ apiKey: '   ' })).toThrow();
  });

  test('일간 한도를 밝힌다', () => {
    expect(new VWorldProvider({ apiKey: KEY }).dailyQuota).toBe(VWORLD_DAILY_QUOTA);
    expect(VWORLD_DAILY_QUOTA).toBe(40_000);
  });
});

describe('요청 형태', () => {
  test('지번(PARCEL)을 WGS84로 물어본다', async () => {
    const { provider: p, urls } = provider([okPoint]);
    await p.ask('서울특별시 종로구 숭인동 207-32');

    const url = new URL(urls[0] ?? '');
    expect(url.origin + url.pathname).toBe('https://api.vworld.kr/req/address');
    expect(url.searchParams.get('request')).toBe('getcoord');
    expect(url.searchParams.get('type')).toBe('PARCEL');
    expect(url.searchParams.get('crs')).toBe('EPSG:4326');
    expect(url.searchParams.get('address')).toBe('서울특별시 종로구 숭인동 207-32');
  });
});

describe('결과 분류', () => {
  test('OK는 좌표다 — x가 경도, y가 위도', async () => {
    const { provider: p } = provider([okPoint]);
    expect(await p.ask('주소')).toEqual({ kind: 'found', lat: 37.57, lng: 127.02 });
  });

  test('NOT_FOUND는 미매칭이다', async () => {
    const { provider: p } = provider([() => body({ response: { status: 'NOT_FOUND' } })]);
    expect(await p.ask('주소')).toEqual({ kind: 'nomatch' });
  });

  test('OK인데 좌표가 비면 미매칭으로 본다', async () => {
    const { provider: p } = provider([() => body({ response: { status: 'OK', result: {} } })]);
    expect(await p.ask('주소')).toEqual({ kind: 'nomatch' });
  });

  test('숫자로 못 읽는 좌표는 오류다 — 사전에 넣으면 그 지역 마커가 사라진다', async () => {
    const { provider: p } = provider([
      () => body({ response: { status: 'OK', result: { point: { x: 'N/A', y: 'N/A' } } } }),
    ]);
    expect(await p.ask('주소')).toMatchObject({ kind: 'error' });
  });
});

describe('막힘', () => {
  test('OVER_REQUEST_LIMIT은 쿼터다', async () => {
    const { provider: p } = provider([
      () => body({ response: { status: 'ERROR', error: { code: 'OVER_REQUEST_LIMIT' } } }),
    ]);
    const out = await p.ask('주소');
    expect(out.kind).toBe('quota');
    expect(out.kind === 'quota' && out.reason).toContain('일간 한도');
  });

  test('인증키 문제도 쿼터로 다루되 사유를 남긴다', async () => {
    const { provider: p } = provider([
      () => body({ response: { status: 'ERROR', error: { code: 'INVALID_KEY' } } }),
    ]);
    const out = await p.ask('주소');
    // 동작은 "이 곳을 더 쓰지 않는다"로 같지만, 사람이 읽는 사유는 달라야 한다.
    expect(out.kind).toBe('quota');
    expect(out.kind === 'quota' && out.reason).toContain('INVALID_KEY');
    expect(out.kind === 'quota' && out.reason).not.toContain('일간 한도');
  });

  test('모르는 오류 코드는 쿼터가 아니라 오류다 — 멀쩡한 실행을 멈추지 않는다', async () => {
    const { provider: p } = provider([
      () => body({ response: { status: 'ERROR', error: { code: 'SYSTEM_ERROR' } } }),
    ]);
    expect(await p.ask('주소')).toMatchObject({ kind: 'error' });
  });
});

describe('키 노출', () => {
  test('HTTP 오류 메시지에 인증키가 실리지 않는다', async () => {
    // 요청을 되비추는 응답이 오면 본문에 키가 들어 있다. 본문을 옮기면 로그에 박힌다.
    const { provider: p } = provider([() => body({ echo: `key=${KEY}` }, 500)]);
    const out = await p.ask('주소');
    expect(out.kind).toBe('error');
    expect(JSON.stringify(out)).not.toContain(KEY);
  });

  test('파싱 실패 메시지에도 인증키가 실리지 않는다', async () => {
    const { provider: p } = provider([
      () =>
        ({
          ok: true,
          status: 200,
          json: () => Promise.reject(new Error('unexpected token')),
        }) as Response,
    ]);
    const out = await p.ask('주소');
    expect(JSON.stringify(out)).not.toContain(KEY);
  });
});
