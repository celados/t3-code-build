#!/usr/bin/env bash
# Build a signed T3 Code Preview APK from an upstream checkout.
#
# usage: build-android.sh <upstream-checkout> <out-dir>
# env:   ANDROID_KEYSTORE (path), ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
#        ANDROID_ARCHS (default arm64-v8a), GRADLE_MAX_WORKERS (default 4)
# Requires JDK 17, Node 24 with corepack, and ANDROID_HOME (see builder/Dockerfile).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)
: "${ANDROID_KEYSTORE:?}" "${ANDROID_KEYSTORE_PASSWORD:?}" "${ANDROID_KEY_ALIAS:?}" "${ANDROID_KEY_PASSWORD:?}"
archs=${ANDROID_ARCHS:-arm64-v8a}
workers=${GRADLE_MAX_WORKERS:-4}

sha=$(git -C "$src" rev-parse HEAD)
short=${sha:0:12}
stamp=$(date -u +%Y%m%d)
# Monotonic across nightlies so a sideloaded build always installs over the previous one.
version_code=$(date -u +%s)
version_code=$((version_code / 60))
version_name="nightly.${stamp}.${short}"

cd "$src"
# The same public identifiers upstream bakes into official builds; enables T3 Connect.
cp .env.example .env

# Preview variant: installs beside the store app as "T3 Code Preview". OTA stays off so the
# APK runs exactly the JS it was built from.
export APP_VARIANT=preview
export T3CODE_MOBILE_UPDATES_ENABLED=0
export EXPO_NO_GIT_STATUS=1
export CI=1
export NODE_OPTIONS=--max-old-space-size=6144

# Gradle and the JVM ignore HTTP(S)_PROXY; translate it for hosts that only egress via a proxy.
proxy=${HTTPS_PROXY:-${https_proxy:-}}
if [[ -n "$proxy" ]]; then
  hostport=${proxy#*://}
  hostport=${hostport%%/*}
  host=${hostport%:*}
  port=${hostport##*:}
  export GRADLE_OPTS="${GRADLE_OPTS:-} -Dhttp.proxyHost=$host -Dhttp.proxyPort=$port -Dhttps.proxyHost=$host -Dhttps.proxyPort=$port -Dhttp.nonProxyHosts=localhost|127.0.0.1"
fi

corepack install
pnpm install --frozen-lockfile --filter=@t3tools/mobile...

# Temporary repairs for upstream breakage; each one is a no-op once upstream is fixed.
for fixup in "$here"/../fixups/*.sh; do
  [[ -e "$fixup" ]] && "$fixup" "$src"
done

cd apps/mobile
pnpm exec expo prebuild --clean --platform android --no-install

gradle_file=android/app/build.gradle
grep -q 'versionCode 1$' "$gradle_file"
sed -i -E \
  -e "s/^(\s*)versionCode 1$/\1versionCode ${version_code}/" \
  -e "s/^(\s*)versionName \"([^\"]+)\"$/\1versionName \"\2-${version_name}\"/" \
  "$gradle_file"

cd android
# The proxy path drops an occasional TLS handshake; Gradle's own retries cover most of it and a
# second invocation resumes from what the first one already resolved and compiled.
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.internal.repository.max.retries=6 -Dorg.gradle.internal.repository.initial.backoff=2000"
gradle() {
  ./gradlew assembleRelease \
    --no-daemon \
    --max-workers="$workers" \
    -PreactNativeArchitectures="$archs"
}
gradle || { echo "gradle failed; retrying once" >&2; gradle; }

unsigned=app/build/outputs/apk/release/app-release.apk
apk="$out/t3code-preview-${version_name}.apk"
build_tools=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 | sort -V | tail -1)
# Release is debug-signed by the Expo template; replace that with the nightly key.
"$build_tools/apksigner" sign \
  --ks "$ANDROID_KEYSTORE" \
  --ks-pass env:ANDROID_KEYSTORE_PASSWORD \
  --ks-key-alias "$ANDROID_KEY_ALIAS" \
  --key-pass env:ANDROID_KEY_PASSWORD \
  --out "$apk" "$unsigned"
"$build_tools/apksigner" verify --print-certs "$apk" | head -3

cat > "$out/build.json" <<JSON
{"upstream_sha":"$sha","version_name":"$(grep -oP 'versionName "\K[^"]+' app/build.gradle)","version_code":$version_code,"archs":"$archs","apk":"$(basename "$apk")","built_at":"$(date -u +%FT%TZ)"}
JSON
cat "$out/build.json"
