import { describe, expect, it } from 'vitest';

import { utmkToWgs84, UtmkError, wgs84ToUtmk } from './utmk.js';

describe('UTM-K 변환', () => {
  it('좌표계 원점은 정의된 값 그대로 나온다', () => {
    // EPSG:5179의 정의상 (1,000,000, 2,000,000)은 정확히 (127.5°E, 38°N)이다.
    // 이 한 점은 근사가 아니라 정의라서, 틀리면 좌표계 설정 자체가 틀린 것이다.
    const origin = utmkToWgs84(1_000_000, 2_000_000);
    expect(origin.lng).toBeCloseTo(127.5, 6);
    expect(origin.lat).toBeCloseTo(38, 6);
  });

  it('서울시청 좌표가 알려진 값과 맞는다', () => {
    // 서울시청 (37.5665, 126.9780) ≈ UTM-K (953,901, 1,952,032)
    const seoul = utmkToWgs84(953_901, 1_952_032);
    expect(seoul.lat).toBeCloseTo(37.5665, 3);
    expect(seoul.lng).toBeCloseTo(126.978, 3);
  });

  it('왕복하면 1 mm 안에서 제자리로 돌아온다', () => {
    for (const [lat, lng] of [
      [37.5665, 126.978], // 서울
      [35.1796, 129.0756], // 부산
      [33.4996, 126.5312], // 제주
      [37.8813, 127.7298], // 춘천
    ]) {
      const { x, y } = wgs84ToUtmk(lat!, lng!);
      const back = utmkToWgs84(x, y);
      // 소수점 6자리로 반올림하므로 1e-6도(약 0.1 m) 안이면 제자리다.
      expect(back.lat).toBeCloseTo(lat!, 5);
      expect(back.lng).toBeCloseTo(lng!, 5);
    }
  });

  it('한반도 밖으로 나오면 던진다', () => {
    // x와 y를 바꿔 읽은 흔한 실수. 숫자만 봐서는 알 수 없고 지도에서도
    // "어딘가에는 찍히므로" 조용히 지나간다. 여기서 잡는다.
    expect(() => utmkToWgs84(1_952_032, 953_901)).toThrow(UtmkError);
  });

  it('숫자가 아니면 던진다', () => {
    expect(() => utmkToWgs84(Number.NaN, 2_000_000)).toThrow(UtmkError);
    expect(() => utmkToWgs84(1_000_000, Number.POSITIVE_INFINITY)).toThrow(UtmkError);
  });

  it('소수점 6자리로 맞춰 돌려준다', () => {
    const { lat, lng } = utmkToWgs84(953_901.1653, 1_952_032.081);
    expect(lat).toBe(Math.round(lat * 1e6) / 1e6);
    expect(lng).toBe(Math.round(lng * 1e6) / 1e6);
  });
});
