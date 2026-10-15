#!/usr/bin/env bash
# Boots a container image, waits until it answers HTTP, and reports how long that took and how much memory it uses.
#
# Usage: smoke-test.sh <image>
#   SMOKE_PORT            container port to probe (default 8080)
#   SMOKE_PATH            path to request (default /)
#   SMOKE_STATUS          extended regex the HTTP status must match (default 2..)
#   SMOKE_ENV             KEY=VALUE lines passed to the container
#   SMOKE_TIMEOUT_S       fail if it isn't answering after this many seconds (default 10)
#   SMOKE_MAX_MEMORY_MIB  fail if it uses more memory than this once started (default 64)
#   SMOKE_STARTED_REGEX   optional regex whose first number in the logs is the app's own startup time, in seconds
#
# "Time to answer" includes Docker starting the container. Results are printed and, in GitHub Actions, added to the
# job summary.
set -euo pipefail

image=${1:?usage: smoke-test.sh <image>}
port=${SMOKE_PORT:-8080}
path=${SMOKE_PATH:-/}
status_re=${SMOKE_STATUS:-2..}
timeout_s=${SMOKE_TIMEOUT_S:-10}
max_mib=${SMOKE_MAX_MEMORY_MIB:-64}
started_re=${SMOKE_STARTED_REGEX-}
name="smoke-$$"
host_port=18080

env_file=$(mktemp)
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -f "$env_file"
}
trap cleanup EXIT
printf '%s\n' "${SMOKE_ENV-}" | sed '/^[[:space:]]*$/d' > "$env_file"

start_ns=$(date +%s%N)
docker run -d --name "$name" --env-file "$env_file" -p "$host_port:$port" "$image" >/dev/null

url="http://localhost:$host_port$path"
while true; do
  status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "$url" || true)
  if [ "$status" != "000" ] && [ -n "$status" ]; then break; fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]; then
    echo "::error::$image exited before $path answered"
    docker logs "$name"
    exit 1
  fi
  if (( ($(date +%s%N) - start_ns) / 1000000000 >= timeout_s )); then
    echo "::error::$image did not answer $path within ${timeout_s}s"
    docker logs "$name"
    exit 1
  fi
  sleep 0.05
done
ready_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))

if ! [[ $status =~ ^($status_re)$ ]]; then
  echo "::error::$image answered $path with HTTP $status, expected $status_re"
  docker logs "$name"
  exit 1
fi

# Let startup work settle before measuring memory.
sleep 2
usage=$(docker stats --no-stream --format '{{.MemUsage}}' "$name" | awk '{print $1}')
mib=$(awk -v u="$usage" 'BEGIN {
  n = u + 0; unit = u; sub(/^[0-9.]+/, "", unit)
  f = (unit == "GiB") ? 1024 : (unit == "KiB") ? 1 / 1024 : (unit == "B") ? 1 / 1048576 : 1
  printf "%.1f", n * f
}')
started="-"
if [ -n "$started_re" ]; then
  started=$(docker logs "$name" 2>&1 | grep -oE "$started_re" | head -1 | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || true)
  started="${started:-?} s"
fi

arch=$(docker image inspect -f '{{.Architecture}}' "$image")
echo "HTTP $status after ${ready_ms} ms, app startup: $started, memory: ${mib} MiB ($arch)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Smoke test: $image"
    echo "| Arch | Answer | Time to answer | App startup | Memory |"
    echo "|---|---|---|---|---|"
    echo "| $arch | HTTP $status on \`$path\` | $ready_ms ms | $started | $mib MiB |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if awk -v r="$mib" -v m="$max_mib" 'BEGIN { exit !(r > m) }'; then
  echo "::error::$image uses ${mib} MiB after startup, above the ${max_mib} MiB limit"
  exit 1
fi
