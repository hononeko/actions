#!/usr/bin/env bash
# Runs actionlint on the repository's workflows and annotates its findings. Uses the repository's
# .github/actionlint.yaml, or else this action's own, which knows the ubuntu-26.04 runners.
#
# Usage: actionlint.sh
#   ACTIONLINT_IMAGE  the actionlint image to run
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(git rev-parse --show-toplevel)
# shellcheck disable=SC2016 # a Go template, not shell
format='{{range $err := .}}::error file={{$err.Filepath}},line={{$err.Line}},col={{$err.Column}},title=actionlint {{$err.Kind}}::{{$err.Message}}\n{{end}}'

args=(-format "$format")
if [ ! -f "$root/.github/actionlint.yaml" ] && [ ! -f "$root/.github/actionlint.yml" ]; then
  args+=(-config-file /action/actionlint.yaml)
fi
docker run --rm -v "$root:/repo:ro" -v "$here:/action:ro" -w /repo "${ACTIONLINT_IMAGE:?}" "${args[@]}"
