#!/usr/bin/env bash
# Runs smoke-test.sh against stand-ins for docker and curl, checking startup probing, crash detection,
# dynamic port binding, and memory validation.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
smoke="$root/smoke-test/smoke-test.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

mkdir -p "$work/bin"

cat >"$work/bin/docker" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$work/docker.log"
case "\$1" in
  image)
    if [ "\${4-}" = "{{.Architecture}}" ]; then
      echo "amd64"
    else
      echo '{"Architecture":"amd64"}'
    fi
    ;;
  inspect)
    if [ "\${3-}" = "{{.State.Running}}" ]; then
      if [ -f "$work/settle_crash" ] && [ -f "$work/curl_succeeded" ]; then
        echo "false"
      elif [ -s "$work/inspect_running" ]; then
        val=\$(head -n 1 "$work/inspect_running")
        sed -i '1d' "$work/inspect_running"
        echo "\$val"
      else
        echo "true"
      fi
    fi
    ;;
  port)
    if [ -f "$work/port_fail" ]; then
      exit 1
    elif [ -s "$work/port_output" ]; then
      cat "$work/port_output"
    else
      echo "127.0.0.1:49153"
    fi
    ;;
  stats)
    if [ -s "$work/stats_output" ]; then
      cat "$work/stats_output"
    else
      echo "24.5MiB / 100MiB"
    fi
    ;;
  logs)
    if [ -s "$work/logs_output" ]; then
      cat "$work/logs_output"
    else
      echo "Started Application in 1.234 seconds"
    fi
    ;;
  run|pull|rm)
    exit 0
    ;;
esac
EOF

cat >"$work/bin/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$work/curl.log"
val="200"
if [ -s "$work/curl_status" ]; then
  val=\$(head -n 1 "$work/curl_status")
  sed -i '1d' "$work/curl_status"
fi
if [[ \$val =~ ^2 ]]; then
  touch "$work/curl_succeeded"
fi
echo "\$val"
EOF

cat >"$work/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$work/bin/docker" "$work/bin/curl" "$work/bin/sleep"
export PATH="$work/bin:$PATH"

pass() { echo "ok   $1"; }
fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}

expect() {
  local name=$1 detail=$2
  shift 2
  if "$@"; then pass "$name"; else fail "$name" "$detail"; fi
}

reset_state() {
  rm -f "$work"/docker.log "$work"/curl.log "$work"/curl_succeeded "$work"/settle_crash \
    "$work"/inspect_running "$work"/curl_status "$work"/port_fail "$work"/port_output \
    "$work"/stats_output "$work"/logs_output "$work"/summary
}

smoke_fails() {
  local name=$1 expected=$2
  shift 2
  local actual
  if actual=$("$@" "$smoke" test-image 2>&1); then
    fail "$name" "expected a failure, got '$actual'"
  elif [[ $actual != *"$expected"* ]]; then
    fail "$name" "expected an error containing '$expected', got '$actual'"
  else
    pass "$name"
  fi
}

# Happy path
reset_state
export GITHUB_STEP_SUMMARY="$work/summary"
out=$("$smoke" ghcr.io/owner/app:v1)
expect "happy path succeeds" "$out" test -n "$out"
expect "reports status and memory" "$out" grep -q "HTTP 200 after .* memory: 24.5 MiB (amd64)" <<<"$out"
expect "binds ephemeral port on 127.0.0.1" "$(cat "$work/docker.log")" grep -q -- "-p 127.0.0.1::8080" "$work/docker.log"
expect "curls bound dynamic host port" "$(cat "$work/curl.log")" grep -q "http://127.0.0.1:49153/" "$work/curl.log"
expect "writes step summary" "$(cat "$work/summary")" grep -q "### Smoke test: ghcr.io/owner/app:v1" "$work/summary"
unset GITHUB_STEP_SUMMARY

