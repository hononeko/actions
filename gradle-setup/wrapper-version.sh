#!/usr/bin/env bash
# Prints the Gradle version a project's wrapper pins. Without a wrapper, a build runs whatever Gradle the runner has.
#
# Usage: wrapper-version.sh [project-dir]
#
# Reads distributionUrl from <project-dir>/gradle/wrapper/gradle-wrapper.properties and fails when there's no wrapper
# or no version in it. A wrapper without distributionSha256Sum still resolves, with a warning on stderr: the wrapper
# then runs whatever distribution that URL serves.
set -euo pipefail

dir=${1:-.}
props="$dir/gradle/wrapper/gradle-wrapper.properties"

if [ ! -f "$props" ]; then
  echo "No Gradle wrapper in $dir: run \"gradle wrapper --gradle-version X.Y.Z\" and commit gradlew and gradle/wrapper" >&2
  exit 1
fi

# key=value or key:value, trimmed; properties files escape the colon in a URL as "\:"
property() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*[=:][[:space:]]*//p" "$props" | head -n 1 | tr -d '\r' |
    sed 's/[[:space:]]*$//'
}

url=$(property distributionUrl)
url=${url//\\:/:}
if ! [[ $url =~ /gradle-([^/]+)-(bin|all)\.zip$ ]]; then
  echo "No Gradle version in distributionUrl of $props: expected .../gradle-X.Y.Z-bin.zip, got \"$url\"" >&2
  exit 1
fi
version=${BASH_REMATCH[1]}

if [ -z "$(property distributionSha256Sum)" ]; then
  echo "$props has no distributionSha256Sum, so the Gradle distribution isn't verified: run" \
    "\"./gradlew wrapper --gradle-version $version --gradle-distribution-sha256-sum <sha256>\"" >&2
fi
printf '%s\n' "$version"
