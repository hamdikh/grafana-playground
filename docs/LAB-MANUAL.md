# Lab manual

The step-by-step manual (missions, SQL, exact click-paths, verified pitfalls)
lives next to the manifests it describes, one file per exercise:

- [TP1 — Installation express](../exercises/tp1-installation/README.md)
- [TP2 — Dashboards & TestData](../exercises/tp2-dashboards/README.md)
- [TP3 — MySQL](../exercises/tp3-mysql/README.md)
- [TP4 — PostgreSQL (datasource + internal DB)](../exercises/tp4-postgresql/README.md)
- [TP5 — Zabbix](../exercises/tp5-zabbix/README.md)
- [TP6 — Alerting & Teams](../exercises/tp6-alerting/README.md)
- [TP7 — Provisioning as code, RBAC, API](../exercises/tp7-provisioning/README.md)
- [Extension — multichannel alerting (Teams+Slack+Email)](../exercises/extension-multichannel-alerting/README.md)

This split (rather than one long manual) is deliberate: each exercise's
instructions sit next to the exact manifests and scripts they reference, so
`README.md` and `manifests/` never drift apart.

## Formateur — conduite d'animation

Les TP2 à TP7 s'enchaînent sur le cluster du TP1 — `exercises/*/run.sh`
bootstrappe tout ce qui précède automatiquement. Prévoir une procédure de
secours : `./bootstrap.sh clean && ./bootstrap.sh` recrée tout en ~5
minutes.

Le TP5 (Zabbix) est le plus lourd au démarrage (RAM, import de schéma) —
lancer `./exercises/tp5-zabbix/run.sh` avant une pause théorique plutôt que
pendant le TP.

Le TP6 doit démarrer tôt : `metrics-feeder` a besoin de quelques minutes de
collecte avant que les règles d'alerte soient utiles.

## Versions

- Support/production reference: Grafana 13.1 (latest as of writing).
- This lab pins `image.tag: "11.5.2"` in `values/grafana-values.yaml` — the
  version the original course program targets. Dashboards, datasources,
  variables, alerting and provisioning all behave identically; only
  Dynamic Dashboards (auto-grid/tabs, Grafana 12+) and Git Sync (Grafana
  12+) are out of scope at 11.5.2.
