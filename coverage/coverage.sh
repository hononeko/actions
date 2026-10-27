#!/usr/bin/env bash
# Measures coverage from Go, JaCoCo/Kover or lcov reports, overall and on the lines changed since a base commit, and
# writes a Markdown report. Run from the directory the tests ran in.
#
# Usage: coverage.sh
#   COVERAGE_FILES        report paths or globs, separated by spaces or newlines (** matches directories)
#   COVERAGE_FORMAT       auto (default), go, jacoco or lcov
#   COVERAGE_BASE         commit to compare with for changed lines; empty for overall coverage only
#   COVERAGE_MIN          minimum overall coverage in percent; empty for none
#   COVERAGE_MIN_CHANGED  minimum coverage of changed lines in percent; empty for none
#   COVERAGE_TITLE        heading of the report (default "Coverage")
#   COVERAGE_REPORT       file to write the Markdown report to (default: stdout)
#
# Writes coverage, covered, total, changed-coverage, changed-covered, changed-total and failure (empty when every
# minimum is met) to $GITHUB_OUTPUT when it's set. Missing a minimum isn't an error here: the action reports first and
# fails after.
set -euo pipefail
shopt -s globstar nullglob

here=$(cd "$(dirname "$0")" && pwd)
fail() {
  echo "::error title=coverage::$1" >&2
  exit 1
}

format=${COVERAGE_FORMAT:-auto}
base=${COVERAGE_BASE-}
min=${COVERAGE_MIN-}
min_changed=${COVERAGE_MIN_CHANGED-}
title=${COVERAGE_TITLE:-Coverage}
[[ $format =~ ^(auto|go|jacoco|lcov)$ ]] || fail "format must be auto, go, jacoco or lcov, got '$format'"
for m in "$min" "$min_changed"; do
  [ -z "$m" ] || [[ $m =~ ^(100(\.0+)?|[0-9]{1,2}(\.[0-9]+)?)$ ]] || fail "A minimum must be a percentage from 0 to 100, got '$m'"
done
[ -z "$base" ] || [[ $base =~ ^[0-9a-f]{40,64}$ ]] || fail "base must be a full commit SHA, got '$base'"

top=$(git rev-parse --show-toplevel 2>/dev/null) || fail "$PWD isn't in a git repository"
prefix=$(git rev-parse --show-prefix)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Reports
read -ra patterns <<<"$(tr '\n' ' ' <<<"${COVERAGE_FILES-}")"
[ "${#patterns[@]}" -gt 0 ] || fail "No coverage reports given"
reports=()
for pattern in "${patterns[@]}"; do
  # shellcheck disable=SC2206 # the pattern is globbed on purpose; it has no spaces after splitting
  matches=($pattern)
  [ "${#matches[@]}" -gt 0 ] || fail "No coverage report matches '$pattern' in ${prefix:-the repository root}"
  reports+=("${matches[@]}")
done

detect() {
  local first
  first=$(grep -m 1 -v '^[[:space:]]*$' "$1" || true)
  case $first in
    mode:*) echo go ;;
    "<?xml"* | "<report"* | "<!DOCTYPE report"*) echo jacoco ;;
    TN:* | SF:*) echo lcov ;;
    *) fail "Can't tell the format of $1; set format" ;;
  esac
}

module=""
kinds=" "
for report in "${reports[@]}"; do
  kind=$format
  [ "$kind" != auto ] || kind=$(detect "$report")
  [[ $kinds == *" $kind "* ]] || kinds="$kinds$kind "
  # Go is measured by statement, the others by line: the two can't be added up.
  [[ $kinds != *" go "* || $kinds == " go " ]] ||
    fail "Go profiles can't be combined with other reports; run coverage once for each"
  case $kind in
    go)
      if [ -z "$module" ] && [ -f go.mod ]; then
        module=$(awk '$1 == "module" { print $2; exit }' go.mod)
      fi
      awk -v module="$module" -v prefix="$prefix" -f "$here/go.awk" "$report"
      ;;
    jacoco) awk -f "$here/jacoco.awk" "$report" ;;
    lcov) awk -v top="$top" -v prefix="$prefix" -f "$here/lcov.awk" "$report" ;;
  esac
  echo "Read $report ($kind)" >&2
done >"$tmp/records"

