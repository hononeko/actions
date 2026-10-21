#!/usr/bin/env bash
# Runs gradle-setup/resolve-version.sh and gradle-setup/wrapper-version.sh against throwaway projects and checks the
# version each resolves, or that it fails.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
java_script="$root/gradle-setup/resolve-version.sh"
wrapper_script="$root/gradle-setup/wrapper-version.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# project <name> [.java-version content] [gradle-wrapper.properties content]: creates $work/<name>
project() {
  local dir="$work/$1"
  mkdir -p "$dir"
  if [ -n "${2-}" ]; then printf '%b' "$2" >"$dir/.java-version"; fi
  if [ -n "${3-}" ]; then
    mkdir -p "$dir/gradle/wrapper"
    printf '%b' "$3" >"$dir/gradle/wrapper/gradle-wrapper.properties"
  fi
  printf '%s' "$dir"
}

pass() {
  echo "ok   $1"
}

fail() {
  echo "FAIL $1"
  failures=$((failures + 1))
}

# jdk <distribution> <version>: the resolve script's output for that pin
jdk() {
  printf 'java-distribution=%s\njava-version=%s' "$1" "$2"
}

# check <name> <script> <dir> <expected stdout> [version input] [distribution input]
check() {
  local name=$1 script=$2 dir=$3 expected=$4 actual
  if ! actual=$(JAVA_VERSION_INPUT=${5-} JAVA_DISTRIBUTION_INPUT=${6-} "$script" "$dir" 2>/dev/null); then
    actual="failed"
  fi
  if [ "$actual" = "$expected" ]; then pass "$name"; else fail "$name: expected '$expected', got '$actual'"; fi
}

# check_fails <name> <script> <dir> <expected error substring> [version input] [distribution input]
check_fails() {
  local name=$1 script=$2 dir=$3 expected=$4 actual
  if actual=$(JAVA_VERSION_INPUT=${5-} JAVA_DISTRIBUTION_INPUT=${6-} "$script" "$dir" 2>&1); then
    fail "$name: expected a failure, got '$actual'"
  elif [[ $actual == *"$expected"* ]]; then
    pass "$name"
  else
    fail "$name: expected an error containing '$expected', got '$actual'"
  fi
}

# check_stderr <name> <script> <dir> <expected stderr substring, or "" for none>
check_stderr() {
  local name=$1 script=$2 dir=$3 expected=$4 stderr
  if ! stderr=$("$script" "$dir" 2>&1 >/dev/null); then
    fail "$name: expected success, got '$stderr'"
  elif [ -z "$expected" ] && [ -z "$stderr" ]; then
    pass "$name"
  elif [ -n "$expected" ] && [[ $stderr == *"$expected"* ]]; then
    pass "$name"
  else
    fail "$name: expected stderr containing '$expected', got '$stderr'"
  fi
}

# JDK version and distribution
pinned=$(project pinned '25.0.1\n')
check "an exact version" "$java_script" "$pinned" "$(jdk temurin 25.0.1)"
check "a feature release" "$java_script" "$(project major '25\n')" "$(jdk temurin 25)"
check "the input wins over the project" "$java_script" "$pinned" "$(jdk temurin 21)" 21
check ".java-version with CRLF and spaces" "$java_script" "$(project crlf '  25.0.1 \r\n')" "$(jdk temurin 25.0.1)"
check "a first GA release" "$java_script" "$(project ga '25.0.0\n')" "$(jdk temurin 25.0.0)"
check "a full Temurin build" "$java_script" "$(project build '25.0.1+8.0.LTS\n')" "$(jdk temurin 25.0.1+8.0.LTS)"
check "an out-of-band patch" "$java_script" "$(project patch '21.0.4.1\n')" "$(jdk temurin 21.0.4.1)"
check "an out-of-band patch with a build" "$java_script" "$(project patch-build 'zulu-17.0.8.1+1\n')" \
  "$(jdk zulu 17.0.8.1+1)"

zulu=$(project zulu 'zulu-25\n')
check "a distribution prefix" "$java_script" "$zulu" "$(jdk zulu 25)"
check "a prefix on an exact version" "$java_script" "$(project tem 'temurin-25.0.1\n')" "$(jdk temurin 25.0.1)"
check "a prefix with a hyphen" "$java_script" "$(project nik 'liberica-nik-25\n')" "$(jdk liberica-nik 25)"
check "a prefix on the input" "$java_script" "$pinned" "$(jdk corretto 21)" corretto-21
check "the distribution input wins over a prefix" "$java_script" "$zulu" "$(jdk corretto 25)" "" corretto
check "the distribution input without a prefix" "$java_script" "$pinned" "$(jdk zulu 25.0.1)" "" zulu

