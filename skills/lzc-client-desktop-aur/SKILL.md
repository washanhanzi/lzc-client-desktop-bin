---
name: lzc-client-desktop-aur
description: Check the latest LazyCat desktop client release, update the `lzc-client-desktop-bin` AUR package, regenerate checksums and `.SRCINFO`, build/test the package, and publish it to AUR. Use when Codex is working in the `lzc-client-desktop-bin` packaging repo or another clone of the same AUR package.
---

# Lzc Client Desktop Aur

Use `skills/lzc-client-desktop-aur/scripts/release_to_aur.py` for the normal release flow from the main checkout. It reads the canonical upstream metadata endpoint used by the LazyCat Linux install script, converts `buildVersion` into the Arch `pkgver`, updates packaging files, rebuilds the package, and can commit and push the release.

This repository uses two working areas:

- Main GitHub checkout: `/home/frank/github/lzc-client-desktop-bin`, branch `main`, for skills, scripts, and docs.
- Clean AUR worktree: `/home/frank/github/lzc-client-desktop-bin-aur`, branch `aur`, tracking AUR `origin/master`.

Always update and publish the package from the clean AUR worktree. AUR rejects pushed history that contains subdirectories such as `skills/`.

## Workflow

1. Work from the main GitHub checkout so the release script is available.
2. Run `python3 skills/lzc-client-desktop-aur/scripts/release_to_aur.py --latest-only` to inspect the upstream version without changing the repo.
3. Run `python3 skills/lzc-client-desktop-aur/scripts/release_to_aur.py --repo ../lzc-client-desktop-bin-aur` to update `PKGBUILD`, refresh checksums, regenerate `.SRCINFO`, and test-build the package in the clean AUR worktree.
4. Review `git -C ../lzc-client-desktop-bin-aur diff` and the built package path reported by the script.
5. Run `python3 skills/lzc-client-desktop-aur/scripts/release_to_aur.py --repo ../lzc-client-desktop-bin-aur --commit --push` only after the update build passes and the clean AUR worktree is clean apart from the expected packaging files.

## Worktree Setup

If the clean AUR worktree is missing, recreate it from the main checkout:

```bash
git fetch origin master
git branch --track aur origin/master
git worktree add ../lzc-client-desktop-bin-aur aur
```

## Rules

- Treat `https://dl.lazycat.cloud/client/desktop/lzc-client-desktop.tar.zst.metadata.json` as the canonical version source.
- Keep `pkgver` without the leading `v`; the `PKGBUILD` source URL already adds it back as `lzc-client-desktop_v${pkgver}.tar.zst`.
- Reset `pkgrel` to `1` when `pkgver` changes upstream.
- Regenerate `.SRCINFO` from `makepkg --printsrcinfo`; never hand-edit it.
- Push AUR releases as `HEAD:master`; the local clean branch is named `aur`, but AUR only accepts the remote `master` branch.
- Stop when the repo has unrelated tracked changes unless the user explicitly wants a mixed release.
- Use [release-workflow.md](references/release-workflow.md) when the scripted path is blocked or a manual release is required.
