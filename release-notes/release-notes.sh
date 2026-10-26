#!/usr/bin/env bash
# Writes the Markdown release notes for the commits since the last release, grouped by Conventional Commit type:
#
#   💥 Breaking changes   a "!" in the header, or a BREAKING CHANGE: footer (the version action's major rule)
#   🚀 Features           feat
#   🐛 Bug fixes          fix
#   👷 CI                 ci
#   📦 Others             every other type, docs: and test: included
#
# Each entry reads "type(scope): subject #PR", oldest first; empty sections are left out. The PR comes from the
# " (#N)" a squash merge ends its subject with. Otherwise (a rebase merge) it's looked up on GitHub when GH_TOKEN is
# set, and a commit that didn't come from a PR links itself.
#
# Usage: release-notes.sh <previous-tag> [ref] [tag]
#   previous-tag  the last release's tag; empty for the first release (every commit up to ref)
#   ref           the commit being released (default HEAD)
#   tag           the release's own tag, for the Full Changelog link (default: ref's short commit)
#   GITHUB_REPOSITORY  owner/repo for the PR lookup and links (default: from the origin remote)
#   GH_TOKEN           enables the PR lookup for subjects without "(#N)"
set -euo pipefail

prev_tag=${1-}
ref=${2:-HEAD}
if [ -n "${3-}" ]; then
  to=$3
else
  full_ref=$(git rev-parse "$ref")
  to=${full_ref:0:7}
fi
repo=${GITHUB_REPOSITORY:-$(git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')}

range=$ref
if [ -n "$prev_tag" ]; then range="$prev_tag..$ref"; fi

# The merged PR that brought in a commit, or nothing.
pr_of() {
  if [ -z "${GH_TOKEN-}" ]; then return 0; fi
  gh api "repos/$repo/commits/$1/pulls" --jq 'map(select(.merged_at != null))[0].number // empty' 2>/dev/null || true
}

breaking=() features=() fixes=() ci=() others=()

# Listed first, so a bad range fails the script instead of giving empty notes.
commits=$(git rev-list --reverse "$range")
for sha in $commits; do
  subject=$(git log -1 --format=%s "$sha")
  body=$(git log -1 --format=%b "$sha")

  if [[ $subject =~ ^(.*)\ \(#([0-9]+)\)$ ]]; then
    entry="* ${BASH_REMATCH[1]} #${BASH_REMATCH[2]}"
  else
    pr=$(pr_of "$sha")
    if [ -n "$pr" ]; then entry="* $subject #$pr"; else entry="* $subject ${sha:0:7}"; fi
  fi

  # The version action's major rule, matched the way semantic-version does: the header pattern ("!" before the
  # colon; type!(scope): too, as older commits used it) against the start of the subject and of the body, and a
  # BREAKING CHANGE: footer against any body line.
  bang='^[a-z]+(\([^)]*\))?!(\([^)]*\))?:'
  if [[ $subject =~ $bang || $body =~ $bang ]] || grep -qE '^BREAKING[ -]CHANGE:' <<<"$body"; then
    breaking+=("$entry")
  elif [[ $subject =~ ^feat(\([^\)]*\))?: ]]; then
    features+=("$entry")
  elif [[ $subject =~ ^fix(\([^\)]*\))?: ]]; then
    fixes+=("$entry")
  elif [[ $subject =~ ^ci(\([^\)]*\))?: ]]; then
    ci+=("$entry")
  else
    others+=("$entry")
  fi
done

section() {
  local title=$1
  shift
  if [ $# -gt 0 ]; then
    printf '## %s\n\n' "$title"
    printf '%s\n' "$@"
    printf '\n'
  fi
}

section "💥 Breaking changes" "${breaking[@]}"
section "🚀 Features" "${features[@]}"
section "🐛 Bug fixes" "${fixes[@]}"
section "👷 CI" "${ci[@]}"
section "📦 Others" "${others[@]}"

if [ -n "$prev_tag" ]; then
  printf '**Full Changelog**: https://github.com/%s/compare/%s...%s\n' "$repo" "$prev_tag" "$to"
else
  printf '**Full Changelog**: https://github.com/%s/commits/%s\n' "$repo" "$to"
fi
