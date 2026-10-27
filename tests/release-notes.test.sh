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
first_sha=$(git rev-parse HEAD)
git tag v1.0.0
commit "feat(ui): add a dark theme (#12)"
commit "fix: handle empty input (#13)"
commit "ci(cd): cache the Go build (#14)"
commit "chore(deps): update module foo to v2 (#15)"
commit "docs: explain the config"
docs_sha=$(git rev-parse HEAD)
commit "feat(api)!: drop the v1 endpoints (#16)"
commit "refactor: split the parser (#17)" "BREAKING CHANGE: the parser package moved"
commit "test: cover the parser"
test_sha=$(git rev-parse HEAD)
commit "feat: describe the rules (#18)" "Mentions type!: and BREAKING CHANGE: inline, which isn't a footer."
commit "fix!(legacy): old bang placement (#19)"
commit "chore: rename the config (#20)" "BREAKING-CHANGE: config.yml is now settings.yml"
commit "feat(parser): add support (nested parens): foo (#21)"
commit "fix(parser): handle error (nested parens): bar (#22)"
commit "ci(workflow): matrix support (nested parens): baz (#23)"

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
* fix!(legacy): old bang placement #19
* chore: rename the config #20

## 🚀 Features

* feat(ui): add a dark theme #12
* feat: describe the rules #18
* feat(parser): add support (nested parens): foo #21

## 🐛 Bug fixes

* fix: handle empty input #13
* fix(parser): handle error (nested parens): bar #22

## 👷 CI

* ci(cd): cache the Go build #14
* ci(workflow): matrix support (nested parens): baz #23

## 📦 Others

* chore(deps): update module foo to v2 #15
* docs: explain the config ${docs_sha:0:7}
* test: cover the parser ${test_sha:0:7}

**Full Changelog**: https://github.com/owner/repo/compare/v1.0.0...v2.0.0
EOF
)" v1.0.0 HEAD v2.0.0

check "first release lists every commit and leaves out empty sections" "$(
  cat <<EOF
## 🚀 Features

* feat: first release ${first_sha:0:7}

**Full Changelog**: https://github.com/owner/repo/commits/v1.0.0
EOF
)" "" v1.0.0 v1.0.0

check "defaults to short sha when tag is omitted" "$(
  cat <<EOF
## 🚀 Features

* feat: first release ${first_sha:0:7}

**Full Changelog**: https://github.com/owner/repo/commits/${first_sha:0:7}
EOF
)" "" v1.0.0

# A repository releasing several things: only the commits under the given path, and every commit without one.
git tag v2.0.0
mkdir -p images/a images/b
echo a >images/a/Dockerfile
git add images/a && git commit -q -m "feat(a): add image a (#30)"
echo b >images/b/Dockerfile
git add images/b && git commit -q -m "feat(b): add image b (#31)"
echo a2 >>images/a/Dockerfile
git add images/a && git commit -q -m "fix(a): pin the base (#32)"

check "only the commits under the change path" "$(
  cat <<EOF
## 🚀 Features

* feat(a): add image a #30

## 🐛 Bug fixes

* fix(a): pin the base #32

**Full Changelog**: https://github.com/owner/repo/compare/v2.0.0...a-1.0.0
EOF
)" v2.0.0 HEAD a-1.0.0 images/a

check "every commit without a change path" "$(
  cat <<EOF
## 🚀 Features

* feat(a): add image a #30
* feat(b): add image b #31

## 🐛 Bug fixes

* fix(a): pin the base #32

**Full Changelog**: https://github.com/owner/repo/compare/v2.0.0...v2.1.0
EOF
)" v2.0.0 HEAD v2.1.0 ""

if "$script" no-such-tag HEAD >/dev/null 2>&1; then
  echo "FAIL: a bad range must fail"
  exit 1
fi
echo "ok: a bad range fails"
