#!/usr/bin/env bash
# Checks that prune-snapshots' pattern matches exactly one pull request's snapshot tags, and nothing a release needs.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/prune-snapshots/snapshot-pattern.sh"
failures=0
pattern=$("$script" 12)

matches() {
  if grep -Eq "$pattern" <<<"$1"; then echo "ok   matches $1"; else
    echo "FAIL should match: $1"
    failures=$((failures + 1))
  fi
}
spares() {
  if grep -Eq "$pattern" <<<"$1"; then
    echo "FAIL should not match: $1"
    failures=$((failures + 1))
  else echo "ok   spares $1"; fi
}

matches pr-12
matches pr-12-sha-1a2b3c4
spares pr-1
spares pr-120
spares pr-12-sha-1a2b3c
spares pr-12-sha-1a2b3c4d
spares pr-12-sha-1A2B3C4
spares xpr-12
spares pr-12-extra
spares 1.2.3
spares 1.2.3-rc.4
spares sha-1a2b3c4
spares latest
spares edge

for bad in "" 0 012 abc "12|.*" "12 "; do
  if out=$("$script" "$bad" 2>&1); then
    echo "FAIL accepted pr-number '$bad': $out"
    failures=$((failures + 1))
  else
    echo "ok   rejects pr-number '$bad'"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
