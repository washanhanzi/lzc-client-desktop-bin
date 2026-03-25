#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

METADATA_URL = "https://dl.lazycat.cloud/client/desktop/lzc-client-desktop.tar.zst.metadata.json"
INSTALL_SCRIPT_URL = "https://dl.lazycat.cloud/client/desktop/linux-install"
TARBALL_URL_TEMPLATE = "https://dl.lazycat.cloud/client/desktop/stable/lzc-client-desktop_v{version}.tar.zst"
AUR_REMOTE_SUFFIX = "aur.archlinux.org/lzc-client-desktop-bin.git"


def run(cmd: list[str], *, cwd: Path | None = None, capture: bool = False) -> str:
    print(f"+ {shlex.join(cmd)}")
    completed = subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )
    return completed.stdout.rstrip("\n") if capture and completed.stdout else ""


def fetch_text(url: str, *, method: str = "GET") -> str:
    request = Request(url, method=method, headers={"User-Agent": "codex-lzc-client-desktop-aur"})
    with urlopen(request) as response:
        return response.read().decode("utf-8")


def fetch_latest_release() -> tuple[str, dict]:
    payload = json.loads(fetch_text(METADATA_URL))
    raw_version = str(payload.get("buildVersion", "")).strip()
    if not raw_version:
        raise RuntimeError(f"Missing buildVersion in {METADATA_URL}")

    version = raw_version[1:] if raw_version.startswith("v") else raw_version
    if not re.fullmatch(r"\d+(?:\.\d+)+", version):
        raise RuntimeError(f"Unexpected buildVersion value: {raw_version}")

    return version, payload


def verify_tarball(version: str) -> None:
    tarball_url = TARBALL_URL_TEMPLATE.format(version=version)
    try:
        fetch_text(tarball_url, method="HEAD")
    except HTTPError as exc:
        raise RuntimeError(f"Tarball probe failed for {tarball_url}: HTTP {exc.code}") from exc
    except URLError as exc:
        raise RuntimeError(f"Tarball probe failed for {tarball_url}: {exc.reason}") from exc


def repo_path_arg(value: str) -> Path:
    return Path(value).expanduser().resolve()


def ensure_repo(repo: Path) -> None:
    required = ("PKGBUILD", ".SRCINFO", ".git")
    missing = [name for name in required if not (repo / name).exists()]
    if missing:
        joined = ", ".join(missing)
        raise RuntimeError(f"{repo} is not a lzc-client-desktop-bin repo; missing: {joined}")


def tracked_changes(repo: Path) -> list[str]:
    status = run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=repo, capture=True)
    if not status:
        return []

    paths = []
    for line in status.splitlines():
        if not line:
            continue
        if len(line) < 4:
            raise RuntimeError(f"Unexpected git status output: {line}")
        paths.append(line[3:])

    return paths


def ensure_release_state(repo: Path, current_version: str, target_version: str) -> None:
    dirty_paths = tracked_changes(repo)
    if not dirty_paths:
        return

    allowed = {"PKGBUILD", ".SRCINFO"}
    unexpected = [path for path in dirty_paths if path not in allowed]
    if unexpected:
        joined = ", ".join(unexpected)
        raise RuntimeError(f"Tracked worktree has unrelated changes: {joined}")

    if current_version != target_version:
        raise RuntimeError(
            "PKGBUILD/.SRCINFO are already modified before the requested version bump completed; "
            "review the repo manually before releasing."
        )


def read_pkgbuild(repo: Path) -> tuple[Path, str, str, str]:
    path = repo / "PKGBUILD"
    text = path.read_text(encoding="utf-8")

    pkgver_match = re.search(r"^pkgver=(.+)$", text, re.MULTILINE)
    pkgrel_match = re.search(r"^pkgrel=(.+)$", text, re.MULTILINE)
    if not pkgver_match or not pkgrel_match:
        raise RuntimeError("Unable to locate pkgver/pkgrel in PKGBUILD")

    return path, text, pkgver_match.group(1).strip(), pkgrel_match.group(1).strip()


def replace_once(pattern: str, replacement: str, text: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"Unable to update pattern: {pattern}")
    return updated


