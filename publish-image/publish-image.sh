#!/usr/bin/env bash
# Joins per-architecture images, each pushed by digest, into one multi-arch image under the given tags.
#
# Usage: publish-image.sh <image> <digests-dir>
#   PUBLISH_TAGS              tags to publish, separated by spaces or newlines; the first one names the image in reports
#   PUBLISH_EXPECTED_DIGESTS  fail unless exactly this many digests were found (default: any number but 0)
#   PUBLISH_TITLE             heading of the job summary (default "Image published")
#
# <digests-dir> holds one empty file per architecture, named by its image digest without "sha256:". Inputs are checked
# before anything is pushed: the image name, each digest and each tag must be well formed. Prints the multi-arch
# image's reference (<image>:<first tag>@<digest>), and in GitHub Actions writes the `digest` and `reference` outputs
# and adds a job summary.
set -euo pipefail

image=${1:?usage: publish-image.sh <image> <digests-dir>}
dir=${2:?usage: publish-image.sh <image> <digests-dir>}
expected=${PUBLISH_EXPECTED_DIGESTS-}
title=${PUBLISH_TITLE:-Image published}

fail() {
  echo "::error title=publish-image::$1" >&2
  exit 1
}

# registry[:port]/path, lowercase, as Docker requires.
name_re='^[a-z0-9]+([.-][a-z0-9]+)*(:[0-9]+)?(/[a-z0-9]+([._-]+[a-z0-9]+)*)+$'
[[ $image =~ $name_re ]] || fail "'$image' isn't an image name like ghcr.io/owner/name"

sources=()
shopt -s nullglob
for file in "$dir"/*; do
  digest=${file##*/}
  [[ $digest =~ ^[0-9a-f]{64}$ ]] || fail "'$digest' in $dir isn't a sha256 digest"
  sources+=("$image@sha256:$digest")
done
shopt -u nullglob
[ "${#sources[@]}" -gt 0 ] || fail "No digests in $dir"
if [ -n "$expected" ] && [ "${#sources[@]}" -ne "$expected" ]; then
  fail "Expected $expected digests, got ${#sources[@]}"
fi

# Split on whitespace without globbing, so a stray "*" can't expand.
read -r -d '' -a tags < <(printf '%s\0' "${PUBLISH_TAGS-}") || true
[ "${#tags[@]}" -gt 0 ] || fail "No tags to publish"
args=()
for tag in "${tags[@]}"; do
  [[ $tag =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || fail "'$tag' isn't a valid image tag"
  args+=(-t "$image:$tag")
done

docker buildx imagetools create "${args[@]}" "${sources[@]}"
digest=$(docker buildx imagetools inspect "$image:${tags[0]}" --format '{{json .Manifest}}' | jq -r .digest)
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || fail "Couldn't read the digest of $image:${tags[0]}, got '$digest'"
reference="$image:${tags[0]}@$digest"
echo "$reference"

if [ -n "${GITHUB_OUTPUT-}" ]; then
  {
    echo "digest=$digest"
    echo "reference=$reference"
  } >>"$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY-}" ]; then
  {
    echo "### $title"
    echo
    echo "\`$reference\`"
    echo
    # shellcheck disable=SC2016 # Markdown backticks, not a command substitution
    echo "Tags: $(printf '`%s` ' "${tags[@]}")"
  } >>"$GITHUB_STEP_SUMMARY"
fi
