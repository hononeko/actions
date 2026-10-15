#!/usr/bin/env bash
# Runs release-notes.sh against a throwaway repository and compares its notes with the expected Markdown.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/release-notes/release-notes.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cd "$work"
git init -q -b main
git config user.name test
git config user.email test@example.com
git config commit.gpgsign false
git config tag.gpgsign false

commit() { git commit -q --allow-empty -m "$1" ${2:+-m "$2"}; }

commit "feat: first release"
git tag v1.0.0
commit "feat(ui): add a dark theme (#12)"
commit "fix: handle empty input (#13)"
commit "ci(cd): cache the Go build (#14)"
commit "chore(deps): update module foo to v2 (#15)"
commit "docs: explain the config"
commit "feat(api)!: drop the v1 endpoints (#16)"
commit "refactor: split the parser (#17)" "BREAKING CHANGE: the parser package moved"
commit "test: cover the parser"

export GITHUB_REPOSITORY=owner/repo
unset GH_TOKEN

check() {
  local name=$1 expected=$2
  shift 2
  local actual
  actual=$("$script" "$@")
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $name"
    diff <(echo "$expected") <(echo "$actual") || true
    exit 1
  fi
  echo "ok: $name"
}

check "groups commits since the last release" "$(
  cat <<EOF
## 💥 Breaking changes

* feat(api)!: drop the v1 endpoints #16
* refactor: split the parser #17

## 🚀 Features

* feat(ui): add a dark theme #12

## 🐛 Bug fixes

* fix: handle empty input #13

## 👷 CI

* ci(cd): cache the Go build #14

## 📦 Others

* chore(deps): update module foo to v2 #15
* docs: explain the config $(git rev-parse --short=7 HEAD~3)
* test: cover the parser $(git rev-parse --short=7 HEAD)

**Full Changelog**: https://github.com/owner/repo/compare/v1.0.0...v2.0.0
EOF
)" v1.0.0 HEAD v2.0.0

check "first release lists every commit and leaves out empty sections" "$(
  cat <<EOF
## 🚀 Features

* feat: first release $(git rev-parse --short=7 v1.0.0)

**Full Changelog**: https://github.com/owner/repo/commits/v1.0.0
EOF
)" "" v1.0.0 v1.0.0

if "$script" no-such-tag HEAD >/dev/null 2>&1; then
  echo "FAIL: a bad range must fail"
  exit 1
fi
echo "ok: a bad range fails"
