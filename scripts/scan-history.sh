#!/usr/bin/env bash
# 비밀값이 **커밋된 적이 있는지** 본다 (G6).
#
#   scripts/scan-history.sh
#
# 값은 환경변수에서 읽는다 — 로컬은 `.env`, CI는 GitHub Secrets. 인자로 받지
# 않는 이유는 argv가 셸 히스토리와 프로세스 목록에 남기 때문이다.
#
# **왜 HEAD로는 모자란가.** 이 저장소는 public이다. 실수로 커밋한 값을 다음
# 커밋에서 지워도 앞 커밋은 그대로 남아 누구나 꺼내 볼 수 있다. HEAD만 보면
# 그 상태가 "✅ 없음"으로 나온다 — 가장 위험한 순간에 통과 도장을 찍는 셈이다.
# `git log -S`(pickaxe)는 값이 나타났다 사라진 커밋까지 짚는다.
#
# **값을 출력하지 않는다.** 있는지 없는지와 커밋 해시만 말한다. 확인하겠다고
# 값을 로그에 찍으면 그 로그가 새 유출 경로가 된다.
set -uo pipefail

cd "$(dirname "$0")/.."

# 이름만 적는다. 값은 환경에서 온다.
#
# R2_ACCOUNT_ID와 R2_BUCKET은 넣지 않는다. 비밀값이 아니고(.env.example에
# 그렇게 적혀 있다) 버킷 이름은 문서와 스크립트에 그대로 나와서, 넣으면
# 매번 걸린다. 매번 걸리는 검사는 곧 아무도 안 읽는다.
NAMES=(
  DATA_GO_KR_SERVICE_KEY
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  CALLBACK_SECRET
  CLOUDFLARE_API_TOKEN
  GITHUB_DISPATCH_TOKEN
)

# 값이 짧으면 우연히 맞는다. 이보다 짧은 것은 비밀값이 아니라 자리표시자로 본다.
MIN_LENGTH=16

checked=0
fail=0

for name in "${NAMES[@]}"; do
  val="${!name:-}"
  if [ -z "$val" ]; then
    echo "  $name: 값이 없음 (건너뜀)"
    continue
  fi
  if [ "${#val}" -lt "$MIN_LENGTH" ]; then
    echo "  $name: ⚠️  ${MIN_LENGTH}자보다 짧습니다. 자리표시자입니까?"
    continue
  fi
  checked=$((checked + 1))

  # `--all`이라야 main 말고 다른 가지에 남은 것도 본다.
  hits=$(git log --all --format=%H -S"$val" -- 2>/dev/null | head -5)
  if [ -n "$hits" ]; then
    echo "  $name: ❌ 커밋 히스토리에서 발견"
    echo "$hits" | sed 's/^/      /'
    fail=1
  else
    echo "  $name: ✅ 없음"
  fi
done

echo
if [ "$checked" -eq 0 ]; then
  # 조용히 통과시키지 않는다. 아무것도 검사하지 못한 것과 깨끗한 것은 다르다.
  echo "실패 — 검사할 값이 하나도 없습니다. 환경변수(.env / GitHub Secrets)를 확인하세요."
  exit 1
fi

if [ "$fail" -eq 0 ]; then
  echo "통과 — $checked개 값이 커밋 히스토리 어디에도 없습니다."
  exit 0
fi

cat <<'MSG'
실패 — 위 값은 이미 공개된 것으로 보아야 합니다.

  1) 먼저 값을 **교체**하세요. 히스토리를 고쳐 써도 이미 복제된 것은 되돌릴 수 없습니다.
  2) 그다음 GitHub Secrets와 .env를 새 값으로 바꾸세요.
MSG
exit 1
