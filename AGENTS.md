# T3 Code Build

Nightly Android APK of [pingdotgg/t3code](https://github.com/pingdotgg/t3code) built from upstream
`main`, signed with our own key and published to R2.

- Download: <https://static.celados.com/t3-code/android/latest.apk> (metadata: `latest.json`).
- Variant: upstream's `preview` (`T3 Code Preview`, `com.t3tools.t3code.preview`), installs beside
  the store app. OTA updates are off, so the APK runs exactly the JS it was built from.
- Single ABI: `arm64-v8a`.

## Layout

- `scripts/build-android.sh` — upstream checkout → signed APK + `build.json`. Runs inside the builder image.
- `scripts/publish-r2.sh` — uploads to `celados-static` (`t3-code/android/`), repoints `latest.*`.
- `builder/Dockerfile` — JDK 17, Android SDK/NDK, Node 24. Published by `builder-image.yml` to
  `docker.io/huodong/t3code-android-builder`; the nightly pins it by digest.
- `fixups/*.sh` — temporary repairs for upstream breakage, run after `pnpm install`. Each one must
  name its upstream fix and be a no-op once upstream has it; delete it when it is.

## CI

`android-nightly.yml` runs on `celados-linux-large` (oh, ARC; one heavy pod — sizing and
rationale in [celados/berth docs/github-actions-runner-pool.md](https://github.com/celados/berth/blob/main/docs/github-actions-runner-pool.md#large-pool)).
It skips when `latest.json` already carries the upstream commit; dispatch with `force` to rebuild.

## Secrets

- Signing key: Vaultwarden `celados / products/misc / t3-code / android / nightly-keystore`
  (PKCS12 attachment, password, alias). Rotating it breaks in-place updates of every installed
  nightly. Repo secrets `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` derive from it.
- R2: Vaultwarden `cloudflare / celados / static-r2` → `R2_*` repo secrets.
- Docker Hub push: Vaultwarden `docker-token` → `DOCKERHUB_TOKEN`.
