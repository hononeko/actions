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

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All build-image tests passed"
