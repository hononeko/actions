#!/usr/bin/env bash
# Finds a commit's release candidate image and prints its digest. When it isn't there yet, it waits for the workflow
# run that publishes it for that commit, so a release dispatched right after a merge doesn't fail on a race. It fails
# when that run fails, doesn't start, or doesn't finish in time.
#
# Usage: find-release-candidate.sh <image> <tag>
#   RC_WORKFLOW        the workflow that publishes the candidate (default main.yml)
#   RC_SHA             the commit (default GITHUB_SHA)
#   RC_TIMEOUT         minutes to wait for that run to finish (default 60)
#   RC_START_TIMEOUT   seconds to wait for the run to appear after the push (default 120)
#   RC_POLL            seconds between checks (default 15)
#   GITHUB_REPOSITORY  owner/repo
#   GH_TOKEN           a token that may read the repository's workflow runs
set -euo pipefail

fail() {
  echo "::error title=release-candidate::$1" >&2
  exit 1
}

image=${1-}
tag=${2-}
workflow=${RC_WORKFLOW:-main.yml}
sha=${RC_SHA:-${GITHUB_SHA-}}
timeout=${RC_TIMEOUT:-60}
start_timeout=${RC_START_TIMEOUT:-120}
poll=${RC_POLL:-15}
[[ $image =~ ^[a-z0-9]+([._/:-][a-z0-9]+)*$ ]] || fail "Expected an image like ghcr.io/owner/app, got '$image'"
[[ $tag =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]] || fail "Expected an image tag, got '$tag'"
[[ $sha =~ ^[0-9a-f]{40}$ ]] || fail "Expected a full commit SHA, got '$sha'"
for n in "$timeout" "$start_timeout" "$poll"; do
  [[ $n =~ ^[0-9]+$ ]] || fail "Timeouts and the poll interval must be whole numbers, got '$n'"
done
ref=$image:$tag

exists() { docker buildx imagetools inspect "$ref" >/dev/null 2>&1; }

if ! exists; then
  echo "$ref doesn't exist yet; waiting for $workflow on ${sha:0:7}, which publishes it" >&2
  started=$SECONDS
  while :; do
    read -r id status conclusion < <(gh run list -R "${GITHUB_REPOSITORY:?}" --workflow "$workflow" --commit "$sha" \
      --limit 1 --json databaseId,status,conclusion --jq '.[0] | "\(.databaseId) \(.status) \(.conclusion)"' || true) ||
      true
    if [ -z "${id-}" ] || [ "$id" = null ]; then
      # A push's run shows up a few seconds after it.
      [ $((SECONDS - started)) -lt "$start_timeout" ] ||
        fail "No $workflow run for ${sha:0:7}, so there's no release candidate $ref; release a commit $workflow ran for"
    elif [ "$status" = completed ]; then
      break
    else
      echo "$workflow run $id is $status" >&2
      [ $((SECONDS - started)) -lt $((timeout * 60)) ] ||
        fail "$workflow run $id for ${sha:0:7} didn't finish within $timeout minutes"
    fi
    sleep "$poll"
  done
  url=https://github.com/$GITHUB_REPOSITORY/actions/runs/$id
  [ "$conclusion" = success ] ||
    fail "$workflow run for ${sha:0:7} ended in '$conclusion', so there's no release candidate $ref: $url"
  exists || fail "$workflow passed for ${sha:0:7} without publishing $ref (it publishes one only when there's something to release): $url"
fi

docker buildx imagetools inspect "$ref" --format '{{json .Manifest}}' | jq -r .digest
