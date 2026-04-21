# Release Workflow

## Upstream Inputs

- Install script: `https://dl.lazycat.cloud/client/desktop/linux-install`
- Metadata JSON: `https://dl.lazycat.cloud/client/desktop/lzc-client-desktop.tar.zst.metadata.json`
- Tarball pattern: `https://dl.lazycat.cloud/client/desktop/stable/lzc-client-desktop_v${pkgver}.tar.zst`

`buildVersion` in the metadata JSON is canonical. Strip the leading `v` before writing `pkgver`.

## Expected Repo State

- The repo should contain `PKGBUILD`, `.SRCINFO`, and the existing `image.png`.
- The tracked worktree should be clean before committing or pushing.
- The AUR remote should usually be `ssh://aur@aur.archlinux.org/lzc-client-desktop-bin.git`.
- Publish from the persistent clean AUR worktree at `/home/frank/github/lzc-client-desktop-bin-aur`, branch `aur`, tracking AUR `origin/master`.
- Keep skills, scripts, docs, and other GitHub-only files in `/home/frank/github/lzc-client-desktop-bin` on branch `main`. Do not push that branch history to AUR.

## Persistent Worktree Setup

From the main GitHub checkout, create the clean AUR branch and worktree when missing:

```bash
git fetch origin master
git branch --track aur origin/master
git worktree add ../lzc-client-desktop-bin-aur aur
```

Check the setup:

```bash
git branch -vv
git -C ../lzc-client-desktop-bin-aur status --short --branch
```

## Normal Commands

```bash
python3 skills/lzc-client-desktop-aur/scripts/release_to_aur.py --latest-only
python3 skills/lzc-client-desktop-aur/scripts/release_to_aur.py --repo ../lzc-client-desktop-bin-aur
git -C ../lzc-client-desktop-bin-aur diff
python3 skills/lzc-client-desktop-aur/scripts/release_to_aur.py --repo ../lzc-client-desktop-bin-aur --commit --push
```

The scripted push validates that `origin` is the AUR remote, checks that the outgoing history does not contain subdirectory paths, and pushes `HEAD:master`.

## Manual Fallback

When the script cannot be used, run the equivalent release steps manually:

1. Read `buildVersion` from the metadata JSON.
2. Update `pkgver` in `PKGBUILD` and reset `pkgrel=1`.
3. Run `updpkgsums`.
4. Run `makepkg --printsrcinfo > .SRCINFO`.
5. Run `makepkg -sf` to test-build the package.
6. Review `git diff`.
7. Commit with `git commit -m "upgpkg: <pkgver>-<pkgrel>"`.
8. Push with `git push origin HEAD:master`.

For packaging-only fixes without an upstream version bump, leave `pkgver` alone and increment `pkgrel` instead.
