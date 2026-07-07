# Release signing secrets (GitHub Actions)

Maintainer / fork setup for the `v*` tag release workflow
(`.github/workflows/macos-release-production.yml`). The workflow signs and
notarizes with material restored from GitHub Actions secrets; none of these
exist on a fresh fork (and they must be re-created if the repo is ever
recreated), so the release pipeline fails at "Restore signing material" until
they are set.

Required secrets:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_KEYCHAIN_GZIP_BASE64` | A self-contained keychain (gzip + base64) holding the Developer ID Application identity and a stored `notarytool` credentials profile |
| `KEYCHAIN_PASSWORD` | The password of that keychain |
| `SPARKLE_PRIVATE_KEY` | The Sparkle EdDSA private key used to sign the appcast |

## Sparkle EdDSA key

Generate a keypair with Sparkle's `generate_keys` (ships with the Sparkle
distribution; a SwiftPM checkout builds it under
`.build/**/artifacts/**/Sparkle/bin/generate_keys`). Then:

- Set the private key as the `SPARKLE_PRIVATE_KEY` secret and back it up
  somewhere durable (a password manager). Losing it means already-installed
  clients can never verify another update.
- Pin the matching public key as `SUPublicEDKey` in `project.yml`. The key
  currently pinned there is the one release builds must match.

## Developer ID keychain

Build a throwaway keychain containing the Developer ID Application identity
plus a `notarytool` profile, then upload it. The workflow discovers the notary
profile name by scanning the keychain, so the profile name is free-form.

Prereqs: your **Developer ID Application** identity exported as a `.p12`, and
a notarization credential (an App Store Connect API key `.p8` + key id +
issuer id, or an Apple ID app-specific password). Notarization requires the
Apple Developer Program license agreement for the team to be current, or
Apple returns HTTP 403.

```sh
set -euo pipefail
REPO=<owner>/<repo>
KCPW="$(openssl rand -base64 24)"
KC="$PWD/build-release.keychain"

security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$KCPW" "$KC"
KC_FILE="$(ls -d "$KC"* | head -n1)"        # handles the macOS .keychain-db suffix

# Import the Developer ID identity. Read the p12 password from your password
# manager rather than typing it into the shell.
security import DeveloperID.p12 -k "$KC" \
  -P "<p12-export-password>" \
  -T /usr/bin/codesign -T /usr/bin/productsign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC"

# Store notarytool credentials into the same keychain (API-key form shown).
xcrun notarytool store-credentials "release-notary" \
  --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-UUID> \
  --keychain "$KC"

# Push the two GitHub secrets (values never printed).
gzip -c "$KC_FILE" | base64 | gh secret set DEVELOPER_ID_KEYCHAIN_GZIP_BASE64 --repo "$REPO"
printf '%s' "$KCPW" | gh secret set KEYCHAIN_PASSWORD --repo "$REPO"

security delete-keychain "$KC"
rm -f DeveloperID.p12
```

## Verify

```sh
gh secret list --repo <owner>/<repo>
# expect: KEYCHAIN_PASSWORD, DEVELOPER_ID_KEYCHAIN_GZIP_BASE64, SPARKLE_PRIVATE_KEY
```

Then push a `v*` tag to run the release pipeline end to end.
