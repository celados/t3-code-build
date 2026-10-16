#!/usr/bin/env bash
# Upload a built APK to R2 and repoint the stable "latest" links.
#
# usage: publish-r2.sh <out-dir>   (the directory build-android.sh wrote)
# env:   R2_ENDPOINT, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, PUBLIC_BASE_URL
#
# Layout under t3-code/android/:
#   builds/<apk>   immutable, one per build; the newest $KEEP_BUILDS are kept
#   latest.apk     always the newest build
#   latest.json    metadata for the newest build; also the "already built?" check
set -euo pipefail

out=$(cd "$1" && pwd)
: "${R2_ENDPOINT:?}" "${R2_BUCKET:?}" "${R2_ACCESS_KEY_ID:?}" "${R2_SECRET_ACCESS_KEY:?}" "${PUBLIC_BASE_URL:?}"
prefix=t3-code/android
KEEP_BUILDS=${KEEP_BUILDS:-14}

apk_name=$(jq -r .apk "$out/build.json")
apk="$out/$apk_name"
sha256=$(sha256sum "$apk" | cut -d' ' -f1)

s3() { curl -fsS --retry 3 --aws-sigv4 "aws:amz:auto:s3" --user "$R2_ACCESS_KEY_ID:$R2_SECRET_ACCESS_KEY" "$@"; }
put() { # <file> <key> <content-type> <cache-control>
  s3 -o /dev/null -H "content-type: $3" -H "cache-control: $4" -T "$1" "$R2_ENDPOINT/$R2_BUCKET/$2"
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
# The bucket token is object-scoped (no lifecycle rules), so retention happens here. APK names
# start with nightly.<date>, so lexical order is build order.
s3 "$R2_ENDPOINT/$R2_BUCKET?list-type=2&prefix=$prefix/builds/" |
  grep -o '<Key>[^<]*</Key>' | sed 's/<[^>]*>//g' | sort | head -n "-$KEEP_BUILDS" |
  while read -r key; do
    s3 -o /dev/null -X DELETE "$R2_ENDPOINT/$R2_BUCKET/$key"
    echo "pruned $key"
  done

echo "published $PUBLIC_BASE_URL/$prefix/latest.apk ($apk_name, sha256 $sha256)"