check_fails "nothing pinned" "$java_script" "$(project bare)" "No JDK version pinned"
check_fails "an empty .java-version" "$java_script" "$(project blank '\n')" "No JDK version pinned"
check_fails "a feature and update only" "$java_script" "$(project partial '25.0\n')" 'JDK version "25.0"'
check_fails "a range" "$java_script" "$(project range '25.x\n')" "neither a feature release"
check_fails "latest" "$java_script" "$(project latest 'latest\n')" 'JDK version "latest"'
check_fails "an early-access version" "$java_script" "$(project ea '26-ea\n')" "neither a feature release"
check_fails "a distribution alone" "$java_script" "$(project distonly 'zulu\n')" 'JDK version "zulu"'
check_fails "an invalid input" "$java_script" "$pinned" "from the java-version input" "25.x"
check_fails "an unknown prefix" "$java_script" "$(project unknown 'openjdk-25\n')" \
  "distribution \"openjdk\" from $work/unknown/.java-version"
check_fails "an unknown distribution input" "$java_script" "$pinned" "from the java-distribution input" "" adoptium
check_fails "a local JDK archive" "$java_script" "$pinned" 'distribution "jdkfile"' "" jdkfile
check_fails "five version numbers" "$java_script" "$(project five '21.0.4.1.1\n')" "neither a feature release"
# The distribution is matched literally, never as a glob
check_fails "a wildcard distribution" "$java_script" "$pinned" 'distribution "*"' "" '*'
check_fails "a single-character wildcard distribution" "$java_script" "$pinned" 'distribution "????"' "" '????'

# Gradle wrapper version
checksum='distributionSha256Sum=21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607\n'
wrapper=$(project wrapper '' "${checksum}distributionUrl=https\\\\://services.gradle.org/distributions/gradle-9.8.2-bin.zip\n")
check "the wrapper's version" "$wrapper_script" "$wrapper" 9.8.2
check_stderr "no warning with a checksum" "$wrapper_script" "$wrapper" ""
check "an all distribution" "$wrapper_script" \
  "$(project all '' "${checksum}distributionUrl=https\\\\://services.gradle.org/distributions/gradle-9.8.2-all.zip\n")" 9.8.2
check "a release candidate" "$wrapper_script" \
  "$(project rc '' "${checksum}distributionUrl=https\\\\://services.gradle.org/distributions/gradle-9.9.0-rc-1-bin.zip\n")" \
  9.9.0-rc-1
check "a mirror, a colon separator and CRLF" "$wrapper_script" \
  "$(project mirror '' "${checksum}distributionUrl: https\\\\://mirror.example.com/gradle/gradle-9.8.2-bin.zip\r\n")" 9.8.2
check "trailing whitespace after the URL" "$wrapper_script" \
  "$(project trailing '' "${checksum}distributionUrl=https\\\\://services.gradle.org/distributions/gradle-9.8.2-bin.zip \t\n")" \
  9.8.2
check_stderr "a blank checksum warns" "$wrapper_script" \
  "$(project blank-sum '' 'distributionSha256Sum=   \ndistributionUrl=https\\://services.gradle.org/distributions/gradle-9.8.2-bin.zip\n')" \
  "has no distributionSha256Sum"

unchecked=$(project unchecked '' 'distributionUrl=https\\://services.gradle.org/distributions/gradle-9.8.2-bin.zip\n')
check "a wrapper without a checksum still resolves" "$wrapper_script" "$unchecked" 9.8.2
check_stderr "a wrapper without a checksum warns" "$wrapper_script" "$unchecked" "has no distributionSha256Sum"

check_fails "no wrapper" "$wrapper_script" "$(project nowrapper '25.0.1\n')" "No Gradle wrapper"
check_fails "no distributionUrl" "$wrapper_script" "$(project nourl '' "$checksum")" "No Gradle version in distributionUrl"
check_fails "an unversioned URL" "$wrapper_script" \
  "$(project custom '' 'distributionUrl=https\\://example.com/gradle.zip\n')" "No Gradle version in distributionUrl"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
