#!/usr/bin/env bash
# One entry point for the whole lab. Idempotent — rerun any target freely.
#
#   ./bootstrap.sh              # cluster + Grafana + mysql + postgres + zabbix + alerting (everything but TP7)
#   ./bootstrap.sh tp1          # cluster + Grafana only
#   ./bootstrap.sh tp3          # tp1 + mysql
#   ./bootstrap.sh tp7          # tp1..tp6 + TP7's provisioning-as-code ConfigMaps
#   ./bootstrap.sh status       # what's up and how to reach it
#   ./bootstrap.sh clean        # delete the kind cluster
#
# Each exercises/<name>/run.sh is a thin wrapper that calls this script with
# the right target, so `./exercises/tp5-zabbix/run.sh` and
# `./bootstrap.sh tp5` do exactly the same thing.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source scripts/lib.sh

target="${1:-all}"

case "$target" in
  cluster|tp1)
    ensure_cluster
    install_grafana
    ;;
  tp2)
    ensure_cluster
    install_grafana
    info "TP2 uses the built-in TestData datasource and exercises/tp2-dashboards/csv/inventory.csv — nothing else to deploy."
    ;;
  tp3)
    "$0" tp1
    apply_manifest exercises/tp3-mysql/manifests/mysql.yaml
    rollout_wait lab deploy/mysql
    ok "MySQL ready — grafana-values.yaml already provisions the MySQL-Lab datasource"
    ;;
  tp4)
    "$0" tp3
    apply_manifest exercises/tp4-postgresql/manifests/postgres.yaml
    rollout_wait lab deploy/postgres
    ok "PostgreSQL ready — grafana-values.yaml already provisions the PostgreSQL-Lab datasource"
    ;;
  zabbix|tp5)
    "$0" tp4
    apply_manifest exercises/tp5-zabbix/manifests/zabbix.yaml
    rollout_wait zabbix deploy/zabbix-web
    ok "Zabbix ready — http://localhost:8080 (Admin / zabbix)"
    ;;
  alerting|tp6)
    "$0" tp4
    apply_manifest exercises/tp6-alerting/manifests/alerting.yaml
    rollout_wait lab deploy/webhook-echo
    rollout_wait lab deploy/mailhog
    ok "webhook-echo + metrics-feeder + MailHog ready"
    ;;
  tp7)
    "$0" all
    info "TP7 mission 1-2: apply exercises/tp7-provisioning/manifests/{ds,dash}-configmap.yaml yourself — that's the exercise."
    ;;
  extension)
    "$0" alerting
    info "See exercises/extension-multichannel-alerting/README.md to render and apply the multichannel alerting policy."
    ;;
  all)
    "$0" zabbix
    "$0" alerting
    ;;
  status)
    status
    ;;
  clean)
    clean
    ;;
  *)
    echo "usage: $0 {cluster|tp1|tp2|tp3|tp4|tp5|zabbix|tp6|alerting|tp7|extension|all|status|clean}" >&2
    exit 1
    ;;
esac
