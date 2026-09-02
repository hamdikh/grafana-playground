#!/usr/bin/env bash
# Shared functions for bootstrap.sh and every exercises/*/run.sh. Never
# touches any kube-context other than kind-grafana-lab.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTX="kind-grafana-lab"
NS_OBS="observability"
NS_LAB="lab"

ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
info() { printf '\033[34m→\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1"; }

kctl() { kubectl --context "$CTX" "$@"; }

ensure_cluster() {
  if kind get clusters 2>/dev/null | grep -qx grafana-lab; then
    ok "kind cluster grafana-lab already exists"
  else
    info "creating kind cluster grafana-lab"
    kind create cluster --config "$REPO_ROOT/kind-config.yaml"
  fi
  kctl cluster-info >/dev/null
}

install_grafana() {
  info "installing/upgrading Grafana (Helm, context $CTX)"
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update grafana >/dev/null
  helm --kube-context "$CTX" upgrade --install grafana grafana/grafana \
    --namespace "$NS_OBS" --create-namespace \
    --values "$REPO_ROOT/values/grafana-values.yaml" \
    --wait --timeout 5m
  ok "Grafana ready — http://localhost:3000 (admin / Grafana2025!)"
}

apply_manifest() {
  # apply_manifest <path relative to repo root>
  info "applying $1"
  kctl apply -f "$REPO_ROOT/$1"
}

rollout_wait() {
  # rollout_wait <namespace> <deploy/name>
  kctl -n "$1" rollout status "$2" --timeout=180s
}

status() {
  echo "--- kind clusters ---"
  kind get clusters 2>/dev/null || true
  echo "--- pods ($NS_OBS) ---"
  kctl -n "$NS_OBS" get pods 2>/dev/null || true
  echo "--- pods ($NS_LAB) ---"
  kctl -n "$NS_LAB" get pods 2>/dev/null || true
  echo "--- pods (zabbix) ---"
  kctl -n zabbix get pods 2>/dev/null || true
  echo
  echo "Grafana:  kubectl --context $CTX -n $NS_OBS port-forward svc/grafana 3000:80  (or NodePort http://localhost:3000)"
  echo "MailHog:  kubectl --context $CTX -n $NS_LAB port-forward svc/mailhog 8025:8025"
  echo "Zabbix:   http://localhost:8080 (Admin / zabbix)"
}

clean() {
  warn "deleting kind cluster grafana-lab"
  kind delete cluster --name grafana-lab
}
