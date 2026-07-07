# Cloudflare setup for Appshots releases

Maintainer infrastructure notes: what the release pipeline
(`DevKit/Scripts/release.sh` + `.github/workflows/macos-release-production.yml`)
expects from Cloudflare. `persist.nerd.ceo` is this project's feed host;
substitute your own domain on a fork.

> **Known caveat:** on this account the custom-domain TLS certificate for the
> feed host initially failed to bind at the Cloudflare edge, and the feed was
> temporarily served from the bucket's public `pub-*.r2.dev` URL instead.
> Before the next release, verify the custom domain actually serves
> (`curl -I https://persist.nerd.ceo/appshots/appcast.xml`); if it does not,
> set the `CLOUDFLARE_R2_PUBLIC_BASE_URL` repo variable to the `pub-*.r2.dev`
> base URL, which the pipeline honors everywhere.

## Goal

Host the Sparkle auto-update feed + DMGs on Cloudflare R2, served publicly at
`https://persist.nerd.ceo/…`, and give GitHub Actions S3 credentials so the release workflow can
upload to it.

## Prerequisite

The domain **`nerd.ceo` must already be an active zone in this Cloudflare account** (DNS managed by
Cloudflare). `persist.nerd.ceo` is a subdomain of it.

## Tasks on Cloudflare

1. **Create an R2 bucket** (or reuse an existing one).
   - R2 → Create bucket, e.g. `appshots-releases`. **Record the exact bucket name.**
   - **Record the Account ID** (R2 overview / dashboard URL — 32-char hex).

2. **Connect the public custom domain.**
   - Bucket → Settings → Public access → **Connect Domain** → `persist.nerd.ceo`.
   - Cloudflare auto-creates a proxied CNAME (`persist` → R2) in the `nerd.ceo` zone and issues TLS.
   - Result: `https://persist.nerd.ceo/<object-key>` serves bucket objects publicly. Do **not** use the
     `*.r2.dev` dev URL for production.

3. **Create R2 S3 credentials.**
   - R2 → **Manage R2 API Tokens** → Create API token.
   - Permission **Object Read & Write**, scoped to the bucket (or all buckets).
   - Yields an **Access Key ID** + **Secret Access Key** (shown once). **Record both.**
   - The pipeline derives the endpoint `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, region `auto`.

4. **Add a Cache Rule for the mutable objects** (important for Sparkle).
   - These change every release and must not be served stale:
     `/appshots/appcast.xml`, `/appshots/latest.txt`, `/appshots/latest-appshots-arm64.dmg`,
     `/appshots/appshotsctl-latest-arm64.zip`.
   - Cloudflare **Cache Rule**: when the URI path matches those, set **Edge TTL ≈ 60s** (or Bypass).
     The versioned `*.dmg` objects are immutable and can cache long.

## Object / URL contract (do not change these paths)

The pipeline writes, and the app reads, under the `appshots/` prefix by default
(`RELEASE_ENVIRONMENT=appshots`):

| Object key | Public URL | Purpose |
|---|---|---|
| `appshots/appcast.xml` | `https://persist.nerd.ceo/appshots/appcast.xml` | Sparkle feed (`SUFeedURL`); also read to compute the next build number |
| `appshots/latest-appshots-arm64.dmg` | .../appshots/latest-appshots-arm64.dmg | stable "latest" download |
| `appshots/<version>-<ts>-<sha>.dmg` | .../appshots/<...>.dmg | the immutable release DMG |
| `appshots/latest.txt` | .../appshots/latest.txt | pointer file |
| `appshots/appshotsctl-<version>-arm64.zip` | .../appshots/appshotsctl-<version>-arm64.zip | standalone CLI zip |
| `appshots/appshotsctl-latest-arm64.zip` | .../appshots/appshotsctl-latest-arm64.zip | stable standalone CLI pointer |

## Values to set on the GitHub repo (`Shahfarzane/appshots`)

Settings → Secrets and variables → Actions. **Mind the variable-vs-secret split** — the workflow
reads them exactly as shown:

| GitHub name | Kind | Value |
|---|---|---|
| `CLOUDFLARE_R2_ACCOUNT_ID` | Variable | account ID |
| `CLOUDFLARE_R2_BUCKET` | Variable | bucket name |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | Variable | R2 token Access Key ID |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | Secret | R2 token Secret Access Key |
| `CLOUDFLARE_R2_PUBLIC_BASE_URL` | Variable | `https://persist.nerd.ceo` |

With `gh`: `gh variable set NAME -b VALUE` for variables, `gh secret set NAME` for the secret.
`CLOUDFLARE_R2_PUBLIC_BASE_URL` is what makes the shipped app's `SUFeedURL` point at the domain
(project.yml's default only affects local `scripts/build-app.sh` builds).

## Verification (after a release runs)

```sh
curl -I https://persist.nerd.ceo/appshots/appcast.xml          # 200, content-type application/xml
curl -s https://persist.nerd.ceo/appshots/appcast.xml | head   # Sparkle XML with <sparkle:version>
```

Before the first release the appcast doesn't exist yet — a `404` there is expected, and the pipeline
treats it as "latest build = 0 → 1".

## Out of scope

Signing/notarization secrets (`KEYCHAIN_PASSWORD`, `DEVELOPER_ID_KEYCHAIN_GZIP_BASE64`,
`SPARKLE_PRIVATE_KEY`) are unrelated to Cloudflare and already expected by the workflow. CORS is not
needed (Sparkle does plain GETs, not browser fetches).
