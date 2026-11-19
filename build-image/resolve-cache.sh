#!/usr/bin/env bash
# Resolves build-image's Buildx cache-from and cache-to, adding a GitHub Actions cache scope when one is set.
#
# Environment:
#   CACHE_SCOPE   optional GitHub Actions cache scope, e.g. app-amd64; empty to add no cache
#   CACHE_WRITE   "auto", "true" or "false": whether to export to that scope. "auto" exports unless EVENT_NAME is a
#                 pull request or merge queue event, whose caches the default branch can't read
#   CACHE_FROM    extra cache sources, passed through first
#   CACHE_TO      extra cache destinations, passed through first
#   EVENT_NAME    the triggering event (github.event_name)
#   GITHUB_OUTPUT file the cache-from and cache-to outputs are appended to
set -euo pipefail

scope=${CACHE_SCOPE-}
write=${CACHE_WRITE:-auto}
from=${CACHE_FROM-}
to=${CACHE_TO-}
event=${EVENT_NAME-}
output=${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}

fail() {
  echo "::error title=build-image::$1" >&2
  exit 1
}

case $write in
  auto | true | false) ;;
  *) fail "'cache-write' must be 'auto', 'true' or 'false', got '$write'" ;;
esac

if [ -z "$scope" ]; then
  [ "$write" = "auto" ] || fail "'cache-write' needs 'cache-scope'"
else
  # Buildx parses cache options as comma-separated key=value pairs, so the scope can't hold separators.
  [[ $scope =~ ^[A-Za-z0-9._-]+$ ]] || fail "'cache-scope' may only hold letters, digits, '.', '_' and '-', got '$scope'"

  if [ "$write" = "auto" ]; then
    case $event in
      pull_request | pull_request_target | merge_group) write=false ;;
      *) write=true ;;
    esac
  fi

  from+="${from:+$'\n'}type=gha,scope=$scope"
  if [ "$write" = "true" ]; then
    # A cache service hiccup shouldn't fail an image that built.
    to+="${to:+$'\n'}type=gha,mode=max,scope=$scope,ignore-error=true"
  fi
fi

delimiter="EOF_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
{
  printf 'cache-from<<%s\n%s\n%s\n' "$delimiter" "$from" "$delimiter"
  printf 'cache-to<<%s\n%s\n%s\n' "$delimiter" "$to" "$delimiter"
} >>"$output"
