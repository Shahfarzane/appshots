# Cloudflare setup for Appshots releases

Maintainer infrastructure notes: what the release pipeline
(`Distribution/Scripts/release.sh` + `.github/workflows/macos-release-production.yml`)
expects from Cloudflare. `updates.nerd.ceo` is this project's feed host;
substitute your own domain on a fork.

## Architecture (what actually serves the feed)

Releases are uploaded to the R2 bucket **`appshots-updates`** and served at
`https://updates.nerd.ceo/<object-key>` by a small **Cloudflare Worker**
(`Distribution/UpdatesProxy/`), not by R2's built-in custom-domain feature:

- **Worker `appshots-updates-proxy`** — read-only GET/HEAD proxy with an R2
  bucket binding; sets short cache for the mutable feed objects and
  `immutable` for versioned artifacts. Deploy with
  `cd Distribution/UpdatesProxy && wrangler deploy`.
- **Route** `updates.nerd.ceo/*` on the `nerd.ceo` zone (declared in
  `wrangler.toml`).
- **DNS**: a plain **proxied `AAAA` record `updates` → `100::`** (the standard
  discard-prefix placeholder for Worker-only hostnames). TLS rides the zone's
  **Universal SSL wildcard certificate** — no per-hostname certificate object.

Why not R2's "Connect Domain" or a Workers Custom Domain? Both provision a
per-hostname certificate through the custom-hostname (SSL-for-SaaS) pipeline,
and on this account those certificates never left `pending` (attempted with
`persist.nerd.ceo`, then twice with `updates.nerd.ceo`). The plain
record + route path avoids that pipeline entirely.

> **History note:** the zone's Universal SSL certificate itself had never
> issued (Edge Certificates showed "No certificates"), which is what broke
> every custom-domain attempt. Toggling Universal SSL off and on again
> (SSL/TLS → Edge Certificates → Disable/Enable Universal SSL) re-triggered
> issuance. If TLS on `updates.nerd.ceo` ever breaks with handshake failures,
> check that page first. The bucket's public dev URL
> (`https://pub-bfc9c06667434ccba3102001f2fa2ee1.r2.dev`) remains a working
> fallback base URL — older installs may still have it baked in, so keep the
> bucket's public access enabled.

## One-time provisioning tasks

1. **R2 bucket** — `appshots-updates` (record the exact name and the 32-hex
   Account ID from the R2 dashboard).
2. **Worker + route + DNS** — deploy `Distribution/UpdatesProxy/` with wrangler,
   then create the proxied `AAAA updates → 100::` record in the zone (DNS →
   Records). The route is created by the deploy.
3. **R2 S3 credentials** — R2 → Manage R2 API Tokens → Create API token,
   permission **Object Read & Write** scoped to the bucket. Yields an
   **Access Key ID** + **Secret Access Key** (shown once). The pipeline derives
   the endpoint `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, region `auto`.
4. **Caching** — handled by the Worker (60s for `appcast.xml`/`latest*`,
   `immutable` for versioned objects); no Cache Rules needed.

## Object / URL contract (do not change these paths)

The pipeline writes, and the app reads, under the `appshots/` prefix by default
(`RELEASE_ENVIRONMENT=appshots`):

| Object key | Public URL | Purpose |
|---|---|---|
| `appshots/appcast.xml` | `https://updates.nerd.ceo/appshots/appcast.xml` | Sparkle feed (`SUFeedURL`); also read to compute the next build number |
| `appshots/latest-appshots-arm64.dmg` | .../appshots/latest-appshots-arm64.dmg | stable "latest" download |
| `appshots/<version>-<ts>-<sha>.dmg` | .../appshots/<...>.dmg | the immutable release DMG |
| `appshots/latest.txt` | .../appshots/latest.txt | pointer file |
| `appshots/appshotsctl-<version>-arm64.zip` | .../appshots/appshotsctl-<version>-arm64.zip | standalone CLI zip |
| `appshots/appshotsctl-latest-arm64.zip` | .../appshots/appshotsctl-latest-arm64.zip | stable standalone CLI pointer |

## Values to set on the GitHub repo

Settings → Secrets and variables → Actions. **Mind the variable-vs-secret split** — the workflow
reads them exactly as shown:

| GitHub name | Kind | Value |
|---|---|---|
| `CLOUDFLARE_R2_ACCOUNT_ID` | Variable | account ID |
| `CLOUDFLARE_R2_BUCKET` | Variable | bucket name (`appshots-updates`) |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | Variable | R2 token Access Key ID |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | Secret | R2 token Secret Access Key |
| `CLOUDFLARE_R2_PUBLIC_BASE_URL` | Variable | `https://updates.nerd.ceo` |

With `gh`: `gh variable set NAME -b VALUE` for variables, `gh secret set NAME` for the secret.
`CLOUDFLARE_R2_PUBLIC_BASE_URL` is what makes the shipped app's `SUFeedURL` point at the domain
(project.yml's default only affects local `scripts/build-app.sh` builds).

## Verification (after a release runs)

```sh
curl -I https://updates.nerd.ceo/appshots/appcast.xml          # 200, content-type application/xml
curl -s https://updates.nerd.ceo/appshots/appcast.xml | head   # Sparkle XML with <sparkle:version>
```

Before the first release the appcast doesn't exist yet — a `404` there is expected, and the pipeline
treats it as "latest build = 0 → 1".

## Out of scope

Signing/notarization secrets (`KEYCHAIN_PASSWORD`, `DEVELOPER_ID_KEYCHAIN_GZIP_BASE64`,
`SPARKLE_PRIVATE_KEY`) are unrelated to Cloudflare and already expected by the workflow — see
[signing-secrets-setup.md](signing-secrets-setup.md). CORS is not needed (Sparkle does plain GETs,
not browser fetches).
