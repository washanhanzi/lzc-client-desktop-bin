---
name: lzc-client-desktop-aur
description: Check the latest LazyCat desktop client release, update the `lzc-client-desktop-bin` AUR package, regenerate checksums and `.SRCINFO`, build/test the package, and publish it to AUR. Use when Codex is working in the `lzc-client-desktop-bin` packaging repo or another clone of the same AUR package.
---

# Lzc Client Desktop Aur

Use `scripts/release_to_aur.py` for the normal release flow. It reads the canonical upstream metadata endpoint used by the LazyCat Linux install script, converts `buildVersion` into the Arch `pkgver`, updates packaging files, rebuilds the package, and can commit and push the release.

## Workflow

1. Work in a clean clone of `lzc-client-desktop-bin`.
2. Run `python3 scripts/release_to_aur.py --latest-only` to inspect the upstream version without changing the repo.
3. Run `python3 scripts/release_to_aur.py --repo /path/to/lzc-client-desktop-bin` to update `PKGBUILD`, refresh checksums, regenerate `.SRCINFO`, and test-build the package.
4. Review `git diff` and the built package path reported by the script.
5. Run `python3 scripts/release_to_aur.py --repo /path/to/lzc-client-desktop-bin --commit --push` only after the update build passes and the repo is clean apart from the expected packaging files.

## Rules

- Treat `https://dl.lazycat.cloud/client/desktop/lzc-client-desktop.tar.zst.metadata.json` as the canonical version source.
- Keep `pkgver` without the leading `v`; the `PKGBUILD` source URL already adds it back as `lzc-client-desktop_v${pkgver}.tar.zst`.
- Reset `pkgrel` to `1` when `pkgver` changes upstream.
- Regenerate `.SRCINFO` from `makepkg --printsrcinfo`; never hand-edit it.
- Stop when the repo has unrelated tracked changes unless the user explicitly wants a mixed release.
- Use [release-workflow.md](references/release-workflow.md) when the scripted path is blocked or a manual release is required.
