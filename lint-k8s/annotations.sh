#!/usr/bin/env bash
# Prints kustomize stderr, kubeconform JSON, or kube-linter JSON results as GitHub error annotations.
#
# Usage: annotations.sh <kustomize|kubeconform|kube-linter> <file> <results>
set -euo pipefail

tool=${1:?usage: annotations.sh <kustomize|kubeconform|kube-linter> <file> <results>}
file=${2:?usage: annotations.sh <kustomize|kubeconform|kube-linter> <file> <results>}
results=${3:?usage: annotations.sh <kustomize|kubeconform|kube-linter> <file> <results>}

[ -s "$results" ] || exit 0

# Workflow commands need %, CR and LF escaped in the message, and also , and : in properties.
esc='
  def data: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
  def prop: data | gsub(":"; "%3A") | gsub(","; "%2C");
'

case "$tool" in
  kustomize)
    jq -Rsr --arg file "$file" "$esc"'
      sub("\n+$"; "") |
      select(length > 0) |
      "::error file=\($file | prop),title=kustomize::\(data)"
    ' "$results"
    ;;
  kubeconform)
    jq -r --arg file "$file" "$esc"'
      (.resources // [])[] |
      select(.status == "statusInvalid" or .status == "statusError") |
      ([.kind, .name] | map(select(. != null and . != "")) | join("/")) as $target |
      (if $target != "" then "kubeconform \($target)" else "kubeconform" end) as $title |
      "::error file=\($file | prop),title=\($title | prop)::\((.msg // .status // "schema validation failed") | data)"
    ' "$results"
    ;;
  kube-linter)
    jq -r --arg file "$file" "$esc"'
      (.Reports // [])[] |
      (.Object.K8sObject.GroupVersionKind.Kind // "") as $kind |
      (.Object.K8sObject.Namespace // "") as $ns |
      (.Object.K8sObject.Name // "") as $name |
      ([$kind, $ns, $name] | map(select(. != "")) | join("/")) as $target |
      (if $target != "" then "\($target): " else "" end) as $prefix |
      (.Remediation // "") as $rem |
      (if $rem != "" then " — \($rem)" else "" end) as $suffix |
      ($prefix + (.Diagnostic.Message // "lint check failed") + $suffix) as $msg |
      "::error file=\($file | prop),title=\("kube-linter \(.Check // "finding")" | prop)::\($msg | data)"
    ' "$results"
    ;;
  *)
    echo "Unknown tool '$tool' (expected kustomize, kubeconform, or kube-linter)" >&2
    exit 1
    ;;
esac