# Custom port, path, and startup regex
reset_state
echo "127.0.0.1:54321" >"$work/port_output"
echo "Application started in 0.42 seconds" >"$work/logs_output"
out=$(env SMOKE_PORT=9090 SMOKE_PATH=/healthz SMOKE_STARTED_REGEX='Application started in [0-9.]+ seconds' "$smoke" test-image)
expect "custom port passed to docker" "$(cat "$work/docker.log")" grep -q -- "-p 127.0.0.1::9090" "$work/docker.log"
expect "custom path and port queried by curl" "$(cat "$work/curl.log")" grep -q "http://127.0.0.1:54321/healthz" "$work/curl.log"
expect "startup time extracted" "$out" grep -q "app startup: 0.42 s" <<<"$out"

# Memory limit exceeded
reset_state
smoke_fails "memory limit exceeded" "uses 24.5 MiB after startup, above the 10 MiB limit" env SMOKE_MAX_MEMORY_MIB=10

# Container crash before answering
reset_state
echo "false" >"$work/inspect_running"
echo "000" >"$work/curl_status"
echo "fatal: container crashed during initialization" >"$work/logs_output"
out=$("$smoke" test-image 2>&1 || true)
expect "crash before answering reports error" "$out" grep -q "::error::test-image exited before / answered" <<<"$out"
expect "crash before answering dumps logs" "$out" grep -q "fatal: container crashed during initialization" <<<"$out"

# Container crash during settle window
reset_state
touch "$work/settle_crash"
echo "panic: crash during settle window" >"$work/logs_output"
out=$("$smoke" test-image 2>&1 || true)
expect "crash during settle window reports error" "$out" grep -q "::error::test-image exited after startup" <<<"$out"
expect "crash during settle window dumps logs" "$out" grep -q "panic: crash during settle window" <<<"$out"

# Retry on transient status (e.g. 503 then 200)
reset_state
printf "503\n200\n" >"$work/curl_status"
out=$("$smoke" test-image)
expect "retry on transient status succeeds" "$out" grep -q "HTTP 200 after" <<<"$out"
expect "curled twice for transient retry" "$(cat "$work/curl.log")" test "$(wc -l <"$work/curl.log")" -eq 2

# Container crash immediately before docker port
reset_state
touch "$work/port_fail"
echo "false" >"$work/inspect_running"
echo "fatal: exited on run" >"$work/logs_output"
out=$("$smoke" test-image 2>&1 || true)
expect "immediate crash before port bind reports error" "$out" grep -q "::error::test-image exited before / answered" <<<"$out"
expect "immediate crash before port bind dumps logs" "$out" grep -q "fatal: exited on run" <<<"$out"

# Validation checks
reset_state
smoke_fails "non-integer timeout" "timeout must be a positive integer, got 'abc'" env SMOKE_TIMEOUT_S=abc
expect "timeout validation does not run docker" "ran docker before failing" test ! -e "$work/docker.log"

reset_state
smoke_fails "zero timeout" "timeout must be a positive integer, got '0'" env SMOKE_TIMEOUT_S=0
expect "zero timeout does not run docker" "ran docker before failing" test ! -e "$work/docker.log"

reset_state
smoke_fails "negative timeout" "timeout must be a positive integer, got '-5'" env SMOKE_TIMEOUT_S=-5
expect "negative timeout does not run docker" "ran docker before failing" test ! -e "$work/docker.log"

reset_state
smoke_fails "non-numeric max-memory-mib" "max-memory-mib must be a positive number, got 'abc'" env SMOKE_MAX_MEMORY_MIB=abc
expect "max-memory-mib validation does not run docker" "ran docker before failing" test ! -e "$work/docker.log"

reset_state
smoke_fails "negative max-memory-mib" "max-memory-mib must be a positive number, got '-1'" env SMOKE_MAX_MEMORY_MIB=-1
expect "negative max-memory-mib does not run docker" "ran docker before failing" test ! -e "$work/docker.log"

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
