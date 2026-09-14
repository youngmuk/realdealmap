import { describe, expect, it } from 'vitest';

import {
  choseongOf,
  isChoseongQuery,
  normalizeQuery,
  scoreOf,
  SEARCH_SCHEMA_VERSION,
  umdIndex,
  umdRowsOf,
} from './search.js';

describe('검색어 다듬기', () => {
  it('공백을 지운다 — 사람은 "중곡 동"과 "중곡동"을 같게 친다', () => {
    expect(normalizeQuery(' 중곡 동 ')).toBe('중곡동');
    expect(normalizeQuery('성산동 1가')).toBe('성산동1가');
  });

  it('라틴 글자는 대소문자를 맞춘다', () => {
    expect(normalizeQuery('IPark')).toBe('ipark');
  });
});

describe('초성', () => {
  it('음절에서 첫 자음을 뽑는다', () => {
    expect(choseongOf('중곡동')).toBe('ㅈㄱㄷ');
    expect(choseongOf('해운대구')).toBe('ㅎㅇㄷㄱ');
    // 쌍자음도 제 자리가 있다
    expect(choseongOf('까치울')).toBe('ㄲㅊㅇ');
  });

  it('한글이 아닌 글자는 그대로 둔다', () => {
    expect(choseongOf('e편한세상')).toBe('eㅍㅎㅅㅅ');
    expect(choseongOf('12-3')).toBe('12-3');
  });

  it('자음만 친 검색어를 가려낸다', () => {
    expect(isChoseongQuery('ㅈㄱㄷ')).toBe(true);
    expect(isChoseongQuery('중곡')).toBe(false);
    expect(isChoseongQuery('')).toBe(false);
  });
});

describe('점수', () => {
  it('완전히 같은 것이 가장 높다', () => {
    expect(scoreOf('중곡동', '중곡동')).toBe(1000);
  });

  // 사람은 이름의 앞을 치지 가운데를 치지 않는다.
  it('앞에서 맞는 것이 가운데서 맞는 것보다 높다', () => {
    expect(scoreOf('중곡동', '중곡')).toBeGreaterThan(scoreOf('용중곡리', '중곡'));
  });

  it('같은 방식으로 맞으면 짧은 이름이 위다', () => {
    expect(scoreOf('신정동', '신정')).toBeGreaterThan(scoreOf('신정제일동', '신정'));
  });

  it('초성으로도 맞는다', () => {
    expect(scoreOf('중곡동', 'ㅈㄱㄷ')).toBeGreaterThan(0);
    expect(scoreOf('중곡동', 'ㅎㅇㄷ')).toBe(0);
  });

  // 초성을 글자 앞에 두면 "ㄱㄴ" 한 방에 온 나라가 딸려 온다.
  it('글자로 맞는 것이 초성으로 맞는 것보다 항상 높다', () => {
    expect(scoreOf('중곡동', '중곡')).toBeGreaterThan(scoreOf('중곡동', 'ㅈㄱ'));
  });

  it('빈 검색어는 아무것도 맞히지 않는다', () => {
    expect(scoreOf('중곡동', '')).toBe(0);
  });

  it('공백이 섞여도 맞는다', () => {
    expect(scoreOf('성산동1가', normalizeQuery('성산동 1가'))).toBe(1000);
  });
});

describe('좌표 사전에서 뽑기', () => {
  const entries = {
    '중곡동|': { lat: 37.561153, lng: 127.084264 },
    '중곡동|12-3': { lat: 37.5612, lng: 127.0843 },
    '능동|': { lat: 37.5501, lng: 127.0801 },
  };

  it('법정동 중심점만 가져온다', () => {
    const rows = umdRowsOf('11215', entries);

    expect(rows.map((r) => r[0])).toEqual(['중곡동', '능동']);
    expect(rows[0]).toEqual(['중곡동', '11215', 37.561153, 127.084264]);
  });

  // 골라도 갈 곳이 없는 줄은 목록에 있으면 안 된다.
  it('좌표가 없거나 이름이 빈 것은 버린다', () => {
    const rows = umdRowsOf('11215', {
      '없는동|': {},
      '|': { lat: 37.5, lng: 127.0 },
      '깨진동|': { lat: Number.NaN, lng: 127.0 },
    });

    expect(rows).toEqual([]);
  });
});

describe('색인', () => {
  it('이름 순으로 정렬하고 같은 것은 하나만 남긴다', () => {
    const index = umdIndex('20260901', [
      ['능동', '11215', 37.55, 127.08],
      ['중곡동', '11215', 37.56, 127.08],
      ['능동', '11215', 37.55, 127.08],
      ['능동', '41111', 37.27, 127.01],
    ]);

    expect(index.umds.map((r) => `${r[0]}/${r[1]}`)).toEqual([
      '능동/11215',
      '능동/41111',
      '중곡동/11215',
    ]);
  });

  // 같은 자료면 같은 바이트여야 다시 구웠을 때 올릴 것이 없다.
  it('순서가 달라도 결과가 같다', () => {
    const a = umdIndex('20260901', [
      ['중곡동', '11215', 37.56, 127.08],
      ['능동', '11215', 37.55, 127.08],
    ]);
    const b = umdIndex('20260901', [
      ['능동', '11215', 37.55, 127.08],
      ['중곡동', '11215', 37.56, 127.08],
    ]);

    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  it('판과 출처를 싣는다', () => {
    const index = umdIndex('20260901', []);

    expect(index.schemaVersion).toBe(SEARCH_SCHEMA_VERSION);
    expect(index.source).toBe('20260901');
    expect(index.attribution).toContain('공공누리');
  });
});
