#!/usr/bin/env bash
# 앱과 저장소에 비밀값이 없는지 확인한다 (G6).
#
#   scripts/check-secrets.sh [APK 경로]
#
# **값을 화면에 내지 않는다.** 있는지 없는지만 말한다 — 확인하겠다고 로그에
# 박아 넣으면 그 로그가 새 유출 경로가 된다.
#
# 저장소 쪽은 `scan-history.sh`가 본다 — HEAD만 보면 지웠다 되살릴 수 있는
# 값을 놓친다. 여기서는 그것을 부르고, APK 안을 마저 본다.
set -uo pipefail

cd "$(dirname "$0")/.."
APK="${1:-app/build/app/outputs/flutter-apk/app-release.apk}"

if [ ! -f .env ]; then
  echo "⚠️  .env가 없습니다. 검사할 값을 읽을 수 없습니다."
  exit 1
fi

get() { grep "^$1=" .env | cut -d= -f2- | tr -d '\r\n"' | xargs; }

# 히스토리와 APK 양쪽에서 **없어야** 하는 값들.
#
# R2_ACCOUNT_ID는 여기 없다. 비밀값이 아니라고 .env.example에 적혀 있고,
# 히스토리 검사에 넣으면 문서에 적힌 그 값이 매번 걸린다.
SERVER_SECRETS=(
  DATA_GO_KR_SERVICE_KEY
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  CALLBACK_SECRET
  CLOUDFLARE_API_TOKEN
  GITHUB_DISPATCH_TOKEN
)

fail=0

echo "== 저장소 (커밋 히스토리 전체) =="
# 값은 **환경으로** 넘긴다. 인자로 주면 프로세스 목록에 그대로 남는다.
# .env를 통째로 source 하지 않는 것은, 그 파일이 셸로 실행되게 두지 않기 위해서다.
env   DATA_GO_KR_SERVICE_KEY="$(get DATA_GO_KR_SERVICE_KEY)"   R2_ACCESS_KEY_ID="$(get R2_ACCESS_KEY_ID)"   R2_SECRET_ACCESS_KEY="$(get R2_SECRET_ACCESS_KEY)"   CALLBACK_SECRET="$(get CALLBACK_SECRET)"   CLOUDFLARE_API_TOKEN="$(get CLOUDFLARE_API_TOKEN)"   GITHUB_DISPATCH_TOKEN="$(get GITHUB_DISPATCH_TOKEN)"   bash scripts/scan-history.sh "${SERVER_SECRETS[@]}" || fail=1

echo
echo "== APK: $APK =="
if [ ! -f "$APK" ]; then
  # **통과로 끝내지 않는다.** 저장소 검사만 하고 0을 돌려주면, 부르는 쪽은
  # 산출물에 대해 아무것도 확인하지 않은 것을 "깨끗하다"로 읽는다.
  echo "  ❌ APK가 없습니다. 산출물을 하나도 검사하지 못했습니다."
  echo "     app/tool/build-release.sh apk 로 먼저 빌드하세요."
  exit 1
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

# 배경지도는 반대로, **없으면** 문제다.
#
# MAP_STYLE을 빠뜨린 빌드는 OSM 폴백으로 그려진다. 화면은 멀쩡해 보이지만
# OSM 이용정책은 배포 앱의 트래픽을 허용하지 않는다 — 그대로 출시하면
# 우리가 남의 서버로 서비스하는 것이 된다. build-release.sh가 먼저 막지만,
# 그 스크립트를 거치지 않고 만든 APK가 여기까지 올 수 있다.
style=$(node -e 'process.stdout.write((JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).MAP_STYLE)||"")' app/dart_defines.json 2>/dev/null || true)
if [ -z "$style" ]; then
  echo "  MAP_STYLE: ❌ app/dart_defines.json에 없습니다 (OSM 폴백으로 나갑니다)"
  fail=1
elif grep -rqF -- "$style" "$work" 2>/dev/null; then
  echo "  MAP_STYLE: ✅ 있음 (우리 배경지도를 가리킨다)"
else
  echo "  MAP_STYLE: ❌ APK에 없습니다. build-release.sh로 다시 빌드하세요"
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "통과 — 서버 비밀값이 앱과 저장소 어디에도 없습니다 (G6)."
else
  echo "실패 — 위 항목을 해결하기 전에 출시하지 마세요. 노출된 값은 즉시 교체하십시오."
fi
exit "$fail"
