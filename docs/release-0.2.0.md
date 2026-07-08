# Release runbook — v0.2.0 (first public release)

The notarize + DMG + publish pipeline already exists
(`Distribution/Scripts/release.sh`, driven in CI by
`.github/workflows/macos-release-production.yml`). This runbook records the
one-time steps to cut the **first public** release.

## Preconditions (verified 2026-07-08)

- Working tree clean, `main` synced.
- `LICENSE` + `README.md` present.
- Entitlements are notarization-safe (hardened-process only, no
  `get-task-allow`): `Appshots.entitlements`, `appshotsctl.entitlements`.
- No secrets in git history or the working tree (scanned: no `.p12/.p8/.keychain`,
  no PEM/private-key/token markers; `docs/signing-secrets-setup.md` is
  placeholders only).
- GitHub Actions secrets set on `Shahfarzane/appshots`:
  `KEYCHAIN_PASSWORD`, `DEVELOPER_ID_KEYCHAIN_GZIP_BASE64` (Developer ID
  identity + `AppshotsNotary` notary profile), `SPARKLE_PRIVATE_KEY`.
- Version: `MARKETING_VERSION = 0.2.0`. CI's `increment_build` reads the
  published appcast (404 on first release → 0) and ships the next build number.

## Phases

1. **Go public.** `gh repo edit Shahfarzane/appshots --visibility public`
   (GitHub Releases is the download + appcast backend, so users can't fetch a
   release or updates while the repo is private). Irreversible in practice —
   explicit confirmation required before running.
2. **Tag & build.** `git tag v0.2.0 && git push origin v0.2.0` → triggers the
   `macos-release-production` workflow: archive → hardened-runtime sign →
   styled DMG → notarize + staple → GitHub Release with `Appshots.dmg`,
   `appcast.xml`, and `appshotsctl-<version>-arm64.zip`.
3. **Verify.** Release assets present; `xcrun stapler validate` on the
   downloaded DMG; `spctl -a -t open --context context:primary-signature` /
   Gatekeeper accepts; appcast `sparkle:version` matches the shipped build.
4. **Homebrew.** Fill `Distribution/Homebrew/appshotsctl.rb` `sha256` + `url`
   + `version` from the published CLI zip
   (`shasum -a 256 appshotsctl-<version>-arm64.zip`).

## Rollback

- A bad release: `gh release delete v0.2.0` and `git push --delete origin
  v0.2.0`, fix, re-tag.
- Repo visibility can be flipped back to private, but anything already cloned
  or cached by others is out. Treat "go public" as one-way.

## Known caveat

`release.sh` staples the DMG and the archived `.app`, but builds the DMG from
the pre-staple app, so the `.app` *inside* the shipped DMG carries no stapled
ticket (Gatekeeper still validates the notarization online on first launch).
Fix if desired: staple the app before `create_dmg`.
