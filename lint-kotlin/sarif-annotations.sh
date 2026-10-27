#!/usr/bin/env bash
# Prints a SARIF report's results as GitHub annotations: errors as errors, everything else as warnings.
#
# Usage: sarif-annotations.sh <report.sarif>
set -euo pipefail

report=${1:?usage: sarif-annotations.sh <report.sarif>}

# Workflow commands need %, CR and LF escaped in the message, and also , and : in properties.
jq -r '
  def data: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
  def prop: data | gsub(":"; "%3A") | gsub(","; "%2C");
  .runs[] | .tool.driver.name as $tool | .results[]? |
  (.locations[0].physicalLocation // {}) as $loc |
  (if .level == "error" then "error" else "warning" end) as $level |
  ($loc.artifactLocation.uri // "" | sub("^file://"; "")) as $file |
  "::\($level) " +
  ([ (if $file != "" then "file=\($file | prop)" else empty end),
     ($loc.region.startLine // empty | "line=\(.)"),
     ($loc.region.startColumn // empty | "col=\(.)"),
     "title=\("\($tool) \(.ruleId // "")" | prop)" ] | join(",")) +
  "::\(.message.text // "" | data)"
' "$report"
