#!/usr/bin/env bash
# End-to-end check of the whole lab. Read-only — deploys nothing, changes
# nothing. Run it after ./bootstrap.sh to confirm the machine is ready for
# a training session:
#
#   ./scripts/validate.sh          # preflight + everything that's deployed
#   ./scripts/validate.sh pre      # preflight only (before bootstrapping)
#
# Exit code 0 when every check passed, 1 otherwise. Checks whose exercise
# hasn't been run yet are reported SKIP, not FAIL — a machine with tp1..tp4
# up and no Zabbix is a valid state (see the RAM note in README.md).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_AUTH="${GRAFANA_AUTH:-admin:Grafana2025!}"
ZABBIX_URL="${ZABBIX_URL:-http://localhost:8080}"

pass=0; fail=0; skip=0

check()  { printf '\033[32m  PASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
nope()   { printf '\033[31m  FAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail+1)); }
absent() { printf '\033[33m  SKIP\033[0m %s — %s\n' "$1" "$2"; skip=$((skip+1)); }
section(){ printf '\n\033[1m%s\033[0m\n' "$1"; }

# assert <label> <command...> — PASS if the command exits 0, FAIL otherwise.
assert() {
  local label="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then check "$label"; else nope "$label" "$(echo "$out" | tail -3 | tr '\n' ' ')"; fi
}

gapi() { curl -sS --max-time 15 -u "$GRAFANA_AUTH" "$GRAFANA_URL$1"; }

# deployed <namespace> <deploy> — true when the deployment exists and is available.
deployed() {
  [ "$(kctl -n "$1" get deploy "$2" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)" -ge 1 ] 2>/dev/null
}

section "Preflight"
for tool in docker kubectl helm kind jq curl; do
  if command -v "$tool" >/dev/null 2>&1; then check "$tool installed"; else nope "$tool installed" "not on PATH"; fi
done
if docker info >/dev/null 2>&1; then check "docker daemon reachable"
elif [ -S /var/run/docker.sock ]; then
  nope "docker daemon reachable" "socket exists but $USER can't use it — sudo usermod -aG docker $USER, then log out and back in"
else nope "docker daemon reachable" "no /var/run/docker.sock — is the daemon started?"; fi

# LC_ALL=C or a fr_FR locale prints "23,5" and every later numeric test blows up.
mem_gb=$(LC_ALL=C awk '/MemTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo 2>/dev/null || echo 0)
if LC_ALL=C awk "BEGIN{exit !($mem_gb >= 7.5)}"; then check "RAM ${mem_gb}G (>= 8G)"
else nope "RAM ${mem_gb}G (>= 8G)" "Zabbix/TP5 needs ~1.5G — skip tp5 if tight"; fi

disk_gb=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
if [ "${disk_gb:-0}" -ge 15 ]; then check "disk ${disk_gb}G free on / (>= 15G)"
else nope "disk ${disk_gb:-?}G free on / (>= 15G)" "kind node image + 6 workloads need room"; fi

# No -f: these answer 401/404 at the paths we probe and that still proves
# egress works, which is all we need before `helm repo add` / image pulls.
assert "reachable grafana helm repo" curl -sS --max-time 20 -o /dev/null https://grafana.github.io/helm-charts/index.yaml
assert "reachable docker registry" curl -sS --max-time 20 -o /dev/null https://registry-1.docker.io/v2/

[ "${1:-}" = "pre" ] && { printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"; exit $(( fail > 0 )); }

section "TP1 — cluster & Grafana"
if kind get clusters 2>/dev/null | grep -qx grafana-lab; then
  check "kind cluster grafana-lab exists"
else
  nope "kind cluster grafana-lab exists" "run ./bootstrap.sh first"
  printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"; exit 1
fi
assert "all nodes Ready" bash -c 'kubectl --context kind-grafana-lab get nodes -o jsonpath="{.items[*].status.conditions[?(@.type==\"Ready\")].status}" | grep -qv False'
if deployed observability grafana; then check "Grafana deployment available"
else nope "Grafana deployment available" "kubectl --context $CTX -n observability get deploy grafana"; fi
assert "Grafana API answers on $GRAFANA_URL" bash -c "curl -sSf --max-time 15 -o /dev/null $GRAFANA_URL/api/health"
ver=$(gapi /api/health | jq -r '.version // empty' 2>/dev/null)
if [ -n "$ver" ]; then check "Grafana health reports version $ver"; else nope "Grafana /api/health parses" "no version in response"; fi
if gapi /api/org | jq -e '.id' >/dev/null 2>&1; then check "admin login works ($GRAFANA_AUTH)"
else nope "admin login works" "credentials rejected by /api/org"; fi

section "TP2 — TestData & CSV"
if gapi /api/datasources | jq -e '.[] | select(.uid=="testdata")' >/dev/null 2>&1; then
  check "TestData datasource provisioned"
else nope "TestData datasource provisioned" "expected uid=testdata"; fi
if [ -s exercises/tp2-dashboards/csv/inventory.csv ]; then check "inventory.csv present and non-empty"
else nope "inventory.csv present and non-empty" "exercises/tp2-dashboards/csv/inventory.csv"; fi

# ds_health <uid> <label> <namespace> <deploy> — datasource health, SKIP when its backend isn't deployed.
ds_health() {
  local uid="$1" label="$2" ns="$3" dep="$4"
  if ! deployed "$ns" "$dep"; then absent "$label datasource healthy" "$dep not deployed yet"; return; fi
  local st
  st=$(gapi "/api/datasources/uid/$uid/health" | jq -r '.status // "?"' 2>/dev/null)
  if [ "$st" = "OK" ]; then check "$label datasource healthy"
  else nope "$label datasource healthy" "health status=$st"; fi
}

section "TP3 — MySQL"
if deployed lab mysql; then
  check "mysql deployment available"
  rows=$(kctl -n lab exec deploy/mysql -- sh -c \
    'mysql -ugrafana -pgrafanapass metricsdb -N -B -e "SELECT COUNT(*) FROM metrics"' 2>/dev/null | tr -dc '0-9')
  if [ "${rows:-0}" -ge 11000 ]; then check "metrics seeded (${rows} rows)"
  else nope "metrics seeded" "got ${rows:-0} rows, expected ~11520 (4 hosts x 2880 min)"; fi
  inc=$(kctl -n lab exec deploy/mysql -- sh -c \
    'mysql -ugrafana -pgrafanapass metricsdb -N -B -e "SELECT COUNT(*) FROM incidents"' 2>/dev/null | tr -dc '0-9')
  if [ "${inc:-0}" -ge 4 ]; then check "incidents seeded (${inc} rows)"
  else nope "incidents seeded" "got ${inc:-0} rows, expected >= 4"; fi
else absent "MySQL checks" "deploy/mysql not up — run ./exercises/tp3-mysql/run.sh"; fi
ds_health mysql-lab MySQL-Lab lab mysql

section "TP4 — PostgreSQL"
if deployed lab postgres; then
  check "postgres deployment available"
  rows=$(kctl -n lab exec deploy/postgres -- sh -c \
    'PGPASSWORD=grafanapass psql -U grafana -d metricsdb -tAc "SELECT COUNT(*) FROM metrics"' 2>/dev/null | tr -dc '0-9')
  if [ "${rows:-0}" -ge 11000 ]; then check "metrics seeded (${rows} rows)"
  else nope "metrics seeded" "got ${rows:-0} rows, expected ~11520"; fi
else absent "PostgreSQL checks" "deploy/postgres not up — run ./exercises/tp4-postgresql/run.sh"; fi
ds_health pg-lab PostgreSQL-Lab lab postgres

section "TP5 — Zabbix"
if deployed zabbix zabbix-web; then
  check "zabbix-web deployment available"
  for d in zabbix-mysql zabbix-server zabbix-agent; do
    if deployed zabbix "$d"; then check "$d available"; else nope "$d available" "kubectl -n zabbix get deploy $d"; fi
  done
  assert "Zabbix frontend answers on $ZABBIX_URL" curl -sSf --max-time 20 -o /dev/null "$ZABBIX_URL"
  if gapi /api/plugins/alexanderzobnin-zabbix-app/settings | jq -e '.enabled == true' >/dev/null 2>&1; then
    check "Zabbix Grafana plugin enabled"
  else nope "Zabbix Grafana plugin enabled" "enable it in Grafana > Plugins > Zabbix"; fi
  ds_health zabbix Zabbix zabbix zabbix-web
else absent "Zabbix checks" "deploy/zabbix-web not up — run ./exercises/tp5-zabbix/run.sh (needs ~1.5G RAM)"; fi

section "TP6 — Alerting"
if deployed lab webhook-echo; then
  check "webhook-echo available"
  if deployed lab mailhog; then check "mailhog available"; else nope "mailhog available" "kubectl -n lab get deploy mailhog"; fi
  if kctl -n lab get cronjob metrics-feeder >/dev/null 2>&1; then check "metrics-feeder CronJob present"
  else nope "metrics-feeder CronJob present" "kubectl -n lab get cronjob"; fi
  n=$(gapi /api/v1/provisioning/alert-rules | jq 'length' 2>/dev/null)
  if [ "${n:-0}" -ge 1 ]; then check "$n alert rule(s) in Grafana"
  else absent "alert rules in Grafana" "none yet — TP6 has you create them in the UI"; fi
  cp=$(gapi /api/v1/provisioning/contact-points | jq 'length' 2>/dev/null)
  if [ "${cp:-0}" -ge 1 ]; then check "$cp contact point(s) in Grafana"
  else absent "contact points in Grafana" "none yet — TP6/extension create them"; fi
else absent "Alerting checks" "deploy/webhook-echo not up — run ./exercises/tp6-alerting/run.sh"; fi

section "TP7 — Provisioning as code"
for f in exercises/tp7-provisioning/manifests/ds-configmap.yaml \
         exercises/tp7-provisioning/manifests/dash-configmap.yaml; do
  assert "$(basename "$f") is valid (server dry-run)" kctl apply --dry-run=server -f "$f"
done
for f in exercises/tp7-provisioning/manifests/dashboards/*.yaml; do
  json=$(kctl create --dry-run=client -o json -f "$f" 2>/dev/null | jq -r '.data | to_entries[0].value' 2>/dev/null)
  if [ -n "$json" ] && echo "$json" | jq -e . >/dev/null 2>&1; then check "$(basename "$f") embeds valid dashboard JSON"
  else nope "$(basename "$f") embeds valid dashboard JSON" "the ConfigMap value did not parse as JSON"; fi
done
if gapi /api/search?type=dash-db | jq -e 'length >= 1' >/dev/null 2>&1; then
  check "$(gapi /api/search?type=dash-db | jq 'length') dashboard(s) visible in Grafana"
else absent "dashboards in Grafana" "none yet — TP2/TP7 have you create or apply them"; fi

section "Extension — multichannel alerting"
if [ -f exercises/extension-multichannel-alerting/alerting-provisioning.tpl.yaml ]; then
  check "alerting template present"
  assert "render.sh is executable" test -x exercises/extension-multichannel-alerting/render.sh
else nope "alerting template present" "alerting-provisioning.tpl.yaml missing"; fi

section "Repo hygiene"
for f in bootstrap.sh scripts/*.sh exercises/*/*.sh; do
  [ -e "$f" ] || continue
  if [ -x "$f" ]; then check "$f executable"; else nope "$f executable" "chmod +x $f"; fi
done
if command -v bash >/dev/null; then
  for f in bootstrap.sh scripts/*.sh exercises/*/*.sh; do
    [ -e "$f" ] || continue
    assert "$f parses" bash -n "$f"
  done
fi

printf '\n\033[1m%d passed, %d failed, %d skipped\033[0m\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] && ok "lab is ready" || warn "see FAIL lines above"
exit $(( fail > 0 ))
