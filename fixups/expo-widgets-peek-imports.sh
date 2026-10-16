#!/usr/bin/env bash
# expo-widgets 58.0.17–58.0.19 import io.github.jakex7.peek but depend on io.github.expo.peek,
# so the Android build fails with "Unresolved reference 'jakex7'".
# Upstream fix: https://github.com/expo/expo/pull/51654 (released in 58.0.20).
# Retire this file once pingdotgg/t3code pins expo-widgets >= 58.0.20; until then it is a
# no-op on any tree that no longer contains the bad import.
set -euo pipefail
src=$1
mapfile -t files < <(grep -rlF 'io.github.jakex7.peek' "$src"/node_modules/.pnpm/expo-widgets@*/node_modules/expo-widgets/android/src 2>/dev/null || true)
((${#files[@]})) || exit 0
sed -i 's/io\.github\.jakex7\.peek/io.github.expo.peek/g' "${files[@]}"
echo "expo-widgets: rewrote peek imports in ${#files[@]} file(s)"
