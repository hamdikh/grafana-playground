#!/usr/bin/env bash
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_TOKEN="${GRAFANA_TOKEN:?jeton manquant}"
FOLDER="${1:?usage: $0 <nom du folder>}"
OUT="dashboards/${FOLDER// /-}"
mkdir -p "$OUT"

folder_uid=$(curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/folders" \
  | jq -r --arg f "$FOLDER" '.[] | select(.title == $f) | .uid')

curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/search?type=dash-db&folderUIDs=$folder_uid" \
  | jq -r '.[].uid' \
  | while read -r uid; do
      title=$(curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
        "$GRAFANA_URL/api/dashboards/uid/$uid" \
        | jq -r '.dashboard.title')
      curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
        "$GRAFANA_URL/api/dashboards/uid/$uid" \
        | jq '.dashboard | del(.id, .version)' \
        > "$OUT/${title// /-}.json"
      echo "exporte : $title"
    done
