#!/usr/bin/env bash
# 앱과 저장소에 비밀값이 없는지 확인한다 (G6).
#
#   scripts/check-secrets.sh [APK 경로]
#
# **값을 화면에 내지 않는다.** 있는지 없는지만 말한다 — 확인하겠다고 로그에
# 박아 넣으면 그 로그가 새 유출 경로가 된다.
#
# VWorld 키는 예외다. 지도 타일 URL에 들어가므로 앱에 있을 수밖에 없고,
# 그래서 있는 것이 정상이다. 없으면 오히려 지도가 안 나온다.
set -uo pipefail

cd "$(dirname "$0")/.."
APK="${1:-app/build/app/outputs/flutter-apk/app-release.apk}"

if [ ! -f .env ]; then
  echo "⚠️  .env가 없습니다. 검사할 값을 읽을 수 없습니다."
  exit 1
fi

get() { grep "^$1=" .env | cut -d= -f2- | tr -d '\r\n"' | xargs; }

SERVER_SECRETS=(
  DATA_GO_KR_SERVICE_KEY
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  R2_ACCOUNT_ID
  KAKAO_REST_API_KEY
  CALLBACK_SECRET
)

fail=0

echo "== 저장소 =="
for name in "${SERVER_SECRETS[@]}"; do
  val=$(get "$name")
  if [ -z "$val" ]; then
    echo "  $name: .env에 없음 (건너뜀)"
    continue
  fi
  # 추적되는 파일만 본다. .env 자체는 추적되지 않는다.
  if git grep -qF -- "$val" HEAD 2>/dev/null; then
    echo "  $name: ❌ 커밋된 파일에서 발견"
    fail=1
  else
    echo "  $name: ✅ 없음"
  fi
done

echo
echo "== APK: $APK =="
if [ ! -f "$APK" ]; then
  echo "  ⚠️  APK가 없습니다. 먼저 빌드하세요."
  echo "     flutter build apk --release --dart-define=..."
  exit "$fail"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -qo "$APK" -d "$work" 2>/dev/null

for name in "${SERVER_SECRETS[@]}"; do
  val=$(get "$name")
  if [ -z "$val" ]; then
    echo "  $name: .env에 없음 (건너뜀)"
    continue
  fi
  if grep -rqF -- "$val" "$work" 2>/dev/null; then
    echo "  $name: ❌ APK에서 발견"
    fail=1
  else
    echo "  $name: ✅ 없음"
  fi
done

# VWorld는 반대로, 없으면 문제다.
vworld=$(get VWORLD_KEY)
if [ -n "$vworld" ]; then
  if grep -rqF -- "$vworld" "$work" 2>/dev/null; then
    echo "  VWORLD_KEY: ✅ 있음 (지도 타일 URL — 설계상 앱에 들어간다)"
  else
    echo "  VWORLD_KEY: ⚠️  APK에 없습니다. --dart-define을 빠뜨리면 지도가 안 나옵니다"
    fail=1
  fi
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "통과 — 서버 비밀값이 앱과 저장소 어디에도 없습니다 (G6)."
else
  echo "실패 — 위 항목을 해결하기 전에 출시하지 마세요. 노출된 값은 즉시 교체하십시오."
fi
exit "$fail"
