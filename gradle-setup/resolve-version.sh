#!/usr/bin/env bash
# Prints the JDK distribution and version a project pins, as GitHub step outputs:
#   java-distribution=<name>
#   java-version=<version>
#
# Usage: resolve-version.sh [project-dir]
#   JAVA_VERSION_INPUT       explicit version; wins over the project's own pin
#   JAVA_DISTRIBUTION_INPUT  explicit distribution; wins over the pin's prefix
#
# The version comes from JAVA_VERSION_INPUT or the first line of <project-dir>/.java-version, optionally prefixed with
# a distribution the way mise and asdf write it (zulu-25, temurin-25.0.1). It's either a feature release (25), which
# takes that release's newest update, or an exact version (25.0.1, or with the distribution's full build like
# 25.0.1+8.0.LTS). Anything else (25.0, 25.x, latest, 26-ea) fails, naming its source. The distribution defaults to
# temurin and must be one actions/setup-java installs from its own downloads.
set -euo pipefail

dir=${1:-.}
version=""
source=""
distributions="temurin zulu liberica liberica-nik microsoft semeru corretto oracle dragonwell sapmachine graalvm
graalvm-community jetbrains kona oracle-openjdk redhat"

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

if [ -n "${JAVA_VERSION_INPUT:-}" ]; then
  version=$JAVA_VERSION_INPUT
  source="the java-version input"
elif [ -f "$dir/.java-version" ]; then
  version=$(head -n 1 "$dir/.java-version")
  source="$dir/.java-version"
fi

version=$(trim "$version")

if [ -z "$version" ]; then
  echo "No JDK version pinned: set the java-version input or add a .java-version file" >&2
  exit 1
fi

# A distribution prefix is everything before the first "-" followed by a digit, so liberica-nik-25 keeps its name
prefix=""
if [[ $version =~ ^([a-z][a-z-]*)-([0-9].*)$ ]]; then
  prefix=${BASH_REMATCH[1]}
  version=${BASH_REMATCH[2]}
fi

if ! [[ $version =~ ^[0-9]+(\.[0-9]+\.[0-9]+(\+[0-9A-Za-z.-]+)?)?$ ]]; then
  echo "JDK version \"$version\" from $source is neither a feature release like 25 nor an exact version like 25.0.1" >&2
  exit 1
fi

distribution=$(trim "${JAVA_DISTRIBUTION_INPUT:-}")
if [ -n "$distribution" ]; then
  distribution_source="the java-distribution input"
elif [ -n "$prefix" ]; then
  distribution=$prefix
  distribution_source=$source
else
  distribution=temurin
  distribution_source="the default"
fi

if ! [[ " ${distributions//$'\n'/ } " == *" $distribution "* ]]; then
  echo "JDK distribution \"$distribution\" from $distribution_source isn't one actions/setup-java installs:" \
    "${distributions//$'\n'/ }" >&2
  exit 1
fi

printf 'java-distribution=%s\njava-version=%s\n' "$distribution" "$version"
