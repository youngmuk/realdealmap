import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import {
  contentHash,
  diffSnapshots,
  identityHash,
  identityParts,
  indexSnapshot,
} from './identity.js';
import { normalizeAll, type Transaction } from './normalize.js';
import { parseResponse } from './parse.js';

const FIXTURE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../test/fixtures');

const load = (key: string): readonly Transaction[] => {
  const name = key.replace('/', '-');
  const parsed = parseResponse(key as never, readFileSync(resolve(FIXTURE_DIR, name + '.xml'), 'utf8'));
  if (parsed.kind !== 'data') throw new Error('data 봉투가 아니다');
  return normalizeAll(key as never, parsed.items).transactions;
};

const withField = <K extends keyof Transaction>(
  tx: Transaction,
  field: K,
  value: Transaction[K],
): Transaction => ({ ...tx, [field]: value });

const first = (key: string): Transaction => {
  const [tx] = load(key);
  if (!tx) throw new Error('픽스처가 비었다');
  return tx;
};

describe('식별키', () => {
  test('같은 거래는 같은 식별키를 낸다', () => {
    const tx = first('apartment/sale');
    expect(identityHash(tx)).toBe(identityHash({ ...tx }));
  });

  test('금액은 식별에 들어가지 않는다 — 정정을 감지하기 위해서다', () => {
    const tx = first('apartment/sale');
    expect(identityHash(withField(tx, 'amount', 999999))).toBe(identityHash(tx));
    expect(contentHash(withField(tx, 'amount', 999999))).not.toBe(contentHash(tx));
  });

  // T1.5 실측: 원천이 같은 건물을 두 가지로 적는다. 한 스냅샷 안에서만도 23건이었다.
  // 이름이 식별에 참여하면 표기가 흔들릴 때 같은 거래가 removed+added로 보이고,
  // 하필 removed는 R-14 탐지 신호다.
  test.each([
    ['쌍용플레티넘밸류', '쌍용플래티넘밸류'],
    ['우성캐릭터빌', '우성캐릭터-빌'],
    ['이지마루역삼', '이지마루 역삼'],
    ['LG선릉에클라트(B)', 'LG선릉에클라트B'],
  ])('건물명이 %s → %s 로 바뀌어도 같은 거래다', (before, after) => {
    const tx = first('apartment/sale');
    expect(identityHash(withField(tx, 'name', after))).toBe(
      identityHash(withField(tx, 'name', before)),
    );
  });

  test('표기가 바뀌어도 removed로 오인하지 않는다', () => {
    const tx = first('apartment/sale');
    const renamed = withField(tx, 'name', '쌍용플래티넘밸류');
    const diff = diffSnapshots([withField(tx, 'name', '쌍용플레티넘밸류')], [renamed]);

    expect(diff.removed).toEqual([]);
    expect(diff.added).toEqual([]);
    expect(diff.unchangedCount).toBe(1);
  });

  test('해제 상태는 내용에 들어간다', () => {
    const tx = first('apartment/sale');
    expect(contentHash(withField(tx, 'cancelled', true))).not.toBe(contentHash(tx));
    expect(identityHash(withField(tx, 'cancelled', true))).toBe(identityHash(tx));
  });

  test.each(['jibun', 'contractedOn', 'floor', 'umdNm'] as const)(
    '%s가 다르면 다른 거래다',
    (field) => {
      const tx = first('apartment/sale');
      const other = withField(tx, field, (field === 'floor' ? 99 : 'X') as never);
      expect(identityHash(other)).not.toBe(identityHash(tx));
    },
  );

  test('지번이 없는 유형은 다른 항목으로 키를 만든다', () => {
    // 단독다가구 전월세는 지번·건물명이 없어 일반 키가 성립하지 않는다.
    const tx = first('detached/rent');
    const parts = identityParts(tx);
    expect(parts).toContain(tx.umdNm);
    expect(parts).toContain(String(tx.areaSqm));
    expect(parts).toContain(String(tx.builtYear));
  });

  test('유형이 다르면 다른 거래다', () => {
    const tx = first('apartment/sale');
    expect(identityHash(withField(tx, 'datasetKey', 'officetel/sale'))).not.toBe(identityHash(tx));
  });
});

