#!/usr/bin/env bash
# Prints hadolint's JSON results as GitHub annotations: errors as errors, warnings as warnings, the rest as notices.
#
# Usage: annotations.sh <results.json>
set -euo pipefail

results=${1:?usage: annotations.sh <results.json>}
[ -s "$results" ] || exit 0

# Workflow commands need %, CR and LF escaped in the message, and also , and : in properties.
jq -r '
  def data: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
  def prop: data | gsub(":"; "%3A") | gsub(","; "%2C");
  .[] |
  (if .level == "error" then "error" elif .level == "warning" then "warning" else "notice" end) as $kind |
  "::\($kind) file=\(.file | prop),line=\(.line),col=\(.column),title=\("hadolint \(.code)" | prop)::\(.message | data)"
' "$results"
