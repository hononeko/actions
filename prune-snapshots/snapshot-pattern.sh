#!/usr/bin/env bash
# Prints the regex matching exactly one pull request's snapshot tags: pr-<N> and pr-<N>-sha-<7 hex>, as named by the
# version action. Anchored, so pr-1 never matches pr-12's tags, nor a release, rc, sha-, latest or edge tag.
#
# Usage: snapshot-pattern.sh <pr-number>
set -euo pipefail

pr=${1-}
if ! [[ $pr =~ ^[1-9][0-9]*$ ]]; then
  echo "::error title=prune-snapshots::Expected a pull request number, got '$pr'" >&2
  exit 1
fi
printf '^pr-%s(-sha-[0-9a-f]{7})?$\n' "$pr"
