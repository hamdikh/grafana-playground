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

# TP4 has the student run `kubectl scale deploy/grafana --replicas=2`. That
# imperative scale records `kubectl` (subresource `scale`) as the owner of
# .spec.replicas, and Helm 4 — which applies server-side — then refuses to
# overwrite a field owned by another manager: every later bootstrap dies on
# `conflict with "kubectl" with subresource "scale"`, whatever target was
# asked for. Rather than making the student scale back by hand, take the
# field back here: drop the recorded ownership (the entries are rebuilt by
# the next apply) so Helm owns .spec.replicas again. No-op on Helm 3, which
# applies client-side and never hits this.
reclaim_grafana_replicas() {
  kctl -n "$NS_OBS" get deploy grafana >/dev/null 2>&1 || return 0
  kctl -n "$NS_OBS" get deploy grafana \
    -o jsonpath='{.metadata.managedFields[*].subresource}' 2>/dev/null \
    | grep -q scale || return 0
  info "reclaiming .spec.replicas of deploy/grafana from kubectl scale"
  kctl -n "$NS_OBS" patch deploy grafana --type=merge \
    -p '{"metadata":{"managedFields":[{}]}}' >/dev/null
}

# TP4 part B has you point Grafana's own database at
# postgres.lab.svc.cluster.local by editing values/grafana-values.yaml.
# From that edit on Grafana cannot start before PostgreSQL runs — and
# bootstrap installs Grafana at the tp1 stage, long before the TP4
# manifest, so the pod crashloops on `dial tcp: lookup
# postgres.lab.svc.cluster.local: no such host` and every target fails.
# When the values file asks for postgres, bring postgres up first.
ensure_grafana_database() {
  grep -qE '^[[:space:]]*type:[[:space:]]*postgres[[:space:]]*$' \
    "$REPO_ROOT/values/grafana-values.yaml" || return 0
  info "grafana-values.yaml stores Grafana in PostgreSQL — deploying it first"
  kctl create namespace "$NS_LAB" --dry-run=client -o yaml | kctl apply -f - >/dev/null
  kctl apply -f "$REPO_ROOT/exercises/tp4-postgresql/manifests/postgres.yaml" >/dev/null
  rollout_wait "$NS_LAB" deploy/postgres
}

install_grafana() {
  info "installing/upgrading Grafana (Helm, context $CTX)"
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update grafana >/dev/null
  ensure_grafana_database
  reclaim_grafana_replicas
  # Belt and braces: newer Helm can also be told to win the conflict
  # outright. Helm 3 does not know the flag, hence the probe.
  local ssa=()
  if helm upgrade --help 2>/dev/null | grep -q -- '--force-conflicts'; then
    ssa=(--force-conflicts)
  fi
  helm --kube-context "$CTX" upgrade --install grafana grafana/grafana \
    --namespace "$NS_OBS" --create-namespace \
    --values "$REPO_ROOT/values/grafana-values.yaml" \
    ${ssa[@]+"${ssa[@]}"} \
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
