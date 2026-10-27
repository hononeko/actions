#!/usr/bin/env bash
# Downloads the detekt CLI (and, with ktlint, its ktlint rules), checks them against the checksums pinned in
# checksums.txt, and runs detekt on the current directory. Findings are annotated, from detekt's SARIF report.
#
# Usage: detekt.sh
#   DETEKT_VERSION   e.g. 1.23.8 or 2.0.0-alpha.6
#   DETEKT_CONFIG    config file; empty for config/detekt/detekt.yml when it exists
#   DETEKT_BASELINE  baseline file; empty for config/detekt/baseline.xml when it exists
#   DETEKT_KTLINT    "true" to add detekt's ktlint rules (detekt-formatting, or detekt-rules-ktlint-wrapper from 2.0)
#   DETEKT_ARGS      additional detekt arguments, split on whitespace
#   DETEKT_CACHE     directory to keep the downloads in
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fail() {
  echo "::error title=lint-kotlin::$1" >&2
  exit 1
}

version=${DETEKT_VERSION:?}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || fail "detekt-version must be a version like 1.23.8, got '$version'"
cache=${DETEKT_CACHE:?}
mkdir -p "$cache"

# Downloads a release asset into the cache, unless it's there already, and checks it.
fetch() {
  local name=$1 file=$cache/$1 sum
  sum=$(awk -v n="$name" '$2 == n { print $1 }' "$here/checksums.txt")
  if [ ! -f "$file" ]; then
    curl -fsSL --retry 3 -o "$file.part" "https://github.com/detekt/detekt/releases/download/v$version/$name" ||
      fail "Can't download $name"
    mv "$file.part" "$file"
  fi
  if [ -n "$sum" ]; then
    echo "$sum  $file" | sha256sum -c --quiet - >&2 || { rm -f "$file"; fail "$name doesn't match its pinned checksum"; }
  else
    echo "::warning title=lint-kotlin::No pinned checksum for $name, so it isn't verified" >&2
  fi
  echo "$file"
}

# Paths in the report are relative to the repository, as annotations need them.
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
report=$(mktemp)
trap 'rm -f "$report"' EXIT
args=(--input . --excludes "**/build/**,**/.gradle/**" --base-path "$root" --build-upon-default-config
  --report "sarif:$report")
config=${DETEKT_CONFIG-}
[ -n "$config" ] || [ ! -f config/detekt/detekt.yml ] || config=config/detekt/detekt.yml
if [ -n "$config" ]; then
  [ -f "$config" ] || fail "No detekt config at $config"
  args+=(--config "$config")
fi
baseline=${DETEKT_BASELINE-}
[ -n "$baseline" ] || [ ! -f config/detekt/baseline.xml ] || baseline=config/detekt/baseline.xml
if [ -n "$baseline" ]; then
  [ -f "$baseline" ] || fail "No detekt baseline at $baseline"
  args+=(--baseline "$baseline")
fi

jar=$(fetch "detekt-cli-$version-all.jar")
if [ "${DETEKT_KTLINT-}" = "true" ]; then
  if [[ $version == 1.* ]]; then plugin="detekt-formatting-$version.jar"; else plugin="detekt-rules-ktlint-wrapper-$version.jar"; fi
  args+=(--plugins "$(fetch "$plugin")")
fi
# shellcheck disable=SC2206 # split on whitespace, as documented
[ -z "${DETEKT_ARGS-}" ] || { set -f; args+=($DETEKT_ARGS); set +f; }

# detekt's embedded Kotlin compiler may not know the newest JDK, so it runs on the runner's JDK 21 when there is one.
java=java
for home in "${JAVA_HOME_21_X64-}" "${JAVA_HOME_21_ARM64-}"; do
  if [ -n "$home" ] && [ -x "$home/bin/java" ]; then
    java=$home/bin/java
    break
  fi
done

status=0
"$java" -jar "$jar" "${args[@]}" || status=$?
[ ! -s "$report" ] || "$here/sarif-annotations.sh" "$report"
case $status in
  0) ;;
  2) fail "detekt found issues" ;;
  3) fail "detekt's configuration is invalid" ;;
  *) fail "detekt failed (exit code $status)" ;;
esac
