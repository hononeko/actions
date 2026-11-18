#!/usr/bin/env bash
# Validates build-image inputs before invoking docker/build-push-action.
#
# Environment:
#   BUILD_PUSH             "true" or "false"
#   BUILD_IMAGE            target image name without tag or digest (required when BUILD_PUSH is "true")
#   BUILD_SBOM             "true" or "false"
#   BUILD_DIGEST_ARTIFACT  optional artifact name (must not contain "/" or whitespace)
set -euo pipefail

push=${BUILD_PUSH-}
image=${BUILD_IMAGE-}
sbom=${BUILD_SBOM-}
digest_artifact=${BUILD_DIGEST_ARTIFACT-}

fail() {
  echo "::error title=build-image::$1" >&2
  exit 1
}

if [ "$push" != "true" ] && [ "$push" != "false" ]; then
  fail "'push' must be 'true' or 'false', got '$push'"
fi

if [ "$sbom" != "true" ] && [ "$sbom" != "false" ]; then
  fail "'sbom' must be 'true' or 'false', got '$sbom'"
fi

if [ "$push" = "true" ]; then
  [ -n "$image" ] || fail "'image' is required when 'push' is 'true'"
  # registry[:port]/path, lowercase, without a tag, digest or comma.
  name_re='^[a-z0-9]+([.-][a-z0-9]+)*(:[0-9]+)?(/[a-z0-9]+([._-]+[a-z0-9]+)*)+$'
  [[ $image =~ $name_re ]] || fail "'$image' isn't an image name like ghcr.io/owner/name"
fi

if [ -n "$digest_artifact" ] && [[ $digest_artifact =~ [/[:space:]] ]]; then
  fail "'digest-artifact' must not contain '/' or whitespace, got '$digest_artifact'"
fi
