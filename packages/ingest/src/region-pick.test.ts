import { describe, expect, test } from 'vitest';

import { pickCold, pickHot } from './region-pick.js';
import type { RegionIndex, RegionSummary } from './region-index.js';

const region = (
  sggCd: string,
  records: number,
  refreshedAt: string,
): RegionSummary => ({
  sggCd,
  name: `테스트 ${sggCd}`,
  sidoName: '테스트도',
  sggName: sggCd,
  records,
  sampled: records,
  located: records,
  refreshedAt,
});

const index = (regions: RegionSummary[]): RegionIndex => ({
  version: 1,
  generatedAt: '2026-09-08T00:00:00.000Z',
  regions,
});

const NOW = new Date('2026-09-08T12:00:00.000Z');
const hoursAgo = (h: number): string =>
  new Date(NOW.getTime() - h * 3_600_000).toISOString();

describe('예열 대상 고르기 (hot)', () => {
  // 사용량을 서버에 남기지 않기로 했으므로(설계상 관측 자체가 없다) 진짜
  // 인기를 알 방법이 없다. 거래 건수를 대리 지표로 쓴다 — 거래가 많은 곳이
  // 사람이 많이 사는 곳이고, 사람이 많이 사는 곳을 많이 볼 것이다.
  test('거래가 많은 지역부터 고른다', () => {
    const picked = pickHot(
      index([
        region('11110', 100, hoursAgo(5)),
        region('11230', 900, hoursAgo(5)),
        region('11680', 500, hoursAgo(5)),
      ]),
      2,
      NOW,
    );
    expect(picked).toEqual(['11230', '11680']);
  });

  // 사용자가 방금 열어 갱신이 걸린 지역을 또 갱신하면 국토부 호출만 태운다.
  test('막 갱신된 지역은 건너뛴다', () => {
    const picked = pickHot(
      index([
        region('11230', 900, hoursAgo(0.2)),
        region('11680', 500, hoursAgo(5)),
      ]),
      5,
      NOW,
    );
    expect(picked).toEqual(['11680']);
  });

  test('상한을 넘겨 고르지 않는다', () => {
    const picked = pickHot(
      index([
        region('a1111', 900, hoursAgo(5)),
        region('b1111', 800, hoursAgo(5)),
        region('c1111', 700, hoursAgo(5)),
      ]),
      2,
      NOW,
    );
    expect(picked).toHaveLength(2);
  });

  // 건수가 같으면 실행할 때마다 다른 지역이 뽑혀서는 안 된다. 같은 입력에
  // 같은 출력이라야 "어제 무엇이 돌았는지"를 로그 없이도 알 수 있다.
  test('건수가 같으면 코드 순으로 고정한다', () => {
    const picked = pickHot(
      index([
        region('11680', 500, hoursAgo(5)),
        region('11230', 500, hoursAgo(5)),
      ]),
      2,
      NOW,
    );
    expect(picked).toEqual(['11230', '11680']);
  });
});

describe('재동기 대상 고르기 (cold)', () => {
  test('오래 갱신되지 않은 지역부터 고른다', () => {
    const picked = pickCold(
      index([
        region('11110', 100, hoursAgo(200)),
        region('11230', 900, hoursAgo(30)),
        region('11680', 500, hoursAgo(400)),
      ]),
      2,
      NOW,
    );
    expect(picked).toEqual(['11680', '11110']);
  });

  // 전부 신선하면 아무것도 하지 않는다. 할 일이 없는데 도는 것은 비용만이다.
  test('충분히 신선하면 아무것도 고르지 않는다', () => {
    const picked = pickCold(
      index([
        region('11230', 900, hoursAgo(2)),
        region('11680', 500, hoursAgo(3)),
      ]),
      10,
      NOW,
    );
    expect(picked).toEqual([]);
  });

  test('갱신 시각이 깨져 있으면 가장 오래된 것으로 친다', () => {
    const picked = pickCold(
      index([
        region('11230', 900, hoursAgo(100)),
        region('11680', 500, '이건 날짜가 아니다'),
      ]),
      1,
      NOW,
    );
    expect(picked).toEqual(['11680']);
  });

  test('상한을 넘겨 고르지 않는다', () => {
    const picked = pickCold(
      index([
        region('11110', 1, hoursAgo(500)),
        region('11230', 1, hoursAgo(400)),
        region('11680', 1, hoursAgo(300)),
      ]),
      2,
      NOW,
    );
    expect(picked).toEqual(['11110', '11230']);
  });
});

describe('공통', () => {
  test('빈 색인이면 빈 목록이다', () => {
    expect(pickHot(index([]), 10, NOW)).toEqual([]);
    expect(pickCold(index([]), 10, NOW)).toEqual([]);
  });

  // 상한을 0이나 음수로 넘기는 실수가 조용히 "전부"로 읽히면 안 된다.
  test('상한이 0 이하면 아무것도 고르지 않는다', () => {
    const i = index([region('11230', 900, hoursAgo(500))]);
    expect(pickHot(i, 0, NOW)).toEqual([]);
    expect(pickCold(i, -1, NOW)).toEqual([]);
  });
});
