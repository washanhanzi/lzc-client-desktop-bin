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

## Normal Commands

```bash
python3 scripts/release_to_aur.py --latest-only
python3 scripts/release_to_aur.py --repo /path/to/lzc-client-desktop-bin
python3 scripts/release_to_aur.py --repo /path/to/lzc-client-desktop-bin --commit --push
```

## Manual Fallback

When the script cannot be used, run the equivalent release steps manually:

1. Read `buildVersion` from the metadata JSON.
2. Update `pkgver` in `PKGBUILD` and reset `pkgrel=1`.
3. Run `updpkgsums`.
4. Run `makepkg --printsrcinfo > .SRCINFO`.
5. Run `makepkg -sf` to test-build the package.
6. Review `git diff`.
7. Commit with `git commit -m "upgpkg: <pkgver>-<pkgrel>"`.
8. Push with `git push origin HEAD`.

For packaging-only fixes without an upstream version bump, leave `pkgver` alone and increment `pkgrel` instead.
