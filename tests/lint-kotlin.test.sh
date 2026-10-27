#!/usr/bin/env bash
# Checks lint-kotlin's default detekt version has pinned checksums for its jars, so a version bump (by Renovate) can't
# quietly drop the check.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version=$(yq '.inputs.detekt-version.default' "$root/lint-kotlin/action.yml")
if [[ $version == 1.* ]]; then plugin="detekt-formatting-$version.jar"; else plugin="detekt-rules-ktlint-wrapper-$version.jar"; fi
failures=0

for jar in "detekt-cli-$version-all.jar" "$plugin"; do
  if grep -Eq "^[0-9a-f]{64}  $jar\$" "$root/lint-kotlin/checksums.txt"; then
    echo "ok   checksum for $jar"
  else
    echo "FAIL no checksum for $jar in lint-kotlin/checksums.txt"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