def update_pkgbuild(path: Path, text: str, version: str) -> None:
    updated = replace_once(r"^pkgver=.*$", f"pkgver={version}", text)
    updated = replace_once(r"^pkgrel=.*$", "pkgrel=1", updated)
    path.write_text(updated, encoding="utf-8")


def regenerate_packaging_files(repo: Path) -> None:
    run(["updpkgsums"], cwd=repo)
    srcinfo = run(["makepkg", "--printsrcinfo"], cwd=repo, capture=True)
    (repo / ".SRCINFO").write_text(f"{srcinfo}\n", encoding="utf-8")


def build_package(repo: Path) -> list[str]:
    run(["makepkg", "-sf"], cwd=repo)
    paths = run(["makepkg", "--packagelist"], cwd=repo, capture=True)
    packages = [line for line in paths.splitlines() if line]
    if not packages:
        raise RuntimeError("makepkg --packagelist returned no package paths")
    return packages


def ensure_aur_remote(repo: Path) -> None:
    remote_url = run(["git", "remote", "get-url", "origin"], cwd=repo, capture=True)
    if AUR_REMOTE_SUFFIX not in remote_url:
        raise RuntimeError(f"origin does not look like the AUR remote: {remote_url}")


def maybe_commit(repo: Path, version: str, pkgrel: str) -> None:
    diff = run(["git", "status", "--short", "--", "PKGBUILD", ".SRCINFO"], cwd=repo, capture=True)
    if not diff:
        print("No PKGBUILD or .SRCINFO changes to commit.")
        return

    run(["git", "add", "PKGBUILD", ".SRCINFO"], cwd=repo)
    run(["git", "commit", "-m", f"upgpkg: {version}-{pkgrel}"], cwd=repo)


def push_release(repo: Path) -> None:
    ensure_aur_remote(repo)
    run(["git", "push", "origin", "HEAD"], cwd=repo)


def print_summary(current_version: str, target_version: str, payload: dict) -> None:
    print(f"Current PKGBUILD version: {current_version}")
    print(f"Latest upstream version:  {target_version}")
    english = next(
        (
            item.get("changelog", "").strip()
            for item in payload.get("changelogs", [])
            if item.get("language") == "en"
        ),
        "",
    )
    if english:
        print(f"Upstream changelog:      {english}")
    print(f"Metadata URL:            {METADATA_URL}")
    print(f"Install script URL:      {INSTALL_SCRIPT_URL}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Update and release the lzc-client-desktop-bin AUR package."
    )
    parser.add_argument("--repo", type=repo_path_arg, default=Path.cwd(), help="Path to the AUR repo.")
    parser.add_argument("--version", help="Override the upstream version instead of querying metadata.")
    parser.add_argument("--latest-only", action="store_true", help="Print the latest upstream version and exit.")
    parser.add_argument("--skip-build", action="store_true", help="Update packaging files without running makepkg.")
    parser.add_argument("--commit", action="store_true", help="Create an AUR release commit after validation.")
    parser.add_argument("--push", action="store_true", help="Push the release commit to origin after validation.")
    args = parser.parse_args()

    if args.push:
        args.commit = True

    try:
        latest_version, payload = fetch_latest_release()
        if args.latest_only:
            print(latest_version)
            return 0

        target_version = args.version or latest_version
        verify_tarball(target_version)

        ensure_repo(args.repo)
        pkgbuild_path, pkgbuild_text, current_version, current_pkgrel = read_pkgbuild(args.repo)
        ensure_release_state(args.repo, current_version, target_version)
        print_summary(current_version, target_version, payload)

        changed = target_version != current_version
        if changed:
            update_pkgbuild(pkgbuild_path, pkgbuild_text, target_version)
            regenerate_packaging_files(args.repo)
            current_pkgrel = "1"
        else:
            print("PKGBUILD already matches the requested upstream version.")

        if not args.skip_build:
            packages = build_package(args.repo)
            print("Built package(s):")
            for package in packages:
                print(f"  {package}")

        if args.commit:
            maybe_commit(args.repo, target_version, current_pkgrel)

        if args.push:
            push_release(args.repo)
    except (RuntimeError, subprocess.CalledProcessError, HTTPError, URLError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
