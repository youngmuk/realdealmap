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

# 서명. 여기가 비면 Gradle이 **디버그 키로** 서명하고 아무 말도 하지 않는다.
#
# 그렇게 만든 것은 겉보기로 정상 릴리스와 구별되지 않는다. 앱 안의 "출시 불가"
# 경고도 이것은 못 잡는다 — 서명은 앱이 자기 자신에 대해 알 수 있는 값이 아니다.
# Play에 첫 업로드가 그 상태로 들어가면 앱 서명이 **공용 디버그 키에 영구히 묶인다.**
# 되돌릴 수 없는 종류의 실수라서, 스토어용 산출물은 아예 만들지 않는다.
if [ ! -f android/key.properties ]; then
  if [ "$TARGET" = appbundle ]; then
    cat >&2 <<'MSG'
없음: app/android/key.properties — 스토어용 번들을 만들 수 없습니다.

  이것이 없으면 빌드는 성공하지만 **디버그 키로 서명**되고, 그 상태로 Play에
  올리면 앱 서명이 공용 디버그 키에 영구히 묶입니다. 되돌릴 수 없습니다.

  키스토어는 직접 만들어 주세요 (비밀번호를 정하는 일입니다).
  만드는 법과 key.properties 형식: Doc/스토어등록.html

  기기 확인용이라면: tool/build-release.sh apk
MSG
    exit 1
  fi
  echo "※ 서명 키가 없어 디버그 키로 서명합니다 — 스토어에 올릴 수 없는 산출물입니다." >&2
fi

# flutter가 PATH에 없는 기기가 있다. 없다고 여기서 끝내면 무엇이 문제인지
# "command not found" 한 줄로만 남아, 스크립트가 잘못된 것처럼 보인다.
FLUTTER="${FLUTTER:-$(command -v flutter || true)}"
if [ -z "$FLUTTER" ]; then
  for candidate in /c/dev/flutter/bin/flutter "$HOME/flutter/bin/flutter"; do
    [ -x "$candidate" ] && { FLUTTER="$candidate"; break; }
  done
fi
if [ -z "$FLUTTER" ]; then
  echo "flutter를 찾지 못했습니다. FLUTTER=/경로/flutter 로 지정해 주세요." >&2
  exit 1
fi

mkdir -p "$(dirname "$GENERATED")"
umask 077
printf '{ "VWORLD_KEY": "%s" }\n' "$VWORLD_KEY" > "$GENERATED"
trap 'rm -f "$GENERATED"' EXIT

# --obfuscate 는 --split-debug-info 와 짝이다. 심볼은 크래시 해독에만 쓰고
# 저장소에 넣지 않는다 (build/ 아래라 이미 무시된다).
"$FLUTTER" build "$TARGET" --release \
  --dart-define-from-file="$PUBLIC" \
  --dart-define-from-file="$GENERATED" \
  --obfuscate --split-debug-info=build/symbols
