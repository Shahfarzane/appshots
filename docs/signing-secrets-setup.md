# Signing secrets setup (GitHub Actions)

The release workflow needs three signing secrets that come from your Apple Developer identity and your
Sparkle key. Run these on your Mac; values go straight to GitHub via `gh` (and 1Password via `op`) and
never need to be pasted anywhere.

Repo: `Shahfarzane/appshots`. Developer ID team: **89S32876QM**
(`Developer ID Application: Shahin Farzane (89S32876QM)`).

## ✅ `SPARKLE_PRIVATE_KEY` — already done

A fresh Sparkle EdDSA keypair was generated (the repo shipped with a placeholder public key you didn't
hold the private half of). Current state:
- GitHub secret `SPARKLE_PRIVATE_KEY` is set.
- `project.yml` `SUPublicEDKey` is repinned to `PRq99IaxC621L/e/dUIZLs48SAwBEvYZ2lhoiwrUBl0=`.
- The private key lives in your **login Keychain** (re-exportable any time with `generate_keys -x`).

**Back it up to 1Password** (run in your own terminal so the Touch ID prompt works — losing this key
means you can never sign updates for already-installed clients):

```sh
GK=.build/index-build/artifacts/sparkle/Sparkle/bin/generate_keys
"$GK" -x /tmp/sparkle_private_key.txt
op document create /tmp/sparkle_private_key.txt --title "Appshots Sparkle EdDSA private key"
rm /tmp/sparkle_private_key.txt
```

## `DEVELOPER_ID_KEYCHAIN_GZIP_BASE64` + `KEYCHAIN_PASSWORD`

A self-contained keychain holding your Developer ID Application cert **and** a stored `notarytool`
credentials profile, gzipped + base64-encoded. The workflow discovers the notary profile name by
scanning the keychain, so the name you choose doesn't matter.

Prereqs:
- Export your **Developer ID Application** identity from Keychain Access (login keychain) as a `.p12`:
  right-click the identity → Export → `DeveloperID.p12`, set a password.
- A notarization credential: an **app-specific password** (appleid.apple.com → Sign-In & Security) or an
  **App Store Connect API key** (`.p8` + key id + issuer id).

Store the sensitive inputs in 1Password and read them with `op` so nothing is hardcoded:

```sh
set -euo pipefail
REPO=Shahfarzane/appshots
KCPW="$(openssl rand -base64 24)"
KC="$PWD/build-release.keychain"

security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$KCPW" "$KC"
KC_FILE="$(ls -d "$KC"* | head -n1)"        # handles the macOS .keychain-db suffix

# import the Developer ID identity (p12 password from 1Password)
security import DeveloperID.p12 -k "$KC" \
  -P "$(op read 'op://Private/Appshots DeveloperID p12/password')" \
  -T /usr/bin/codesign -T /usr/bin/productsign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC"

# store notarytool creds into the keychain (app-specific password from 1Password)
xcrun notarytool store-credentials "appshots-notary" \
  --apple-id "$(op read 'op://Private/Apple ID/username')" \
  --team-id 89S32876QM \
  --password "$(op read 'op://Private/Apple Notary/app-specific password')" \
  --keychain "$KC"

# push the two GitHub secrets (values never printed)
gzip -c "$KC_FILE" | base64 | gh secret set DEVELOPER_ID_KEYCHAIN_GZIP_BASE64 --repo "$REPO"
printf '%s' "$KCPW" | gh secret set KEYCHAIN_PASSWORD --repo "$REPO"

# optional: stash the keychain password in 1Password too
printf '%s' "$KCPW" | op item create --category password --title "Appshots release keychain password" password[password]=-

security delete-keychain "$KC"
rm -f DeveloperID.p12
```

(Replace the `op://…` paths with your actual item/field references.)

## Verify

```sh
gh secret list --repo Shahfarzane/appshots
# expect: KEYCHAIN_PASSWORD, DEVELOPER_ID_KEYCHAIN_GZIP_BASE64, SPARKLE_PRIVATE_KEY,
#         CLOUDFLARE_R2_SECRET_ACCESS_KEY
```

Then push a `v*` tag to run the release — the first true end-to-end test of the pipeline.
