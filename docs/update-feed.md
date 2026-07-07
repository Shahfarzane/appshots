# Update feed (GitHub Releases)

Sparkle updates and all release artifacts are served from **GitHub Releases** —
no separate hosting.

## How it fits together

- Pushing a `v*` tag runs `.github/workflows/macos-release-production.yml`:
  `release.sh build` (archive → sign → notarize → staple → DMG + standalone CLI
  zip), then the workflow creates the GitHub Release with `Appshots.dmg` and
  `appshotsctl-<version>-arm64.zip` attached, then `release.sh upload` generates
  the Sparkle appcast and attaches it plus the immutable, versioned DMG
  (`<version>-<ts>-<sha>.dmg`) to the same release.
- The app's `SUFeedURL` is the stable alias
  `https://github.com/Shahfarzane/appshots/releases/latest/download/appcast.xml`
  — GitHub redirects it to the newest release's appcast, so the URL baked into
  shipped builds never changes. Sparkle follows the redirect and verifies the
  appcast with the pinned `SUPublicEDKey` (project.yml).
- Appcast enclosure URLs point at that release's immutable versioned DMG under
  `releases/download/v<version>/…`.
- The Homebrew formula (`Distribution/Homebrew/appshotsctl.rb`) pins the
  versioned CLI zip URL on the same release.
- `release.sh` reads the live latest appcast to advance the build number, so
  release numbering is stateful in GitHub itself.

## Requirements

- The repo must be **public** (Sparkle can't authenticate to private release
  assets).
- CI needs `GH_TOKEN` (the workflow passes `github.token`; `contents: write`).
- Signing/notarization/Sparkle secrets: see
  [signing-secrets-setup.md](signing-secrets-setup.md).

## Verification (after a release runs)

```sh
curl -ILs https://github.com/Shahfarzane/appshots/releases/latest/download/appcast.xml | head -1
curl -Ls  https://github.com/Shahfarzane/appshots/releases/latest/download/appcast.xml | head
```

Before the first release the alias 404s — expected; the pipeline treats it as
"latest build = 0 → 1".

## History

Earlier iterations planned a Cloudflare R2 bucket behind a branded domain.
That was abandoned before anything shipped: the zone's certificate
provisioning was unreliable, and for a public repo GitHub Releases is simpler,
free, and gives users a browsable download page. No published install ever
pointed at the old hosts, so there is nothing to migrate.
