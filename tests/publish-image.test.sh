#!/usr/bin/env bash
# Runs publish-image.sh and comment.sh against stand-ins for docker and gh, checking what they would push or post, and
# that malformed input fails before anything is pushed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
publish="$root/publish-image/publish-image.sh"
comment="$root/publish-image/comment.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

amd64=1111111111111111111111111111111111111111111111111111111111111111
arm64=2222222222222222222222222222222222222222222222222222222222222222
joined=sha256:3333333333333333333333333333333333333333333333333333333333333333

# docker logs its arguments, one call per line, and answers inspect with the joined image's digest.
mkdir -p "$work/bin"
cat >"$work/bin/docker" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$work/docker.log"
if [ "\$3" = inspect ]; then echo '{"digest":"$joined"}'; fi
EOF
# gh logs its arguments; listing comments prints STUB_COMMENT_ID when set, like an existing comment would.
cat >"$work/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$work/gh.log"
if [ "\$2" = --paginate ] && [ -n "\${STUB_COMMENT_ID-}" ]; then echo "\$STUB_COMMENT_ID"; fi
EOF
chmod +x "$work/bin/docker" "$work/bin/gh"
export PATH="$work/bin:$PATH"

pass() { echo "ok   $1"; }
fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}

# expect <name> <shown on failure> <command>...: passes when the command succeeds
expect() {
  local name=$1 detail=$2
  shift 2
  if "$@"; then pass "$name"; else fail "$name" "$detail"; fi
}

# digests <dir> <name>...: creates the digest files publish-image.sh reads
digests() {
  local dir="$work/$1"
  shift
  mkdir -p "$dir"
  for name in "$@"; do touch "$dir/$name"; done
  printf '%s' "$dir"
}

# publish_fails <name> <expected error substring> <image> <dir> [tags] [expected digests]
publish_fails() {
  local name=$1 expected=$2 actual
  rm -f "$work/docker.log"
  if actual=$(PUBLISH_TAGS=${5-v1} PUBLISH_EXPECTED_DIGESTS=${6-} "$publish" "$3" "$4" 2>&1); then
    fail "$name" "expected a failure, got '$actual'"
  elif [[ $actual != *"$2"* ]]; then
    fail "$name" "expected an error containing '$expected', got '$actual'"
  elif [ -e "$work/docker.log" ]; then
    fail "$name" "pushed before failing: $(cat "$work/docker.log")"
  else
    pass "$name"
  fi
}

# Publishes both architectures under two tags.
two=$(digests two "$amd64" "$arm64")
rm -f "$work/docker.log"
export GITHUB_OUTPUT="$work/output" GITHUB_STEP_SUMMARY="$work/summary"
out=$(PUBLISH_TAGS=$'pr-12-sha-1a2b3c4\npr-12' PUBLISH_EXPECTED_DIGESTS=2 "$publish" ghcr.io/owner/app "$two")
expected_create="buildx imagetools create -t ghcr.io/owner/app:pr-12-sha-1a2b3c4 -t ghcr.io/owner/app:pr-12 ghcr.io/owner/app@sha256:$amd64 ghcr.io/owner/app@sha256:$arm64"
created=$(head -n 1 "$work/docker.log")
expect "joins every digest under every tag" "$created" test "$created" = "$expected_create"
expect "prints the reference" "$out" test "$out" = "ghcr.io/owner/app:pr-12-sha-1a2b3c4@$joined"
expect "writes the digest output" "$(cat "$work/output")" grep -qx "digest=$joined" "$work/output"
expect "writes the reference output" "$(cat "$work/output")" grep -qx "reference=$out" "$work/output"
expect "writes the summary" "$(cat "$work/summary")" grep -qF "\`$out\`" "$work/summary"
unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY

# Any number of digests is fine without expected-digests; a registry with a port is a valid name.
one=$(digests one "$amd64")
if out=$(PUBLISH_TAGS=edge "$publish" localhost:5000/team/app "$one" 2>&1); then pass "registry with a port"; else
  fail "registry with a port" "$out"
fi

publish_fails "wrong number of digests" "Expected 2 digests, got 1" ghcr.io/owner/app "$one" v1 2
publish_fails "no digests" "No digests" ghcr.io/owner/app "$(digests empty)"
publish_fails "malformed digest" "isn't a sha256 digest" ghcr.io/owner/app "$(digests bad "$amd64" nope)"
publish_fails "uppercase image" "isn't an image name" ghcr.io/Owner/app "$two"
publish_fails "image without a path" "isn't an image name" app "$two"
publish_fails "no tags" "No tags" ghcr.io/owner/app "$two" ""
publish_fails "tag with a colon" "isn't a valid image tag" ghcr.io/owner/app "$two" "v1 a:b"
# A "*" must be rejected as a tag, not expanded to the files in the current directory.
(cd "$work/two" && publish_fails "unexpanded glob" "'*' isn't a valid image tag" ghcr.io/owner/app "$two" "*")

# Comments: a new one when there's none yet, the same one updated afterwards.
export GITHUB_REPOSITORY=owner/repo GH_TOKEN=test
rm -f "$work/gh.log"
"$comment" 12 "ghcr.io/owner/app:pr-12@$joined" >/dev/null
if grep -q '^api -X POST repos/owner/repo/issues/12/comments -f body=<!-- hononeko/actions:publish-image -->' "$work/gh.log"; then
  pass "adds a comment"
else
  fail "adds a comment" "$(cat "$work/gh.log")"
fi
rm -f "$work/gh.log"
STUB_COMMENT_ID=987 COMMENT_NOTE="Deleted when this pull request closes." "$comment" 12 "ghcr.io/owner/app:pr-12@$joined" >/dev/null
if grep -q '^api -X PATCH repos/owner/repo/issues/comments/987 ' "$work/gh.log" && ! grep -q POST "$work/gh.log" &&
  grep -q 'Deleted when this pull request closes.' "$work/gh.log"; then
  pass "updates its comment"
else
  fail "updates its comment" "$(cat "$work/gh.log")"
fi
if out=$("$comment" "12; rm -rf /" ref 2>&1); then fail "rejects a malformed pr-number" "$out"; else
  pass "rejects a malformed pr-number"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
