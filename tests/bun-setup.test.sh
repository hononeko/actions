#!/usr/bin/env bash
# Runs bun-setup/resolve-version.sh against throwaway projects and checks the version it resolves, or that it fails.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/bun-setup/resolve-version.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# project <name> [.bun-version content] [package.json content]: creates $work/<name>
project() {
  local dir="$work/$1"
  mkdir -p "$dir"
  if [ -n "${2-}" ]; then printf '%b' "$2" >"$dir/.bun-version"; fi
  if [ -n "${3-}" ]; then printf '%s\n' "$3" >"$dir/package.json"; fi
  printf '%s' "$dir"
}

# check <name> <dir> <expected version> [explicit input]
check() {
  local name=$1 dir=$2 expected=$3 actual
  if ! actual=$(BUN_VERSION_INPUT=${4-} "$script" "$dir" 2>&1); then actual="failed: $actual"; fi
  if [ "$actual" = "$expected" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: expected '$expected', got '$actual'"
    failures=$((failures + 1))
  fi
}

# check_fails <name> <dir> <expected error substring> [explicit input]
check_fails() {
  local name=$1 dir=$2 expected=$3 actual
  if actual=$(BUN_VERSION_INPUT=${4-} "$script" "$dir" 2>&1); then
    echo "FAIL $name: expected a failure, got '$actual'"
    failures=$((failures + 1))
  elif [[ $actual == *"$expected"* ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: expected an error containing '$expected', got '$actual'"
    failures=$((failures + 1))
  fi
}

pinned=$(project pinned '1.4.3\n' '{ "packageManager": "bun@1.2.0" }')
check ".bun-version wins over packageManager" "$pinned" 1.4.3
check "the input wins over the project" "$pinned" 1.5.0 1.5.0
check "the input may have a leading v" "$pinned" 1.5.0 v1.5.0
check "whitespace-only input falls back to .bun-version" "$pinned" 1.4.3 "   "

check ".bun-version with CRLF and spaces" "$(project crlf '  1.4.3 \r\n')" 1.4.3
check ".bun-version with a bun-v prefix" "$(project prefixed 'bun-v1.4.3\n')" 1.4.3
check "a prerelease version" "$(project canary '1.5.0-canary.1\n')" 1.5.0-canary.1

check "packageManager" "$(project pm '' '{ "name": "x", "packageManager": "bun@1.4.3" }')" 1.4.3
check "packageManager with a Corepack hash" \
  "$(project pm-hash '' '{ "packageManager": "bun@1.4.3+sha512.abc123" }')" 1.4.3

check_fails "nothing pinned" "$(project empty '' '{ "name": "x" }')" "No Bun version pinned"
check_fails "no project files" "$(project bare)" "No Bun version pinned"
check_fails "another package manager" "$(project npm '' '{ "packageManager": "npm@10.9.0" }')" "No Bun version pinned"
check_fails "latest" "$(project latest 'latest\n')" 'Bun version "latest"'
check_fails "a partial version" "$(project partial '1.4\n')" "is not an exact version"
check_fails "a range" "$(project range '' '{ "packageManager": "bun@^1.4.0" }')" "packageManager in"
check_fails "an invalid input" "$pinned" "from the bun-version input" "1.x"
check_fails "stacked prefix in .bun-version" "$(project stacked 'bun-vv1.4.3\n')" "is not an exact version"
check_fails "stacked prefix in input" "$pinned" "is not an exact version" "bun-vv1.4.3"
check_fails ".bun-version with plus suffix" "$(project plus '1.4.3+sha512\n')" "is not an exact version"
check_fails "input with plus suffix" "$pinned" "is not an exact version" "1.4.3+sha512"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
