/**
 * `.env` 로더 — 스크립트 4개가 같은 것을 복사해 쓰고 있어 여기로 모았다.
 *
 * 로컬은 `.env`, CI는 환경변수(GitHub Secrets)에서 읽는다. 파일이 없는 것은
 * 정상이므로 조용히 넘어간다 — CI에는 애초에 없다.
 *
 * 자격증명을 다루므로 **어떤 경우에도 값을 출력하지 않는다.**
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');

/**
 * `.env` 한 줄의 값을 푼다.
 *
 * 따옴표로 감싸면 그 안을 값으로 본다. 감싸지 않았을 때만 `#` 이후를 주석으로 버린다 —
 * 인증키에 `#`이 들어갈 수 있어서, 따옴표 안까지 자르면 키가 조용히 잘린다.
 * 잘린 키는 오류가 아니라 인증 실패로 나타나므로 원인을 찾기 어렵다.
 */
export const unquote = (raw) => {
  const v = raw.trim();
  const quoted = /^(["'])([\s\S]*)\1$/.exec(v);
  if (quoted) return quoted[2];
  return v.split('#')[0].trim();
};

/** 이미 있는 환경변수는 덮지 않는다. CI가 준 값이 파일보다 우선한다. */
export const loadEnv = () => {
  let raw;
  try {
    raw = readFileSync(resolve(ROOT, '.env'), 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return;
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (!m || process.env[m[1]] !== undefined) continue;
    process.env[m[1]] = unquote(m[2]);
  }
};

/** 필수 환경변수. 없으면 어디에 넣어야 하는지까지 말해 준다. */
export const requireEnv = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`${name}이(가) 비어 있습니다. .env 또는 GitHub Secrets에 넣으세요.`);
  return value;
};