describe('스냅샷 색인', () => {
  test('픽스처 전 건이 고유 id를 받는다', () => {
    for (const key of ['apartment/sale', 'detached/rent', 'land/sale']) {
      const indexed = indexSnapshot(load(key));
      expect(new Set(indexed.map((i) => i.id)).size, key).toBe(indexed.length);
      expect(indexed.length, key).toBe(load(key).length);
    }
  });

  test('입력 순서가 달라도 같은 결과가 나온다', () => {
    const all = load('apartment/rent');
    const forward = indexSnapshot(all);
    const backward = indexSnapshot([...all].reverse());
    expect(backward.map((i) => i.id)).toEqual(forward.map((i) => i.id));
  });

  test('식별키가 같은 두 건을 병합하지 않고 순번으로 보존한다', () => {
    const tx = first('apartment/sale');
    const twin = withField(tx, 'amount', (tx.amount ?? 0) + 1000);
    const indexed = indexSnapshot([tx, twin]);

    expect(indexed).toHaveLength(2);
    expect(indexed.map((i) => i.occurrence).sort()).toEqual([0, 1]);
    expect(new Set(indexed.map((i) => i.id)).size).toBe(2);
  });

  test('순번은 내용해시 순이라 입력 순서에 흔들리지 않는다', () => {
    const tx = first('apartment/sale');
    const twin = withField(tx, 'amount', (tx.amount ?? 0) + 1000);
    const a = indexSnapshot([tx, twin]);
    const b = indexSnapshot([twin, tx]);
    expect(b).toEqual(a);
  });

  test('완전히 같은 두 건도 각각 보존된다', () => {
    const tx = first('land/sale');
    expect(indexSnapshot([tx, tx])).toHaveLength(2);
  });

  test('빈 스냅샷은 빈 색인이다', () => {
    expect(indexSnapshot([])).toEqual([]);
  });

  test('정렬이 로케일에 의존하지 않는다', () => {
    // 이 정렬이 발생순번 → id → 청크 바이트를 정한다. 로케일에 따라 결과가 달라지면
    // 환경마다 다른 청크가 만들어진다.
    const ids = indexSnapshot(load('apartment/rent')).map((i) => i.id);
    const ordinal = [...ids].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    expect(ids).toEqual(ordinal);
  });
});

describe('스냅샷 비교', () => {
  const base = load('apartment/sale');

  test('변화가 없으면 전부 unchanged다', () => {
    const diff = diffSnapshots(base, base);
    expect(diff.unchangedCount).toBe(base.length);
    expect([diff.added, diff.changed, diff.cancelled, diff.removed]).toEqual([[], [], [], []]);
  });

  test('새 거래는 added다', () => {
    const extra = withField(base[0] as Transaction, 'contractedOn', '2026-08-28');
    const diff = diffSnapshots(base, [...base, extra]);
    expect(diff.added).toHaveLength(1);
    expect(diff.added[0]?.contractedOn).toBe('2026-08-28');
    expect(diff.removed).toEqual([]);
  });

  test('금액 정정은 changed로 잡힌다 — added+removed가 아니다', () => {
    const [head, ...rest] = base;
    const corrected = withField(head as Transaction, 'amount', (head as Transaction).amount! + 5000);
    const diff = diffSnapshots(base, [corrected, ...rest]);

    expect(diff.changed).toHaveLength(1);
    expect(diff.added).toEqual([]);
    expect(diff.removed).toEqual([]);
    expect(diff.changed[0]?.before.amount).toBe((head as Transaction).amount);
    expect(diff.changed[0]?.after.amount).toBe((head as Transaction).amount! + 5000);
  });

  test('해제 전환은 changed이면서 cancelled다', () => {
    const [head, ...rest] = base;
    const cancelled = { ...(head as Transaction), cancelled: true, cancelledOn: '2026-09-01' };
    const diff = diffSnapshots(base, [cancelled, ...rest]);

    expect(diff.cancelled).toHaveLength(1);
    expect(diff.changed).toHaveLength(1);
    // 해제는 삭제가 아니다.
    expect(diff.removed).toEqual([]);
  });

  test('이미 해제된 건이 그대로면 cancelled로 다시 세지 않는다', () => {
    const already = base.map((t) => ({ ...t, cancelled: true }));
    expect(diffSnapshots(already, already).cancelled).toEqual([]);
  });

  test('원천에서 사라진 건은 removed이며 해제와 구분된다', () => {
    const diff = diffSnapshots(base, base.slice(1));
    expect(diff.removed).toHaveLength(1);
    expect(diff.cancelled).toEqual([]);
    expect(diff.changed).toEqual([]);
  });

  test('첫 수집(이전 스냅샷 없음)은 전부 added다', () => {
    const diff = diffSnapshots([], base);
    expect(diff.added).toHaveLength(base.length);
    expect(diff.unchangedCount).toBe(0);
  });

  test('전량 소실은 removed로 드러난다 — R-14 감지 지점', () => {
    const diff = diffSnapshots(base, []);
    expect(diff.removed).toHaveLength(base.length);
    expect(diff.added).toEqual([]);
  });
});
