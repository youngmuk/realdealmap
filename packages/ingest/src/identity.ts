import { createHash } from 'node:crypto';

import type { Transaction } from './normalize.js';

/**
 * 거래 식별과 변경 감지.
 *
 * 원천에 영속 거래 ID가 없어 내용으로 키를 만든다. 설계상 중요한 선택이 하나 있다.
 *
 * **식별키에 금액을 넣지 않는다.** 선행 문서(§5.5)는 거래금액을 복합키에 포함했지만,
 * 그러면 가격 정정이 "기존 건 삭제 + 새 건 추가"로 보여 정정을 감지할 수 없다.
 * 금액은 식별이 아니라 **내용**에 두어야 정정이 변경으로 드러난다.
 *
 * 대신 금액을 뺀 만큼 서로 다른 두 거래가 같은 키를 가질 수 있다
 * (같은 단지·같은 날·같은 층·같은 면적). 이때는 병합해서 한 건을 잃는 대신
 * **내용해시로 정렬한 뒤 발생순번을 붙여 둘 다 보존**한다.
 * 정렬을 거치므로 원천의 응답 순서가 흔들려도 순번이 바뀌지 않는다.
 */

const sha256 = (parts: readonly string[]): string =>
  createHash('sha256').update(JSON.stringify(parts)).digest('hex');

/**
 * 코드포인트 순 비교.
 *
 * `localeCompare`를 쓰면 안 된다. 이 정렬이 발생순번을 정하고, 순번이 id를 정하고,
 * id가 청크의 정규 JSON에 들어간다 — 즉 **결정성 경로 위에 있다.**
 * 로케일·ICU 빌드에 따라 결과가 달라질 수 있는 비교를 여기에 두면
 * 환경마다 다른 청크가 만들어진다. `chunk.ts`의 `canonical()`도 같은 이유로 서수 비교를 쓴다.
 */
const ordinal = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);

/**
 * 이 거래가 "무엇인가"를 정하는 부분. 시간이 지나도 변하지 않아야 한다.
 *
 * 단독다가구 전월세는 지번도 건물명도 없으므로(§3.1) 쓸 수 있는 항목이 다르다.
 * 유형마다 다른 키를 쓰지 않으면 이 유형 전체가 한 덩어리로 뭉친다.
 *
 * **건물명(`name`)은 쓰지 않는다.** 원천의 표기가 흔들리기 때문이다 — T1.5에서
 * 한 스냅샷 안에서만도 같은 주소에 두 가지 이름이 붙은 사례를 23건 확인했다
 * (`쌍용플레티넘밸류`/`쌍용플래티넘밸류` 같은 원천 오타, `우성캐릭터빌`/`우성캐릭터-빌`).
 * 갱신 사이에 표기가 바뀌면 같은 거래가 `removed`+`added`로 보이고,
 * 하필 `removed`는 R-14 탐지 신호다. 정규화로는 오타를 못 잡는다.
 *
 * 이름을 빼면 같은 지번·면적·층·건축년도의 서로 다른 건물이 한 식별키로 묶일 수 있다.
 * 그래도 `indexSnapshot`의 발생순번이 둘 다 보존하므로 데이터가 사라지지는 않는다.
 * **불안정한 구분보다 안정적인 병합이 낫다** — 금액을 식별키에서 뺀 것과 같은 판단이다.
 */
export const identityParts = (tx: Transaction): readonly string[] => {
  const common = [tx.datasetKey, tx.sggCd, tx.umdNm, tx.contractedOn];

  if (tx.precision === 'umd' && tx.jibun === null) {
    // 위치를 좁힐 항목이 없다. 면적·건축년도까지 끌어 써야 겨우 구분된다.
    return [...common, String(tx.areaSqm), String(tx.builtYear), String(tx.floor)];
  }
  return [
    ...common,
    tx.jibun ?? '',
    String(tx.areaSqm),
    String(tx.floor),
    String(tx.builtYear),
  ];
};

