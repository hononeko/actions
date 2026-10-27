#!/usr/bin/env bash
# Lints the repository's Dockerfiles with hadolint and annotates its findings: errors as errors, warnings as warnings,
# info and style as notices. Fails when one reaches the failure threshold.
#
# Usage: hadolint.sh
#   HADOLINT_FILES      Dockerfiles, separated by spaces or newlines; empty for every tracked Dockerfile, Containerfile,
#                       Dockerfile.* and *.Dockerfile
#   HADOLINT_THRESHOLD  error, warning, info, style or ignore (default warning)
#   HADOLINT_CONFIG     config file; empty for hadolint's own lookup (.hadolint.yaml)
#   HADOLINT_IMAGE      the hadolint image to run
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fail() {
  echo "::error title=lint-docker::$1" >&2
  exit 1
}

threshold=${HADOLINT_THRESHOLD:-warning}
[[ $threshold =~ ^(error|warning|info|style|ignore)$ ]] ||
  fail "failure-threshold must be error, warning, info, style or ignore, got '$threshold'"

root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "$PWD isn't in a git repository"
cd "$root"

if [ -n "${HADOLINT_FILES-}" ]; then
  read -ra files <<<"$(tr '\n' ' ' <<<"$HADOLINT_FILES")"
  for f in "${files[@]}"; do [ -f "$f" ] || fail "No Dockerfile at $f"; done
else
  mapfile -t files < <(git ls-files -- ':(glob)**/Dockerfile' ':(glob)**/Dockerfile.*' ':(glob)**/*.Dockerfile' \
    ':(glob)**/*.dockerfile' ':(glob)**/Containerfile' ':(glob)**/Containerfile.*' | grep -v '\.dockerignore$' || true)
fi
[ "${#files[@]}" -gt 0 ] || fail "No Dockerfiles to lint"

args=(--format json --failure-threshold "$threshold")
if [ -n "${HADOLINT_CONFIG-}" ]; then
  [ -f "$HADOLINT_CONFIG" ] || fail "No hadolint config at $HADOLINT_CONFIG"
  args+=(--config "$HADOLINT_CONFIG")
fi

echo "Linting ${files[*]}" >&2
results=$(mktemp)
trap 'rm -f "$results"' EXIT
status=0
docker run --rm -v "$root:/repo:ro" -w /repo "${HADOLINT_IMAGE:?}" hadolint "${args[@]}" -- "${files[@]}" \
  >"$results" || status=$?
"$here/annotations.sh" "$results"
[ "$status" -eq 0 ] || fail "hadolint found issues at or above '$threshold'"
