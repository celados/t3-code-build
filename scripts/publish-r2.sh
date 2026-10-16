#!/usr/bin/env bash
# Upload a built APK to R2 and repoint the stable "latest" links.
#
# usage: publish-r2.sh <out-dir>   (the directory build-android.sh wrote)
# env:   R2_ENDPOINT, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, PUBLIC_BASE_URL
#
# Layout under t3-code/android/:
#   builds/<apk>   immutable, one per build (expired by the bucket lifecycle rule)
#   latest.apk     always the newest build
#   latest.json    metadata for the newest build; also the "already built?" check
set -euo pipefail

out=$(cd "$1" && pwd)
: "${R2_ENDPOINT:?}" "${R2_BUCKET:?}" "${R2_ACCESS_KEY_ID:?}" "${R2_SECRET_ACCESS_KEY:?}" "${PUBLIC_BASE_URL:?}"
prefix=t3-code/android

apk_name=$(jq -r .apk "$out/build.json")
apk="$out/$apk_name"
sha256=$(sha256sum "$apk" | cut -d' ' -f1)

put() { # <file> <key> <content-type> <cache-control>
  curl -fsS --retry 3 -o /dev/null \
    --aws-sigv4 "aws:amz:auto:s3" --user "$R2_ACCESS_KEY_ID:$R2_SECRET_ACCESS_KEY" \
    -H "content-type: $3" -H "cache-control: $4" \
    -T "$1" "$R2_ENDPOINT/$R2_BUCKET/$2"
}

put "$apk" "$prefix/builds/$apk_name" application/vnd.android.package-archive "public, max-age=31536000, immutable"

jq --arg sha256 "$sha256" --arg url "$PUBLIC_BASE_URL/$prefix/builds/$apk_name" \
  '. + {sha256: $sha256, url: $url}' "$out/build.json" > "$out/latest.json"

# latest.json goes last: it is what the next run reads to decide whether to rebuild.
put "$apk" "$prefix/latest.apk" application/vnd.android.package-archive "no-cache"
put "$out/latest.json" "$prefix/latest.json" application/json "no-cache"

# Read back through the public domain, not the S3 endpoint we just wrote to.
served=$(curl -fsS "$PUBLIC_BASE_URL/$prefix/latest.json" | jq -r .sha256)
[[ "$served" == "$sha256" ]] || { echo "latest.json not served yet ($served)" >&2; exit 1; }
echo "published $PUBLIC_BASE_URL/$prefix/latest.apk ($apk_name, sha256 $sha256)"
