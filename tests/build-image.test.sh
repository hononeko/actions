#!/usr/bin/env bash
# Checks build-image input validation for valid and malformed inputs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
validate="$root/build-image/validate-inputs.sh"
failures=0

pass() { echo "ok   $1"; }
fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}

should_pass() {
  local name=$1 actual
  if actual=$(BUILD_PUSH=$2 BUILD_IMAGE=$3 BUILD_SBOM=${4-true} BUILD_DIGEST_ARTIFACT=${5-} "$validate" 2>&1); then
    pass "$name"
  else
    fail "$name" "expected pass, got '$actual'"
  fi
}

should_fail() {
  local name=$1 expected=$2 actual
  if actual=$(BUILD_PUSH=$3 BUILD_IMAGE=$4 BUILD_SBOM=${5-true} BUILD_DIGEST_ARTIFACT=${6-} "$validate" 2>&1); then
    fail "$name" "expected failure, got '$actual'"
  elif [[ $actual != *"$expected"* ]]; then
    fail "$name" "expected '$expected', got '$actual'"
  else
    pass "$name"
  fi
}

should_pass "local build without image" "false" ""
should_pass "local build ignores digest-artifact" "false" "" "true" "digests-amd64"
should_pass "push with lowercase image" "true" "ghcr.io/hononeko/thread-udp-proxy" "true" "digests-amd64"
should_pass "push with port and underscores" "true" "localhost:5000/org_1/my-app.svc" "false"

should_fail "push typo True" "'push' must be 'true' or 'false'" "True" "ghcr.io/hononeko/app"
should_fail "push typo yes" "'push' must be 'true' or 'false'" "yes" "ghcr.io/hononeko/app"
should_fail "empty push" "'push' must be 'true' or 'false'" "" "ghcr.io/hononeko/app"
should_fail "invalid sbom" "'sbom' must be 'true' or 'false'" "false" "" "yes"

should_fail "push without image" "'image' is required" "true" ""
should_fail "push with uppercase image" "isn't an image name" "true" "ghcr.io/Hononeko/app"
should_fail "push with tagged image" "isn't an image name" "true" "ghcr.io/hononeko/app:v1"
should_fail "push with digest in image" "isn't an image name" "true" "ghcr.io/hononeko/app@sha256:1234"
should_fail "push with comma in image" "isn't an image name" "true" "ghcr.io/hononeko/app,push=false"
should_fail "push with single segment" "isn't an image name" "true" "ghcr.io"

should_fail "digest-artifact with slash" "must not contain '/'" "true" "ghcr.io/hononeko/app" "true" "digests/amd64"
should_fail "digest-artifact with space" "must not contain '/'" "true" "ghcr.io/hononeko/app" "true" "digests amd64"

# resolve-cache.sh: cache_case <name> <scope> <write> <event> <from> <to> <expected-from> <expected-to>
resolve="$root/build-image/resolve-cache.sh"
output_file=$(mktemp)
trap 'rm -f "$output_file"' EXIT

# Reads a multi-line output (name<<DELIMITER ... DELIMITER) from the GITHUB_OUTPUT file.
read_output() {
  awk -v name="$1" '
    !open && index($0, name "<<") == 1 { delim = substr($0, length(name) + 3); open = 1; next }
    open && $0 == delim { exit }
    open { print }
  ' "$output_file"
}

cache_case() {
  local name=$1 actual from to
  : >"$output_file"
  if ! actual=$(CACHE_SCOPE=$2 CACHE_WRITE=$3 EVENT_NAME=$4 CACHE_FROM=$5 CACHE_TO=$6 GITHUB_OUTPUT=$output_file \
    "$resolve" 2>&1); then
    fail "$name" "expected pass, got '$actual'"
    return
  fi
  from=$(read_output cache-from)
  to=$(read_output cache-to)
  if [ "$from" != "$7" ]; then
    fail "$name" "expected cache-from '$7', got '$from'"
  elif [ "$to" != "$8" ]; then
    fail "$name" "expected cache-to '$8', got '$to'"
  else
    pass "$name"
  fi
}

cache_fail() {
  local name=$1 expected=$2 actual
  if actual=$(CACHE_SCOPE=$3 CACHE_WRITE=$4 EVENT_NAME=push CACHE_FROM="" CACHE_TO="" GITHUB_OUTPUT=$output_file \
    "$resolve" 2>&1); then
    fail "$name" "expected failure, got '$actual'"
  elif [[ $actual != *"$expected"* ]]; then
    fail "$name" "expected '$expected', got '$actual'"
  else
    pass "$name"
  fi
}

gha_from="type=gha,scope=app-amd64"
gha_to="type=gha,mode=max,scope=app-amd64,ignore-error=true"

cache_case "no cache" "" "auto" "push" "" "" "" ""
cache_case "raw cache passed through" "" "auto" "pull_request" "type=registry,ref=r/c" "type=registry,ref=r/c" \
  "type=registry,ref=r/c" "type=registry,ref=r/c"
cache_case "scope on push reads and writes" "app-amd64" "auto" "push" "" "" "$gha_from" "$gha_to"
cache_case "scope on workflow_dispatch writes" "app-amd64" "auto" "workflow_dispatch" "" "" "$gha_from" "$gha_to"
cache_case "scope on pull_request only reads" "app-amd64" "auto" "pull_request" "" "" "$gha_from" ""
cache_case "scope on pull_request_target only reads" "app-amd64" "auto" "pull_request_target" "" "" "$gha_from" ""
cache_case "scope on merge_group only reads" "app-amd64" "auto" "merge_group" "" "" "$gha_from" ""
cache_case "cache-write true on pull_request writes" "app-amd64" "true" "pull_request" "" "" "$gha_from" "$gha_to"
cache_case "cache-write false on push only reads" "app-amd64" "false" "push" "" "" "$gha_from" ""
cache_case "raw cache comes before scope" "app-amd64" "auto" "push" "type=registry,ref=r/c" "type=local,dest=/tmp/c" \
  "type=registry,ref=r/c"$'\n'"$gha_from" "type=local,dest=/tmp/c"$'\n'"$gha_to"
cache_case "raw cache-to kept when not writing" "app-amd64" "auto" "pull_request" "" "type=local,dest=/tmp/c" \
  "$gha_from" "type=local,dest=/tmp/c"

cache_fail "invalid cache-write" "'cache-write' must be 'auto', 'true' or 'false'" "app-amd64" "yes"
cache_fail "cache-write without scope" "'cache-write' needs 'cache-scope'" "" "true"
cache_fail "scope with comma" "'cache-scope' may only hold" "app,mode=min" "auto"
cache_fail "scope with space" "'cache-scope' may only hold" "app amd64" "auto"

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All build-image tests passed"