# Changed lines: since where HEAD left the base. With full history that's their merge base. On a pull request's merge
# commit checked out shallow (actions/checkout's default), it's the merge commit's first parent, the base branch.
: >"$tmp/changed"
if [ -n "$base" ]; then
  git cat-file -e "$base^{commit}" 2>/dev/null || git fetch -q --no-tags --depth=1 origin "$base" ||
    fail "Can't fetch the base commit $base"
  if ! from=$(git merge-base "$base" HEAD 2>/dev/null); then
    mapfile -t parents < <(git cat-file -p HEAD | awk '/^parent / { print $2 } /^$/ { exit }')
    [ "${#parents[@]}" -ge 2 ] ||
      fail "Can't tell which lines changed since $base: check out with fetch-depth: 0, or the pull request's merge commit"
    from=${parents[0]}
    git cat-file -e "$from^{commit}" 2>/dev/null || git fetch -q --no-tags --depth=1 origin "$from" ||
      fail "Can't fetch the merge commit's parent $from"
  fi
  git -C "$top" -c core.quotePath=false diff --no-color --no-ext-diff --unified=0 --diff-filter=AMR \
    --src-prefix=a/ --dst-prefix=b/ "$from" HEAD | awk -f "$here/changed.awk" >"$tmp/changed"
fi

awk -f "$here/summary.awk" "$tmp/records" "$tmp/changed" >"$tmp/summary"

read -r _ kind covered total < <(grep '^TOTAL' "$tmp/summary")
read -r _ changed_covered changed_total < <(grep '^CHANGED' "$tmp/summary")
[ "$total" -gt 0 ] || fail "The coverage reports have nothing to cover: ${reports[*]}"

pct() { awk -v c="$1" -v t="$2" 'BEGIN { printf "%.2f", c * 100 / t }'; }
below() { awk -v c="$1" -v t="$2" -v m="$3" 'BEGIN { exit !(c * 100 < m * t) }'; }

coverage=$(pct "$covered" "$total")
changed_coverage=""
[ "$changed_total" -eq 0 ] || changed_coverage=$(pct "$changed_covered" "$changed_total")

failure=""
if [ -n "$min" ] && below "$covered" "$total" "$min"; then
  failure="Coverage is $coverage%, below the minimum of $min%"
fi
if [ -n "$min_changed" ] && [ -n "$changed_coverage" ] && below "$changed_covered" "$changed_total" "$min_changed"; then
  failure="${failure:+$failure; }Coverage of changed lines is $changed_coverage%, below the minimum of $min_changed%"
fi

# The report goes to fd 3: reopening /dev/stdout would truncate a file it's redirected to.
if [ -n "${COVERAGE_REPORT-}" ]; then exec 3>"$COVERAGE_REPORT"; else exec 3>&1; fi
mark() { if [ -z "$1" ]; then echo "—"; elif below "$2" "$3" "$1"; then echo "$1% ❌"; else echo "$1% ✅"; fi; }
{
  echo "### $title"
  echo
  echo "| | Covered | Total | Coverage | Minimum |"
  echo "|---|--:|--:|--:|--:|"
  echo "| All ${kind} | $covered | $total | **$coverage%** | $(mark "$min" "$covered" "$total") |"
  if [ -z "$base" ]; then
    :
  elif [ "$changed_total" -eq 0 ]; then
    echo "| Changed lines | – | 0 | no coverable lines changed | — |"
  else
    echo "| Changed lines | $changed_covered | $changed_total | **$changed_coverage%** | $(mark "$min_changed" "$changed_covered" "$changed_total") |"
  fi
  if grep -q '^UNCOVERED' "$tmp/summary"; then
    echo
    echo "<details><summary>Uncovered changed lines</summary>"
    echo
    grep '^UNCOVERED' "$tmp/summary" | head -n 50 | while IFS=$'\t' read -r _ file lines; do
      echo "- \`$file\`: $lines"
    done
    more=$(($(grep -c '^UNCOVERED' "$tmp/summary") - 50))
    [ "$more" -le 0 ] || echo "- and $more more files"
    echo
    echo "</details>"
  fi
} >&3

if [ -n "${GITHUB_OUTPUT-}" ]; then
  {
    echo "coverage=$coverage"
    echo "covered=$covered"
    echo "total=$total"
    echo "changed-coverage=$changed_coverage"
    echo "changed-covered=$changed_covered"
    echo "changed-total=$changed_total"
    echo "failure=$failure"
  } >>"$GITHUB_OUTPUT"
fi
echo "Coverage: $coverage% of $kind ($covered/$total)${changed_coverage:+, changed lines: $changed_coverage% ($changed_covered/$changed_total)}" >&2
