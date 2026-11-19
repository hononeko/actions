#!/usr/bin/env bash
# Resolves the setup-gradle cache-read-only boolean as "true" or "false" on stdout.
#
# Environment:
#   CACHE_READ_ONLY_INPUT  optional "true" or "false"; empty defaults to read-only off the default branch
#   REF_NAME               current git ref name (github.ref_name)
#   DEFAULT_BRANCH         repository default branch (github.event.repository.default_branch)
set -euo pipefail

input=${CACHE_READ_ONLY_INPUT-}
input=${input#"${input%%[![:space:]]*}"}
input=${input%"${input##*[![:space:]]}"}

if [ -z "$input" ]; then
  if [ -n "${DEFAULT_BRANCH-}" ] && [ "${REF_NAME-}" != "$DEFAULT_BRANCH" ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
  exit 0
fi

case "$input" in
  true|false)
    printf '%s\n' "$input"
    ;;
  *)
    echo "cache-read-only must be 'true' or 'false', got '$input'" >&2
    exit 1
    ;;
esac
