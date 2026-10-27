#!/usr/bin/env bash
# Checks coverage's totals and changed-line coverage for each report format, against throwaway repositories, and that
# bad input fails.
# shellcheck disable=SC2016 # the expected reports have Markdown code spans in single quotes
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/coverage/coverage.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else
    echo "FAIL $1"
    echo "  expected: $3"
    echo "  actual:   $2"
    failures=$((failures + 1))
  fi
}
# Runs coverage.sh in a directory with the given environment; prints its outputs, sorted, then the report.
run() {
  local dir=$1
  shift
  : >"$work/output"
  (cd "$dir" && env GITHUB_OUTPUT="$work/output" COVERAGE_REPORT="$work/report.md" "$@" "$script" 2>/dev/null)
}
output() { sed -n "s/^$1=//p" "$work/output"; }
rejects() {
  local name=$1 dir=$2 out
  shift 2
  if out=$(cd "$dir" && env "$@" "$script" 2>&1); then
    echo "FAIL accepted $name: $out"
    failures=$((failures + 1))
  else
    echo "ok   rejects $name"
  fi
}
lines() { for i in $(seq "$1"); do echo "line $i"; done; }
new_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
}
commit() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }
# Rewrites lines of a file: edit <file> <line>...
edit() {
  local file=$1 l
  shift
  for l in "$@"; do sed -i "${l}s/\$/ changed/" "$file"; done
}

# Go: statements overall, and the lines of changed blocks. The module path is swapped for the module's directory.
repo=$work/go
new_repo "$repo"
mkdir -p "$repo/pkg"
echo "module example.com/m" >"$repo/go.mod"
lines 11 >"$repo/pkg/calc.go"
commit "$repo" base
base=$(git -C "$repo" rev-parse HEAD)
edit "$repo/pkg/calc.go" 4 8 11
commit "$repo" change
cat >"$repo/coverage.out" <<'EOF'
mode: set
example.com/m/pkg/calc.go:3.20,5.2 2 1
example.com/m/pkg/calc.go:7.20,9.2 1 0
EOF
run "$repo" COVERAGE_FILES=coverage.out COVERAGE_BASE="$base"
check "go: overall" "$(output coverage) $(output covered)/$(output total)" "66.67 2/3"
check "go: changed lines" "$(output changed-coverage) $(output changed-covered)/$(output changed-total)" "50.00 1/2"
check "go: uncovered changed lines" "$(grep -F 'pkg/calc.go' "$work/report.md")" '- `pkg/calc.go`: 8'
check "go: measured by statement" "$(grep -c '| All statements |' "$work/report.md")" 1

# JaCoCo on one line, as Gradle writes it. Its paths are the package's, matched to the repository's files by suffix:
# dev/y/Foo.kt isn't dev/x/Foo.kt.
repo=$work/jacoco
new_repo "$repo"
mkdir -p "$repo/src/main/kotlin/dev/x" "$repo/src/main/kotlin/dev/y" "$repo/build"
lines 8 >"$repo/src/main/kotlin/dev/x/Foo.kt"
lines 8 >"$repo/src/main/kotlin/dev/y/Foo.kt"
commit "$repo" base
base=$(git -C "$repo" rev-parse HEAD)
edit "$repo/src/main/kotlin/dev/x/Foo.kt" 4 5 6
edit "$repo/src/main/kotlin/dev/y/Foo.kt" 3 4
commit "$repo" change
printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.1//EN" "report.dtd"><report name="r"><package name="dev/x"><class name="dev/x/Foo" sourcefilename="Foo.kt"><counter type="LINE" missed="1" covered="2"/></class><sourcefile name="Foo.kt"><line nr="3" mi="0" ci="4" mb="0" cb="0"/><line nr="4" mi="2" ci="0" mb="0" cb="0"/><line nr="5" mi="1" ci="1" mb="1" cb="1"/><line nr="6" mi="0" ci="0" mb="0" cb="0"/></sourcefile></package></report>' \
  >"$repo/build/jacoco.xml"
run "$repo" COVERAGE_FILES="build/**/*.xml" COVERAGE_BASE="$base" COVERAGE_MIN=70 COVERAGE_MIN_CHANGED=50
check "jacoco: overall" "$(output coverage) $(output covered)/$(output total)" "66.67 2/3"
check "jacoco: changed lines" "$(output changed-coverage) $(output changed-covered)/$(output changed-total)" "50.00 1/2"
check "jacoco: uncovered changed lines" "$(grep '^- ' "$work/report.md")" '- `src/main/kotlin/dev/x/Foo.kt`: 4'
check "jacoco: below the overall minimum" "$(output failure)" "Coverage is 66.67%, below the minimum of 70%"
check "jacoco: minimums in the report" "$(grep -c '70% ❌' "$work/report.md") $(grep -c '50% ✅' "$work/report.md")" "1 1"

