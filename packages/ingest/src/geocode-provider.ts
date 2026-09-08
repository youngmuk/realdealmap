import type { GeoSource } from './geo.js';

/**
 * 주소를 좌표로 바꿔 주는 **한 곳**의 규약.
 *
 * 곳을 여러 개 두는 이유는 정확도가 아니라 **쿼터**다. 카카오 하나만 쓰던 동안
 * 하루치(10만)를 태우고 나면 그날은 아무것도 못 했다 — 실제로 2026-09-07에
 * 101,324회를 쓰고 이튿날 하루를 통째로 놀렸다. 한 곳이 막히면 다음 곳으로
 * 넘어가면 그런 날이 없어진다.
 *
 * 섞어도 되는지는 실측으로 확인했다: 카카오가 이미 채운 42개 주소를 VWorld에
 * 다시 물어 본 결과 42건 모두 매칭됐고 거리는 중앙값 2m·최대 29m였다.
 * 지도에서 구분되지 않는 차이다.
 */

/**
 * 한 주소에 대한 답.
 *
 * `quota`는 "이 곳을 이번 실행에서 더는 못 쓴다"는 뜻이고, 한도 초과뿐 아니라
 * 인증키 문제도 여기 들어온다. 둘 다 "다시 물어도 소용없다"는 점에서 같지만
 * **사람에게는 전혀 다른 소식이므로** `reason`으로 구분해 남긴다. 구분하지 않으면
 * 키를 잘못 넣어 놓고 "쿼터 소진"이라는 로그를 보며 다음 날을 기다리게 된다.
 */
export type GeocodeOutcome =
  | { readonly kind: 'found'; readonly lat: number; readonly lng: number }
  | { readonly kind: 'nomatch' }
  | { readonly kind: 'quota'; readonly reason: string }
  | { readonly kind: 'error'; readonly detail: string };

export interface GeocodeProvider {
  /** 사전에 남길 이름. 나중에 어느 곳에서 온 좌표인지 가릴 수 있어야 한다 */
  readonly source: Exclude<GeoSource, 'nomatch'>;
  /** 사람이 읽는 이름. 로그와 요약에만 쓴다 */
  readonly label: string;
  /** 이 곳의 일간 무료 한도. 계획을 세울 때만 쓰고 강제하지는 않는다 */
  readonly dailyQuota: number;
  ask(address: string): Promise<GeocodeOutcome>;
}

export interface ProviderOptions {
  readonly apiKey: string;
  readonly fetchImpl?: typeof fetch;
  readonly timeoutMs?: number;
}
