#!/usr/bin/env bash
# Prints the exact Bun version a project pins, so builds never float to "latest".
#
# Usage: resolve-version.sh [project-dir]
#   BUN_VERSION_INPUT  explicit version; wins over the project's own pin
#
# Looks at, in order: BUN_VERSION_INPUT, the first line of <project-dir>/.bun-version, and
# "packageManager": "bun@X.Y.Z" in <project-dir>/package.json. A leading "v" or "bun-v" and a Corepack-style
# "+sha512..." suffix are dropped. Anything but an exact version (latest, 1.4, ^1.4.0) fails, naming its source.
set -euo pipefail

dir=${1:-.}
version=""
source=""

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

if [ -n "${BUN_VERSION_INPUT:-}" ]; then
  version=$BUN_VERSION_INPUT
  source="the bun-version input"
elif [ -f "$dir/.bun-version" ]; then
  version=$(head -n 1 "$dir/.bun-version")
  source="$dir/.bun-version"
elif [ -f "$dir/package.json" ]; then
  version=$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"bun@\([^"]*\)".*/\1/p' "$dir/package.json" | head -n 1)
  source="packageManager in $dir/package.json"
fi

version=$(trim "$version")
version=${version%%+*}
version=${version#bun-v}
version=${version#v}

if [ -z "$version" ]; then
  echo "No Bun version pinned: set the bun-version input, add a .bun-version file, or set" \
    "\"packageManager\": \"bun@X.Y.Z\" in package.json" >&2
  exit 1
fi
if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Bun version \"$version\" from $source is not an exact version like 1.4.3" >&2
  exit 1
fi
printf '%s\n' "$version"