/** 시간에 따라 바뀔 수 있는 부분. 금액과 해제 상태가 여기 들어간다. */
export const contentParts = (tx: Transaction): readonly string[] => [
  String(tx.amount),
  String(tx.deposit),
  String(tx.monthlyRent),
  String(tx.cancelled),
  tx.cancelledOn ?? '',
];

/** 내용 지문. 같은 식별키 안에서 정정을 감지하고 순번을 정하는 데 쓴다. */
export const contentHash = (tx: Transaction): string => sha256(contentParts(tx));

/** 식별 지문. 같은 거래로 볼 것들이 공유한다(발생순번 제외). */
export const identityHash = (tx: Transaction): string => sha256(identityParts(tx));

/** 발생순번까지 반영한 최종 식별자. 스냅샷 사이에서 이 값으로 짝을 맞춘다. */
export const transactionId = (tx: Transaction, occurrence: number): string =>
  sha256([identityHash(tx), String(occurrence)]);

export interface IndexedTransaction {
  readonly id: string;
  readonly occurrence: number;
  readonly transaction: Transaction;
}

/**
 * 스냅샷에 결정적 식별자를 부여한다.
 *
 * 같은 식별키가 여러 번 나오면 내용해시 순으로 줄을 세워 순번을 매긴다.
 * 입력 순서와 무관하게 같은 결과가 나오는 것이 요점이다.
 */
export const indexSnapshot = (
  transactions: readonly Transaction[],
): readonly IndexedTransaction[] => {
  const groups = new Map<string, Transaction[]>();
  for (const tx of transactions) {
    const key = identityHash(tx);
    const bucket = groups.get(key);
    if (bucket) bucket.push(tx);
    else groups.set(key, [tx]);
  }

  const indexed: IndexedTransaction[] = [];
  for (const bucket of groups.values()) {
    const ordered = [...bucket].sort((a, b) => ordinal(contentHash(a), contentHash(b)));
    ordered.forEach((transaction, occurrence) => {
      indexed.push({ id: transactionId(transaction, occurrence), occurrence, transaction });
    });
  }
  return indexed.sort((a, b) => ordinal(a.id, b.id));
};

export interface ChangedTransaction {
  readonly id: string;
  readonly before: Transaction;
  readonly after: Transaction;
}

export interface SnapshotDiff {
  readonly added: readonly Transaction[];
  /** 금액 정정 등 내용이 바뀐 건 */
  readonly changed: readonly ChangedTransaction[];
  /** 이번에 해제로 바뀐 건. `changed`에도 포함된다 */
  readonly cancelled: readonly Transaction[];
  /** 원천에서 사라진 건. 해제와 다르며, 조용한 소실이므로 따로 본다 */
  readonly removed: readonly Transaction[];
  readonly unchangedCount: number;
}

/**
 * 이전 스냅샷과 새 스냅샷을 비교한다.
 *
 * `removed`는 해제가 아니다. 원천이 이유 없이 건을 빼는 경우가 있고,
 * R-14 때문에 그것이 장애인지 정상인지 응답만으로는 알 수 없으므로 분리해 보고한다.
 */
export const diffSnapshots = (
  before: readonly Transaction[],
  after: readonly Transaction[],
): SnapshotDiff => {
  const previous = new Map(indexSnapshot(before).map((i) => [i.id, i.transaction]));
  const current = indexSnapshot(after);

  const added: Transaction[] = [];
  const changed: ChangedTransaction[] = [];
  const cancelled: Transaction[] = [];
  let unchangedCount = 0;

  const seen = new Set<string>();
  for (const { id, transaction } of current) {
    seen.add(id);
    const old = previous.get(id);
    if (!old) {
      added.push(transaction);
      continue;
    }
    if (contentHash(old) === contentHash(transaction)) {
      unchangedCount += 1;
      continue;
    }
    changed.push({ id, before: old, after: transaction });
    if (!old.cancelled && transaction.cancelled) cancelled.push(transaction);
  }

  const removed = [...previous.entries()]
    .filter(([id]) => !seen.has(id))
    .map(([, transaction]) => transaction);

  return { added, changed, cancelled, removed, unchangedCount };
};
