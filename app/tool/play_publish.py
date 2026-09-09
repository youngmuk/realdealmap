# -*- coding: utf-8 -*-
"""Google Play 배포 자동화.

배치 파일(publish-internal.bat / promote-production.bat)이 부르는 실제 로직이다.
직접 부를 수도 있다.

    python tool/play_publish.py status
    python tool/play_publish.py bump
    python tool/play_publish.py upload --track internal
    python tool/play_publish.py promote --from internal --to production --fraction 0.1

서비스 계정 키는 환경변수 PLAY_SA_KEY로 덮어쓸 수 있다.
키 파일은 저장소 밖에 두고 절대 커밋하지 않는다.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:  # pragma: no cover - 콘솔이 없는 환경
    pass

PACKAGE_NAME = "com.jsmgames.realdealmap"
DEFAULT_KEY_PATH = r"D:\Work26\_Keys\jsmgames-publisher.json"
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]

APP_ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = APP_ROOT / "pubspec.yaml"
DEFAULT_AAB = APP_ROOT / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"

# version: 1.0.0+1  →  이름과 빌드번호를 따로 잡는다.
# 끝을 \s*$ 로 두면 \s가 개행을 먹어 뒤따르는 빈 줄까지 치환에 휩쓸린다. [ \t]* 로 묶어 둔다.
VERSION_RE = re.compile(
    r"^version:[ \t]*(?P<name>\d+\.\d+\.\d+)\+(?P<code>\d+)[ \t]*$", re.MULTILINE
)


class Fail(Exception):
    """사용자에게 그대로 보여 줄 실패."""


# ---------------------------------------------------------------- pubspec


def read_version():
    text = PUBSPEC.read_text(encoding="utf-8")
    m = VERSION_RE.search(text)
    if not m:
        raise Fail(
            "{0} 에서 'version: x.y.z+n' 줄을 찾지 못했다.\n"
            "형식을 바꿨다면 이 스크립트의 VERSION_RE도 같이 고쳐야 한다.".format(PUBSPEC)
        )
    return m.group("name"), int(m.group("code"))


def bump_build_number():
    """빌드번호만 +1 한다. versionName은 건드리지 않는다."""
    text = PUBSPEC.read_text(encoding="utf-8")
    name, old_code = read_version()
    new_code = old_code + 1
    new_text = VERSION_RE.sub("version: {0}+{1}".format(name, new_code), text, count=1)
    if new_text == text:
        raise Fail("pubspec.yaml 치환에 실패했다. 파일을 확인하라.")
    # newline을 명시하지 않으면 Windows에서 파일 전체가 CRLF로 바뀌어 diff가 통째로 뒤집힌다.
    PUBSPEC.write_text(new_text, encoding="utf-8", newline="\n")
    return name, old_code, new_code


# ---------------------------------------------------------------- API


def service():
    key_path = os.environ.get("PLAY_SA_KEY", DEFAULT_KEY_PATH)
    if not Path(key_path).exists():
        raise Fail(
            "서비스 계정 키를 찾지 못했다: {0}\n"
            "PLAY_SA_KEY 환경변수로 다른 경로를 줄 수 있다.".format(key_path)
        )
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError as exc:
        raise Fail(
            "필요한 패키지가 없다. 아래를 한 번 실행하라.\n"
            "    pip install google-api-python-client google-auth\n"
            "(원인: {0})".format(exc)
        )

    creds = service_account.Credentials.from_service_account_file(key_path, scopes=SCOPES)
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def http_error_text(exc):
    body = ""
    if getattr(exc, "content", None):
        body = exc.content.decode("utf-8", "replace")
    return "{0}\n{1}".format(getattr(exc, "reason", ""), body).strip()


def latest_version_code(track):
    """트랙에서 가장 큰 versionCode와 그 릴리스의 노트를 돌려준다."""
    best_code = None
    best_notes = []
    for release in track.get("releases", []):
        for code in release.get("versionCodes", []) or []:
            code = int(code)
            if best_code is None or code > best_code:
                best_code = code
                best_notes = release.get("releaseNotes", []) or []
    if best_code is None:
        raise Fail("'{0}' 트랙에 올라간 버전이 없다.".format(track.get("track")))
    return best_code, best_notes


def discard_edit(svc, edit_id, quiet=False):
    try:
        svc.edits().delete(packageName=PACKAGE_NAME, editId=edit_id).execute()
        if not quiet:
            print("(변경사항 없이 편집을 취소했다)")
    except Exception:
        pass


# ---------------------------------------------------------------- 명령


def cmd_status(_args):
    from googleapiclient.errors import HttpError

    svc = service()
    name, code = read_version()
    print("로컬 pubspec.yaml : {0}+{1}".format(name, code))
    print("패키지            : {0}".format(PACKAGE_NAME))
    edit_id = None
    try:
        edit_id = svc.edits().insert(packageName=PACKAGE_NAME, body={}).execute()["id"]
        tracks = svc.edits().tracks().list(packageName=PACKAGE_NAME, editId=edit_id).execute()
        print()
        for track in tracks.get("tracks", []):
            releases = track.get("releases", []) or []
            if not releases:
                print("  {0:<12} (비어 있음)".format(track["track"]))
                continue
            for rel in releases:
                codes = ", ".join(str(c) for c in rel.get("versionCodes", []) or [])
                status = rel.get("status", "?")
                frac = rel.get("userFraction")
                frac_text = " · {0:g}%".format(frac * 100) if frac is not None else ""
                print(
                    "  {0:<12} versionCode {1} · {2}{3}".format(
                        track["track"], codes or "-", status, frac_text
                    )
                )
    except HttpError as exc:
        raise Fail("트랙 조회 실패\n{0}".format(http_error_text(exc)))
    finally:
        if edit_id:
            discard_edit(svc, edit_id, quiet=True)
    return 0


def cmd_bump(_args):
    name, old, new = bump_build_number()
    print("버전 올림: {0}+{1} -> {0}+{2}".format(name, old, new))
    return 0


def cmd_upload(args):
    from googleapiclient.errors import HttpError
    from googleapiclient.http import MediaFileUpload

    aab = Path(args.aab) if args.aab else DEFAULT_AAB
    if not aab.exists():
        raise Fail("AAB가 없다: {0}\n먼저 릴리스 빌드를 해야 한다.".format(aab))

    size_mb = aab.stat().st_size / (1024 * 1024)
    name, code = read_version()
    print("올릴 파일 : {0} ({1:.1f} MB)".format(aab, size_mb))
    print("pubspec   : {0}+{1}".format(name, code))
    print("트랙      : {0}".format(args.track))
    print()

    svc = service()
    edit_id = None
    try:
        edit_id = svc.edits().insert(packageName=PACKAGE_NAME, body={}).execute()["id"]
        media = MediaFileUpload(str(aab), mimetype="application/octet-stream", resumable=True)
        print("업로드 중... (파일이 커서 몇 분 걸릴 수 있다)")
        bundle = (
            svc.edits()
            .bundles()
            .upload(packageName=PACKAGE_NAME, editId=edit_id, media_body=media)
            .execute()
        )
        version_code = int(bundle["versionCode"])
        print("업로드 완료 · versionCode {0}".format(version_code))

        notes = args.notes or "{0}+{1} 내부 테스트 빌드".format(name, version_code)
        release = {
            "versionCodes": [version_code],
            "status": "completed",
            "releaseNotes": [{"language": "ko-KR", "text": notes}],
        }

        svc.edits().tracks().update(
            packageName=PACKAGE_NAME,
            editId=edit_id,
            track=args.track,
            body={"track": args.track, "releases": [release]},
        ).execute()

        svc.edits().commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
        edit_id = None
        print()
        print("'{0}' 트랙에 versionCode {1} 게시 완료.".format(args.track, version_code))
        print("Play Console에서 처리에 몇 분 걸린 뒤 테스터에게 보인다.")
    except HttpError as exc:
        raise Fail("업로드 실패\n{0}".format(http_error_text(exc)))
    finally:
        if edit_id:
            discard_edit(svc, edit_id)
    return 0


def cmd_promote(args):
    from googleapiclient.errors import HttpError

    try:
        fraction = float(args.fraction)
    except ValueError:
        raise Fail("--fraction 값이 숫자가 아니다: {0}".format(args.fraction))
    if not 0 < fraction <= 1:
        raise Fail("--fraction은 0 초과 1 이하여야 한다 (받은 값: {0})".format(args.fraction))

    svc = service()
    edit_id = None
    try:
        edit_id = svc.edits().insert(packageName=PACKAGE_NAME, body={}).execute()["id"]
        source = (
            svc.edits()
            .tracks()
            .get(packageName=PACKAGE_NAME, editId=edit_id, track=args.source)
            .execute()
        )
        version_code, notes = latest_version_code(source)

        staged = fraction < 1
        print("원본 트랙  : {0}".format(args.source))
        print("대상 트랙  : {0}".format(args.target))
        print("versionCode: {0}".format(version_code))
        if staged:
            print("출시 범위  : 단계적 출시 {0:g}%".format(fraction * 100))
        else:
            print("출시 범위  : 100% (전체 공개)")
        print()

        if not args.yes:
            print("이 작업은 앱을 실제 사용자에게 공개한다. 되돌리려면 새 버전을 올려야 한다.")
            answer = input("계속하려면 yes 를 입력하라: ").strip().lower()
            if answer != "yes":
                print("취소했다. 아무것도 바뀌지 않았다.")
                return 1

        release = {"versionCodes": [version_code]}
        if staged:
            release["status"] = "inProgress"
            release["userFraction"] = fraction
        else:
            release["status"] = "completed"
        if notes:
            release["releaseNotes"] = notes

        svc.edits().tracks().update(
            packageName=PACKAGE_NAME,
            editId=edit_id,
            track=args.target,
            body={"track": args.target, "releases": [release]},
        ).execute()

        svc.edits().commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
        edit_id = None
        print()
        print("'{0}' 트랙에 versionCode {1} 게시 완료.".format(args.target, version_code))
        if staged:
            print("비율을 올리거나 멈추는 것은 Play Console의 프로덕션 트랙에서 한다.")
        print("Google 검토를 거쳐야 실제로 반영된다.")
    except HttpError as exc:
        raise Fail("승격 실패\n{0}".format(http_error_text(exc)))
    finally:
        if edit_id:
            discard_edit(svc, edit_id)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Google Play 배포 자동화")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="로컬 버전과 각 트랙 상태를 보여 준다").set_defaults(func=cmd_status)
    sub.add_parser("bump", help="pubspec.yaml 빌드번호를 +1 한다").set_defaults(func=cmd_bump)

    up = sub.add_parser("upload", help="AAB를 트랙에 올린다")
    up.add_argument("--track", default="internal")
    up.add_argument("--aab", default=None, help="기본값: {0}".format(DEFAULT_AAB))
    up.add_argument("--notes", default=None, help="ko-KR 릴리스 노트")
    up.set_defaults(func=cmd_upload)

    pr = sub.add_parser("promote", help="트랙 사이로 버전을 승격한다")
    pr.add_argument("--from", dest="source", default="internal")
    pr.add_argument("--to", dest="target", default="production")
    pr.add_argument("--fraction", default="0.1", help="단계적 출시 비율 (1 이면 전체 공개)")
    pr.add_argument("--yes", action="store_true", help="확인 프롬프트를 건너뛴다")
    pr.set_defaults(func=cmd_promote)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except Fail as exc:
        print("\n[실패] {0}".format(exc), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\n중단했다.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
