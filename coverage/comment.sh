#!/usr/bin/env bash
# Adds or updates the one comment on a pull request that reports its coverage.
#
# Usage: comment.sh <pr-number> <report-file>
#   GITHUB_REPOSITORY  owner/repo
#   GH_TOKEN           a token that may write pull request comments
#   COVERAGE_TITLE     the report's heading; each title keeps its own comment
#
# The comment is found again by a hidden marker, so every push updates it instead of adding another one.
set -euo pipefail

pr=${1:?usage: comment.sh <pr-number> <report-file>}
report=${2:?usage: comment.sh <pr-number> <report-file>}
[[ $pr =~ ^[1-9][0-9]*$ ]] || { echo "::error title=coverage::'$pr' isn't a pull request number" >&2; exit 1; }
# The title goes into the marker, an HTML comment matched in jq, so only plain characters are kept.
key=$(tr -cd 'A-Za-z0-9 _.-' <<<"${COVERAGE_TITLE:-Coverage}")
marker="<!-- hononeko/actions:coverage:$key -->"

body="$marker
$(cat "$report")"

id=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$pr/comments" \
  --jq "first(.[] | select(.body | startswith(\"$marker\")) | .id) // empty")
id=${id%%$'\n'*}
if [ -n "$id" ]; then
  gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -f body="$body" >/dev/null
  echo "Updated comment $id on #$pr"
else
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$pr/comments" -f body="$body" >/dev/null
  echo "Commented on #$pr"
fi
