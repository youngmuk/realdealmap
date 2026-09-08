import { describe, expect, test } from 'vitest';

import type { MissingAddress } from './geo.js';
import type { GeocodeOutcome, GeocodeProvider } from './geocode-provider.js';
import { Geocoder } from './geocoder.js';

/**
 * 한 곳이 막혔을 때 다음 곳이 이어받는지만 본다.
 *
 * 진짜 API 두 개를 흉내 내면 시험이 응답 형식에 묶인다. 형식은 각 제공자의
 * 시험이 맡고, 여기서는 **넘김 자체**만 다룬다.
 */
interface Fake extends GeocodeProvider {
  readonly calls: () => number;
}

const fake = (
  source: 'kakao' | 'vworld',
  label: string,
  script: readonly GeocodeOutcome[],
): Fake => {
  let index = 0;
  return {
    source,
    label,
    dailyQuota: 1000,
    calls: () => index,
    ask: async (): Promise<GeocodeOutcome> => {
      const next = script[Math.min(index, script.length - 1)];
      index += 1;
      return next ?? { kind: 'error', detail: '대본 없음' };
    },
  };
};

const found = (): GeocodeOutcome => ({ kind: 'found', lat: 37.5, lng: 127 });
const blocked = (reason: string): GeocodeOutcome => ({ kind: 'quota', reason });

const missing = (n: number): MissingAddress[] =>
  Array.from({ length: n }, (_, i) => ({
    key: `동${i}|${i}`,
    umdNm: `동${i}`,
    jibun: String(i),
    deals: n - i,
  }));

const run = (providers: readonly GeocodeProvider[], n: number) =>
  new Geocoder({
    providers,
    regionName: '서울특별시 강남구',
    concurrency: 1,
    today: '2026-09-08',
  }).run(missing(n));

describe('넘김', () => {
  test('앞이 막히면 뒤가 이어받는다', async () => {
    const kakao = fake('kakao', '카카오', [blocked('일간 한도(code -10)')]);
    const vworld = fake('vworld', 'VWorld', [found()]);

    const result = await run([kakao, vworld], 5);

    // 막힌 그 한 건은 처리되지 못하고 다음 실행으로 넘어간다.
    expect(kakao.calls()).toBe(1);
    expect(vworld.calls()).toBe(4);
    expect(result.found).toBe(4);
    expect(result.deferred).toHaveLength(1);
  });

  test('한 곳만 막힌 것으로는 실행을 끝내지 않는다', async () => {
    const result = await run(
      [fake('kakao', '카카오', [blocked('일간 한도')]), fake('vworld', 'VWorld', [found()])],
      5,
    );
    // 쓸 곳이 남았는데 `quotaExhausted`를 세우면 워크플로가 남은 지역을 통째로 건너뛴다.
    expect(result.quotaExhausted).toBe(false);
    expect(result.exhausted).toEqual(['카카오: 일간 한도']);
  });

  test('전부 막히면 그때 끝낸다', async () => {
    const result = await run(
      [
        fake('kakao', '카카오', [blocked('일간 한도')]),
        fake('vworld', 'VWorld', [blocked('OVER_REQUEST_LIMIT — 일간 한도 초과')]),
      ],
      5,
    );
    expect(result.quotaExhausted).toBe(true);
    expect(result.found).toBe(0);
    expect(result.deferred).toHaveLength(5);
    expect(result.exhausted).toHaveLength(2);
  });

  test('막힌 곳을 다시 부르지 않는다', async () => {
    const kakao = fake('kakao', '카카오', [blocked('일간 한도')]);
    await run([kakao, fake('vworld', 'VWorld', [found()])], 20);
    // 한 번 막힌 뒤로는 한 건도 더 보내지 않는다. 보내면 그저 버리는 왕복이다.
    expect(kakao.calls()).toBe(1);
  });
});

describe('출처 기록', () => {
  test('사전 항목에 답한 곳을 남긴다', async () => {
    const result = await run(
      [fake('kakao', '카카오', [blocked('일간 한도')]), fake('vworld', 'VWorld', [found()])],
      3,
    );
    const sources = Object.values(result.entries).map((e) => e.source);
    expect(sources).toEqual(['vworld', 'vworld']);
  });

  test('곳마다 몇 번 불렀는지 센다', async () => {
    const result = await run(
      [fake('kakao', '카카오', [found(), found(), blocked('일간 한도')]), fake('vworld', 'VWorld', [found()])],
      6,
    );
    expect(result.callsBySource).toEqual({ 카카오: 3, VWorld: 3 });
    expect(result.calls).toBe(6);
  });
});

describe('구성', () => {
  test('VWorld 키가 없으면 카카오 하나로 돈다', () => {
    const g = new Geocoder({ apiKey: 'K', vworldKey: '', regionName: '구' });
    expect(g.sources).toEqual(['카카오']);
  });

  test('VWorld 키가 있으면 카카오 뒤에 붙는다 — 큰 쿼터를 먼저 태운다', () => {
    const g = new Geocoder({ apiKey: 'K', vworldKey: 'V', regionName: '구' });
    expect(g.sources).toEqual(['카카오', 'VWorld']);
  });

  test('쓸 곳이 하나도 없으면 만들지 못한다', () => {
    expect(() => new Geocoder({ regionName: '구' })).toThrow();
  });
});

describe('병든 곳 접기', () => {
  const errors = (n: number): GeocodeOutcome[] =>
    Array.from({ length: n }, () => ({ kind: 'error', detail: 'HTTP 502' }) as GeocodeOutcome);

  test('내리 실패하는 곳은 접고 다음 곳으로 넘어간다', async () => {
    const sick = fake('kakao', '카카오', errors(100));
    const well = fake('vworld', 'VWorld', [found()]);

    const result = await new Geocoder({
      providers: [sick, well],
      regionName: '서울특별시 강남구',
      concurrency: 1,
      maxAttempts: 1,
      errorStreakLimit: 5,
      today: '2026-09-08',
    }).run(missing(20));

    // 다섯 번 버리고 접는다. 접지 않으면 예산 20을 전부 오류로 태운다.
    expect(sick.calls()).toBe(5);
    expect(well.calls()).toBe(15);
    expect(result.exhausted[0]).toContain('연속 오류');
  });

  test('성공하면 연속 실패가 끊긴다', async () => {
    // 실패 3 → 성공 → 실패 3. 한도가 5여도 접히지 않아야 한다.
    const flaky = fake('kakao', '카카오', [
      ...errors(3),
      found(),
      ...errors(3),
      found(),
    ]);

    const result = await new Geocoder({
      providers: [flaky],
      regionName: '서울특별시 강남구',
      concurrency: 1,
      maxAttempts: 1,
      errorStreakLimit: 5,
      today: '2026-09-08',
    }).run(missing(8));

    expect(result.exhausted).toEqual([]);
    expect(result.quotaExhausted).toBe(false);
  });
});
