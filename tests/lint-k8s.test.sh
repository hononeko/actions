#!/usr/bin/env bash
# Checks lint-k8s annotation formatting and input/discovery validation.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ann="$root/lint-k8s/annotations.sh"
lint="$root/lint-k8s/lint-k8s.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

pass() { echo "ok   $1"; }
fail() {
  echo "FAIL $1"
  echo "  expected: $2"
  echo "  actual:   $3"
  failures=$((failures + 1))
}

check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}

should_fail() {
  local name=$1 dir=$2 expected=$3 actual
  shift 3
  if actual=$(cd "$dir" && env "$@" "$lint" 2>&1); then
    fail "$name" "failure containing '$expected'" "unexpected pass: $actual"
  elif [[ $actual != *"$expected"* ]]; then
    fail "$name" "$expected" "$actual"
  else
    pass "$name"
  fi
}

# --- annotations.sh: empty ---
: >"$work/empty"
check "kustomize empty stderr" "$("$ann" kustomize k8s/kustomization.yaml "$work/empty")" ""

# --- annotations.sh: kustomize stderr with escaping ---
printf 'Error: bad 100%%\nline two\n' >"$work/kustomize.err"
check "kustomize stderr" "$("$ann" kustomize "k8s,a/kustomization.yaml" "$work/kustomize.err")" \
  '::error file=k8s%2Ca/kustomization.yaml,title=kustomize::Error: bad 100%25%0Aline two'

# --- annotations.sh: kubeconform clean ---
echo '{"resources":[{"filename":"stdin","kind":"Deployment","name":"ok","version":"apps/v1","status":"statusValid"}]}' \
  >"$work/kc-clean.json"
check "kubeconform valid" "$("$ann" kubeconform k8s/kustomization.yaml "$work/kc-clean.json")" ""

# --- annotations.sh: kubeconform invalid + error + escaping ---
cat >"$work/kc-bad.json" <<'EOF'
{"resources":[
  {"filename":"stdin","kind":"Deployment","name":"bad","version":"apps/v1","status":"statusInvalid","msg":"50% bad\nline2"},
  {"filename":"stdin","kind":"","name":"","version":"","status":"statusError","msg":"a:b,c"}
]}
EOF
check "kubeconform findings" "$("$ann" kubeconform k8s/kustomization.yaml "$work/kc-bad.json")" \
  '::error file=k8s/kustomization.yaml,title=kubeconform Deployment/bad::50%25 bad%0Aline2
::error file=k8s/kustomization.yaml,title=kubeconform::a:b,c'

# --- annotations.sh: kube-linter clean (Reports: null) ---
echo '{"Reports":null,"Summary":{"ChecksStatus":"Passed"}}' >"$work/kl-clean.json"
check "kube-linter null Reports" "$("$ann" kube-linter k8s/kustomization.yaml "$work/kl-clean.json")" ""

# --- annotations.sh: kube-linter findings with and without remediation ---
cat >"$work/kl-bad.json" <<'EOF'
{"Reports":[
  {"Check":"latest-tag","Remediation":"Pin tag: 100% required.","Diagnostic":{"Message":"Uses :latest\nfix it"},"Object":{"K8sObject":{"Namespace":"media","Name":"miru","GroupVersionKind":{"Kind":"Deployment"}}}},
  {"Check":"custom","Remediation":"","Diagnostic":{"Message":"Simple error"},"Object":{"K8sObject":{"Namespace":"","Name":"svc","GroupVersionKind":{"Kind":"Service"}}}}
]}
EOF
check "kube-linter findings" "$("$ann" kube-linter k8s/kustomization.yaml "$work/kl-bad.json")" \
  '::error file=k8s/kustomization.yaml,title=kube-linter latest-tag::Deployment/media/miru: Uses :latest%0Afix it — Pin tag: 100%25 required.
::error file=k8s/kustomization.yaml,title=kube-linter custom::Service/svc: Simple error'

# --- lint-k8s.sh: input validation against repo root ---
should_fail "invalid ignore-missing-schemas" "$root" "ignore-missing-schemas must be 'true' or 'false'" \
  K8S_IGNORE_MISSING_SCHEMAS=yes
should_fail "invalid enable-helm" "$root" "enable-helm must be 'true' or 'false'" \
  K8S_ENABLE_HELM=True
should_fail "invalid kube-linter" "$root" "kube-linter must be 'true' or 'false'" \
  K8S_KUBELINTER=nope
should_fail "whitespace in skip-kinds" "$root" "skip-kinds must be comma-separated without whitespace" \
  K8S_SKIP_KINDS="Secret, SealedSecret"
should_fail "missing path" "$root" "No Kustomize directory at tests/fixtures/does-not-exist" \
  K8S_PATHS="tests/fixtures/does-not-exist"
should_fail "dir without kustomization" "$root" "No kustomization.yaml or kustomization.yml in tests/fixtures/docker" \
  K8S_PATHS="tests/fixtures/docker"
should_fail "missing kube-linter-config" "$root" "No kube-linter config at does-not-exist.yaml" \
  K8S_PATHS="tests/fixtures/k8s" K8S_KUBELINTER_CONFIG="does-not-exist.yaml"

# --- lint-k8s.sh: discovery in empty repo & Component-only repo ---
git init -q "$work/empty-repo"
should_fail "empty repo" "$work/empty-repo" "No Kustomize directories to lint"

git init -q "$work/component-repo"
mkdir -p "$work/component-repo/comp"
cat >"$work/component-repo/comp/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
EOF
git -C "$work/component-repo" add comp/kustomization.yaml
should_fail "Component-only repo" "$work/component-repo" "No Kustomize directories to lint"

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
