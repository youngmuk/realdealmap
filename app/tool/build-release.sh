#!/usr/bin/env bash
# 출시 빌드. **이 스크립트를 거치지 않은 릴리스 산출물은 올리지 않는다.**
#
# 왜 스크립트가 필요한가: `flutter build`에 --dart-define을 빠뜨려도 빌드는 성공하고
# 앱도 실행된다. 지도는 OSM 폴백으로 그려지고 데이터만 조용히 비어서, 화면만 봐서는
# "아직 안 받았나 보다"와 구별되지 않는다. 실제로 그렇게 만든 APK를 손에 쥐고도
# 지역 목록을 열어 보고서야 알았다. 여기서 그 조용함을 없앤다.
#
# 값은 인자로 받지 않는다 — argv에 두면 셸 히스토리와 프로세스 목록에 그대로 남는다.
# VWorld 키는 이미 저장소 밖 .env 에 있다. 키를 두는 자리를 하나 더 만들면
# 두 곳이 어긋날 때 어느 쪽이 진짜인지 알 수 없게 된다.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=../.env
PUBLIC=dart_defines.json
GENERATED=build/dart_defines.key.json   # build/ 는 두 VCS 모두 무시한다

[ -f "$PUBLIC" ] || { echo "없음: app/$PUBLIC" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "없음: $ENV_FILE (.env.example 참고)" >&2; exit 1; }

VWORLD_KEY=$(sed -n 's/^VWORLD_KEY=//p' "$ENV_FILE" | head -1 | tr -d '\r"')
if [ -z "$VWORLD_KEY" ]; then
  cat >&2 <<'MSG'
.env 에 VWORLD_KEY 가 비어 있습니다.

  이 키는 타일 URL에 실려 나가므로 앱 안에 들어갈 수밖에 없다 (설계대로다).
  없이 빌드하면 OSM 폴백으로 떨어지는데, OSM 이용정책은 앱 트래픽을 허용하지
  않는다 — 기능은 멀쩡해 보이므로 그대로 출시될 수 있다.
MSG
  exit 1
fi

TARGET="${1:-appbundle}"   # appbundle (스토어) 또는 apk
case "$TARGET" in
  appbundle|apk) ;;
  *) echo "쓰임: $0 [appbundle|apk]" >&2; exit 1 ;;
esac

mkdir -p "$(dirname "$GENERATED")"
umask 077
printf '{ "VWORLD_KEY": "%s" }\n' "$VWORLD_KEY" > "$GENERATED"
trap 'rm -f "$GENERATED"' EXIT

# --obfuscate 는 --split-debug-info 와 짝이다. 심볼은 크래시 해독에만 쓰고
# 저장소에 넣지 않는다 (build/ 아래라 이미 무시된다).
flutter build "$TARGET" --release \
  --dart-define-from-file="$PUBLIC" \
  --dart-define-from-file="$GENERATED" \
  --obfuscate --split-debug-info=build/symbols