# lcov, relative to the working directory or absolute; the same line in two reports is covered if either covers it.
repo=$work/lcov
new_repo "$repo"
mkdir -p "$repo/web/src"
lines 6 >"$repo/web/src/app.ts"
lines 6 >"$repo/web/src/util.ts"
commit "$repo" base
base=$(git -C "$repo" rev-parse HEAD)
edit "$repo/web/src/app.ts" 2 3 4 5
edit "$repo/web/src/util.ts" 1
commit "$repo" change
printf 'TN:\nSF:./src/app.ts\nDA:1,1\nDA:2,0\nDA:3,0\nDA:4,0\nDA:5,3\nend_of_record\n' >"$repo/web/a.info"
printf 'TN:\nSF:%s/web/src/app.ts\nDA:3,2\nend_of_record\nSF:%s/web/src/util.ts\nDA:1,0\nend_of_record\n' \
  "$repo" "$repo" >"$repo/web/b.info"
run "$repo/web" COVERAGE_FILES=$'a.info\nb.info' COVERAGE_BASE="$base" COVERAGE_MIN_CHANGED=60
check "lcov: overall" "$(output coverage) $(output covered)/$(output total)" "50.00 3/6"
check "lcov: changed lines" "$(output changed-coverage) $(output changed-covered)/$(output changed-total)" "40.00 2/5"
check "lcov: uncovered changed lines, in ranges" "$(grep '^- ' "$work/report.md")" \
  $'- `web/src/app.ts`: 2, 4\n- `web/src/util.ts`: 1'
check "lcov: below the changed minimum" "$(output failure)" "Coverage of changed lines is 40.00%, below the minimum of 60%"

# Without a base, overall only; with one but no coverable line changed, no changed coverage and no failure.
run "$repo/web" COVERAGE_FILES=a.info COVERAGE_MIN_CHANGED=90
check "no base: overall only" "$(output changed-total) [$(output changed-coverage)] [$(output failure)]" "0 [] []"
check "no base: no changed row" "$(grep -c 'Changed lines' "$work/report.md")" 0
run "$repo/web" COVERAGE_FILES=a.info COVERAGE_BASE="$(git -C "$repo" rev-parse HEAD)" COVERAGE_MIN_CHANGED=90
check "nothing changed" "$(output changed-total) [$(output failure)]" "0 []"
check "nothing changed: in the report" "$(grep -c 'no coverable lines changed' "$work/report.md")" 1

# A pull request's merge commit, cloned shallow as actions/checkout does: changed lines come from its first parent.
repo=$work/pr
new_repo "$repo"
lines 6 >"$repo/app.ts"
commit "$repo" base
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" switch -q -c feature
edit "$repo/app.ts" 2
commit "$repo" feature
git -C "$repo" switch -q main
edit "$repo/app.ts" 5
commit "$repo" "main moves on"
git -C "$repo" switch -q -c merge
git -C "$repo" merge -q --no-edit feature >/dev/null
git clone -q --depth=1 --branch=merge "file://$repo" "$work/pr-merge"
printf 'SF:app.ts\nDA:2,0\nDA:5,0\nend_of_record\n' >"$work/pr-merge/lcov.info"
run "$work/pr-merge" COVERAGE_FILES=lcov.info COVERAGE_BASE="$(git -C "$repo" rev-parse main)"
check "shallow merge commit: only the pull request's lines" "$(grep '^- ' "$work/report.md")" '- `app.ts`: 2'

# The pull request's head, shallow: there's no telling where it branched off.
git clone -q --depth=1 --branch=feature "file://$repo" "$work/pr-head"
cp "$work/pr-merge/lcov.info" "$work/pr-head/"
rejects "a shallow branch head" "$work/pr-head" COVERAGE_FILES=lcov.info COVERAGE_BASE="$base"

rejects "an unknown format" "$repo" COVERAGE_FILES=app.ts COVERAGE_FORMAT=cobertura
rejects "an undetectable report" "$repo" COVERAGE_FILES=app.ts
rejects "a missing report" "$repo" COVERAGE_FILES=missing.info
rejects "no reports" "$repo" COVERAGE_FILES=""
rejects "a minimum over 100" "$work/lcov/web" COVERAGE_FILES=a.info COVERAGE_MIN=101
rejects "a minimum that isn't a number" "$work/lcov/web" COVERAGE_FILES=a.info "COVERAGE_MIN_CHANGED=80;x"
rejects "a short base" "$work/lcov/web" COVERAGE_FILES=a.info COVERAGE_BASE=abc1234
rejects "go with another format" "$work/go" COVERAGE_FILES="coverage.out $work/lcov/web/a.info"
printf 'TN:\nend_of_record\n' >"$work/empty.info"
rejects "a report with nothing to cover" "$work/lcov" COVERAGE_FILES="$work/empty.info"

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
