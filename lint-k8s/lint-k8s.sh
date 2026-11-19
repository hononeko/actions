#!/usr/bin/env bash
# Renders Kustomize directories, validates them with kubeconform, and lints them with kube-linter.
#
# Usage: lint-k8s.sh
#   K8S_PATHS                   Kustomize directories, separated by spaces or newlines; empty discovers tracked ones
#   K8S_IGNORE_MISSING_SCHEMAS  "true" or "false" (default "true")
#   K8S_SKIP_KINDS              comma-separated Kubernetes kinds to skip in kubeconform (empty for none)
#   K8S_ENABLE_HELM             "true" or "false" (default "false")
#   K8S_KUBELINTER              "true" or "false" (default "true")
#   K8S_KUBELINTER_CONFIG       kube-linter config path relative to repository; empty checks .kube-linter.yaml/.yml
#   KUSTOMIZE_IMAGE             kustomize container image
#   KUBECONFORM_IMAGE           kubeconform container image
#   KUBELINTER_IMAGE            kube-linter container image
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fail() {
  echo "::error title=lint-k8s::$1" >&2
  exit 1
}

check_bool() {
  [ "$2" = "true" ] || [ "$2" = "false" ] || fail "$1 must be 'true' or 'false', got '$2'"
}

ignore_missing=${K8S_IGNORE_MISSING_SCHEMAS:-true}
enable_helm=${K8S_ENABLE_HELM:-false}
kube_linter=${K8S_KUBELINTER:-true}
skip_kinds=${K8S_SKIP_KINDS-}

check_bool "ignore-missing-schemas" "$ignore_missing"
check_bool "enable-helm" "$enable_helm"
check_bool "kube-linter" "$kube_linter"

if [ -n "$skip_kinds" ] && [[ $skip_kinds =~ [[:space:]] ]]; then
  fail "skip-kinds must be comma-separated without whitespace, got '$skip_kinds'"
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "$PWD isn't in a git repository"
cd "$root"

paths=()
if [ -n "${K8S_PATHS-}" ]; then
  read -ra raw_paths <<<"$(tr '\n' ' ' <<<"$K8S_PATHS")"
  for p in "${raw_paths[@]}"; do
    [ "$p" = "/" ] || p=${p%/}
    p=${p#./}
    [ -n "$p" ] || p="."
    [ -d "$p" ] || fail "No Kustomize directory at $p"
    [ -f "$p/kustomization.yaml" ] || [ -f "$p/kustomization.yml" ] ||
      fail "No kustomization.yaml or kustomization.yml in $p"
    paths+=("$p")
  done
else
  mapfile -t kfiles < <(git ls-files -- ':(glob)**/kustomization.yaml' ':(glob)**/kustomization.yml')
  dirs=()
  for f in "${kfiles[@]}"; do
    grep -Eq '^[[:space:]]*kind:[[:space:]]*Component([[:space:]]|#|$)' "$f" && continue
    dirs+=("$(dirname "$f")")
  done
  if [ "${#dirs[@]}" -gt 0 ]; then
    mapfile -t paths < <(printf '%s\n' "${dirs[@]}" | sort -u)
  fi
fi
[ "${#paths[@]}" -gt 0 ] || fail "No Kustomize directories to lint"

kl_config=""
if [ -n "${K8S_KUBELINTER_CONFIG-}" ]; then
  kl_config=${K8S_KUBELINTER_CONFIG#./}
  [ -f "$kl_config" ] || fail "No kube-linter config at $K8S_KUBELINTER_CONFIG"
elif [ -f .kube-linter.yaml ]; then
  kl_config=.kube-linter.yaml
elif [ -f .kube-linter.yml ]; then
  kl_config=.kube-linter.yml
fi

k_args=(build)
[ "$enable_helm" = "true" ] && k_args+=(--enable-helm)

kc_args=(-strict)
[ "$ignore_missing" = "true" ] && kc_args+=(-ignore-missing-schemas)
[ -n "$skip_kinds" ] && kc_args+=(-skip "$skip_kinds")
kc_args+=(-output json -)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

for dir in "${paths[@]}"; do
  prefix=""
  [ "$dir" = "." ] || prefix="$dir/"
  if [ -f "${prefix}kustomization.yaml" ]; then
    file_ref="${prefix}kustomization.yaml"
  else
    file_ref="${prefix}kustomization.yml"
  fi

  echo "Linting $dir" >&2
  rendered="$tmp/rendered.yaml"
  k_err="$tmp/kustomize.err"
  kc_out="$tmp/kubeconform.json"
  kl_out="$tmp/kubelinter.json"

  if ! docker run --rm -v "$root:/repo:ro" -w /repo "${KUSTOMIZE_IMAGE:?}" "${k_args[@]}" "$dir" >"$rendered" 2>"$k_err"; then
    cat "$k_err" >&2
    "$here/annotations.sh" kustomize "$file_ref" "$k_err"
    failed=1
    continue
  fi

  kc_status=0
  docker run --rm -i "${KUBECONFORM_IMAGE:?}" "${kc_args[@]}" <"$rendered" >"$kc_out" || kc_status=$?
  "$here/annotations.sh" kubeconform "$file_ref" "$kc_out"
  if [ "$kc_status" -ne 0 ]; then
    failed=1
  fi

  if [ "$kube_linter" = "true" ]; then
    kl_status=0
    if [ -n "$kl_config" ]; then
      docker run --rm -i -v "$root:/repo:ro" -w /repo "${KUBELINTER_IMAGE:?}" \
        lint --format json --config "/repo/$kl_config" - <"$rendered" >"$kl_out" || kl_status=$?
    else
      docker run --rm -i "${KUBELINTER_IMAGE:?}" \
        lint --format json - <"$rendered" >"$kl_out" || kl_status=$?
    fi
    "$here/annotations.sh" kube-linter "$file_ref" "$kl_out"
    if [ "$kl_status" -ne 0 ]; then
      failed=1
    fi
  fi
done

[ "$failed" -eq 0 ] || fail "Kubernetes manifest linting failed"
