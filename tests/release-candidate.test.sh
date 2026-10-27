#!/usr/bin/env bash
# Runs find-release-candidate.sh against stand-ins for docker and gh: the candidate already there, published while it
# waits, and every way it can be missing.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/release-candidate/find-release-candidate.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
digest=sha256:4444444444444444444444444444444444444444444444444444444444444444

# docker: the image exists once $work/exists does; with --format, it prints its digest.
mkdir -p "$work/bin"
cat >"$work/bin/docker" <<EOF
#!/usr/bin/env bash
[ -e "$work/exists" ] || exit 1
case "\$*" in *--format*) echo '{"digest":"$digest"}' ;; *) echo "Name: \$4" ;; esac
EOF
# gh: each call answers with the next line of $work/runs ("<id> <status> <conclusion>", or empty for no run), then
# the last one again. A line ending in "publish" also publishes the image, as the run would.
cat >"$work/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$work/gh.log"
n=\$(wc -l <"$work/gh.log")
line=\$(sed -n "\${n}p" "$work/runs")
[ -n "\$line" ] || [ "\$n" -le "\$(wc -l <"$work/runs")" ] || line=\$(tail -n 1 "$work/runs")
set -- \$line
[ "\${4-}" != publish ] || touch "$work/exists"
[ -z "\${1-}" ] || echo "\$1 \$2 \${3-}"
EOF
chmod +x "$work/bin/docker" "$work/bin/gh"
export PATH="$work/bin:$PATH" GITHUB_REPOSITORY=owner/app RC_POLL=0
sha=0123456789abcdef0123456789abcdef01234567

# scenario <runs...>: resets the stand-ins; each argument is one gh answer
scenario() {
  rm -f "$work/exists" "$work/gh.log"
  printf '%s\n' "$@" >"$work/runs"
}
finds() {
  local name=$1 actual
  if actual=$(RC_SHA=$sha "$script" ghcr.io/owner/app sha-0123456 2>/dev/null) && [ "$actual" = "$digest" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: got '${actual-}'"
    failures=$((failures + 1))
  fi
}
fails() {
  local name=$1 expected=$2 out
  shift 2
  if out=$(env RC_SHA=$sha "$@" "$script" ghcr.io/owner/app sha-0123456 2>&1); then
    echo "FAIL $name: succeeded with '$out'"
    failures=$((failures + 1))
  elif [[ $out != *"$expected"* ]]; then
    echo "FAIL $name: expected '$expected' in '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

scenario ""
touch "$work/exists"
finds "already published"
if [ -e "$work/gh.log" ]; then
  echo "FAIL looked up the workflow anyway"
  failures=$((failures + 1))
else
  echo "ok   no workflow lookup when it's there"
fi

scenario "" "7 queued" "7 in_progress" "7 completed success publish"
finds "waits for the run to appear and finish"

scenario "7 completed failure"
fails "the run failed" "ended in 'failure'"

scenario ""
fails "no run for the commit" "No main.yml run for 0123456" RC_START_TIMEOUT=0

scenario "7 in_progress"
fails "the run doesn't finish in time" "didn't finish within 0 minutes" RC_TIMEOUT=0

scenario "7 completed success"
fails "the run passed without publishing" "main.yml passed for 0123456 without publishing ghcr.io/owner/app:sha-0123456"

for args in "Bad/Image sha-1" "ghcr.io/owner/app sha;1" "ghcr.io/owner/app -x"; do
  # shellcheck disable=SC2086 # split on purpose
  if out=$(RC_SHA=$sha "$script" $args 2>&1); then
    echo "FAIL accepted '$args': $out"
    failures=$((failures + 1))
  else
    echo "ok   rejects '$args'"
  fi
done
if RC_SHA=abc1234 "$script" ghcr.io/owner/app sha-1 >/dev/null 2>&1; then
  echo "FAIL accepted a short sha"
  failures=$((failures + 1))
else echo "ok   rejects a short sha"; fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
