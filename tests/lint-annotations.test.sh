#!/usr/bin/env bash
# Checks that detekt's SARIF and hadolint's JSON become GitHub annotations, with workflow-command characters escaped.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
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

cat >"$work/detekt.sarif" <<'EOF'
{"runs": [{"tool": {"driver": {"name": "detekt"}}, "results": [
  {"ruleId": "detekt.style.MagicNumber", "level": "warning", "message": {"text": "Magic: 100%, a, b"},
   "locations": [{"physicalLocation": {"artifactLocation": {"uri": "src/main/kotlin/A.kt"},
                                       "region": {"startLine": 3, "startColumn": 7}}}]},
  {"ruleId": "detekt.x:y,z", "level": "error", "message": {"text": "two\nlines"},
   "locations": [{"physicalLocation": {"artifactLocation": {"uri": "file://B,1.kt"}, "region": {"startLine": 1}}}]},
  {"ruleId": "detekt.Project", "message": {"text": "no location"}}
]}]}
EOF
check "sarif" "$("$root/lint-kotlin/sarif-annotations.sh" "$work/detekt.sarif")" \
  '::warning file=src/main/kotlin/A.kt,line=3,col=7,title=detekt detekt.style.MagicNumber::Magic: 100%25, a, b
::error file=B%2C1.kt,line=1,title=detekt detekt.x%3Ay%2Cz::two%0Alines
::warning title=detekt detekt.Project::no location'

echo '{"runs": [{"tool": {"driver": {"name": "detekt"}}, "results": []}]}' >"$work/clean.sarif"
check "sarif without results" "$("$root/lint-kotlin/sarif-annotations.sh" "$work/clean.sarif")" ""

cat >"$work/hadolint.json" <<'EOF'
[{"code": "DL3007", "column": 1, "file": "Dockerfile", "level": "warning", "line": 1, "message": "Using latest"},
 {"code": "DL3000", "column": 1, "file": "docker/Dockerfile.a", "level": "error", "line": 4, "message": "50% bad"},
 {"code": "DL3066", "column": 2, "file": "Dockerfile", "level": "info", "line": 9, "message": "Non-numeric"},
 {"code": "DL3059", "column": 1, "file": "Dockerfile", "level": "style", "line": 5, "message": "Merge RUNs"}]
EOF
check "hadolint" "$("$root/lint-docker/annotations.sh" "$work/hadolint.json")" \
  '::warning file=Dockerfile,line=1,col=1,title=hadolint DL3007::Using latest
::error file=docker/Dockerfile.a,line=4,col=1,title=hadolint DL3000::50%25 bad
::notice file=Dockerfile,line=9,col=2,title=hadolint DL3066::Non-numeric
::notice file=Dockerfile,line=5,col=1,title=hadolint DL3059::Merge RUNs'

: >"$work/empty.json"
check "hadolint without output" "$("$root/lint-docker/annotations.sh" "$work/empty.json")" ""

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
