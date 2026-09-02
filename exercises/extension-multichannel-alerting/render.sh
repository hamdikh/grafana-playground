#!/usr/bin/env bash
# Renders alerting-provisioning.tpl.yaml into alerting-provisioning.yaml
# (gitignored — contains real webhook URLs) and wraps it as a ConfigMap the
# grafana_alerting sidecar picks up (see values/grafana-values.yaml
# sidecar.alerts). Requires SLACK_WEBHOOK_URL and TEAMS_WORKFLOW_URL.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

: "${SLACK_WEBHOOK_URL:?export SLACK_WEBHOOK_URL first (Slack app -> Incoming Webhooks)}"
: "${TEAMS_WORKFLOW_URL:?export TEAMS_WORKFLOW_URL first (Teams channel -> Workflows -> Post to a channel when a webhook request is received)}"

sed -e "s|SLACK_WEBHOOK_URL|${SLACK_WEBHOOK_URL}|" \
    -e "s|TEAMS_WORKFLOW_URL|${TEAMS_WORKFLOW_URL}|" \
    alerting-provisioning.tpl.yaml > alerting-provisioning.yaml

python3 - <<'PY'
import json
with open("alerting-provisioning.yaml") as f:
    body = f.read()
cm = f"""---
apiVersion: v1
kind: ConfigMap
metadata:
  name: alerting-provisioning
  namespace: observability
  labels:
    grafana_alerting: "1"
data:
  tp-alerting.yaml: |
{chr(10).join('    ' + l for l in body.splitlines())}
"""
with open("alerting-configmap.yaml", "w") as f:
    f.write(cm)
PY

echo "Rendered alerting-provisioning.yaml and alerting-configmap.yaml (both gitignored)."
echo "Apply with: kubectl --context kind-grafana-lab apply -f alerting-configmap.yaml"
