# TP7 — Provisioning as code, RBAC et API

**Objectif :** recréer sources, dashboards et alertes en YAML, puis
cloisonner les accès. **Durée :** 60 min. **Niveau :** avancé.

## Lancer

```bash
./run.sh   # tout (tp1..tp6) — TP7 lui-même est deux `kubectl apply` que vous faites à la main, voir ci-dessous
```

## Mission 1 — datasource par ConfigMap

```bash
kubectl --context kind-grafana-lab apply -f manifests/ds-configmap.yaml
kubectl --context kind-grafana-lab -n observability logs deploy/grafana -c grafana-sc-datasources --tail=20
```

## Mission 2 — dashboard par ConfigMap

```bash
kubectl --context kind-grafana-lab apply -f manifests/dash-configmap.yaml
```

Ce dashboard-là s'appuie sur la datasource `PG-IaC` (uid `pg-iac`) créée par
`ds-configmap.yaml`, pas sur `PostgreSQL-Lab` — deux datasources distinctes
pointant sur le même Postgres, pour illustrer le provisioning de bout en
bout.

## Mission 3 — édition impossible

L'enregistrement échoue : le dashboard est provisionné, le fichier sur
disque est la source de vérité, le sidecar le réécrit à chaque changement de
ConfigMap. Contournement pédagogique : *Save As* pour une copie éditable,
puis réinjecter le JSON dans la ConfigMap — exactement le workflow Git à
mettre en place en vrai.

## Mission 4 — provider catalogue

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: catalogue
        orgId: 1
        folder: Catalogue
        type: file
        options:
          path: /var/lib/grafana/dashboards/catalogue
dashboards:
  catalogue:
    postgres-overview:
      gnetId: 9628
      revision: 7
      datasource: PG-IaC
```

⚠️ Le chart télécharge le JSON depuis grafana.com au démarrage du pod (via
un `initContainer`) — sans accès Internet, le pod ne démarre pas. En
production, vendoriser le JSON dans le dépôt Git.

## Missions 5-6 — Teams et permissions

1. Administration > Users and access > Teams > `equipe-infra`, `equipe-appli`.
2. Users > New user : un Viewer, un Editor, rattachés aux teams.
3. Dashboards > folder *Formation IaC* > Manage permissions : `equipe-infra`
   en Edit, `equipe-appli` en View.
4. Session privée, connexion Viewer : le folder est visible en lecture, le
   reste ne l'est pas.

**Limites OSS à connaître :** pas de rôles personnalisés, pas de RBAC sur
les datasources — fonctions Enterprise/Cloud, souvent l'argument
déclencheur d'un passage payant.

## Mission 7 — API

```bash
export GRAFANA_URL="http://localhost:3000"
export GRAFANA_TOKEN="glsa_xxxxxxxx"

curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/search?type=dash-db" | jq '.[] | {uid, title, folderTitle}'

curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/dashboards/uid/cpu-iac" | jq '.dashboard' > cpu-iac.json
```

## Mission 8 — script d'export par folder

Voir [`export-by-folder.sh`](export-by-folder.sh) — `del(.id, .version)`
avant d'écrire le JSON est indispensable : sans lui, le réimport sur une
autre instance échoue sur un conflit de version.

## Comparaison des quatre approches

| Approche | Avantages | Inconvénients |
|---|---|---|
| Sidecar ConfigMap | natif Kubernetes, GitOps immédiat | limite de taille des ConfigMaps |
| Provider fichier | simple, adapté aux VM | nécessite de reconstruire l'image |
| Terraform `provider grafana` | couvre users/teams/folders/alertes | état à maintenir, dérive possible |
| Grafana Operator | CRD, réconciliation continue | brique supplémentaire à opérer |

## Critères de réussite

- Le dashboard IaC apparaît dans le bon folder sans action manuelle.
- Le compte Viewer ne voit pas les dashboards des autres folders.

## Bonus — dashboards TP3/TP4/TP5 entièrement en code

Trois dashboards supplémentaires, un par datasource SQL/Zabbix des TP
précédents, chacun avec ses requêtes écrites en clair dans le YAML — pas de
raccourci "cliqué dans l'UI puis exporté" : ce que vous lisez dans le
fichier est exactement ce qui s'exécute.

```bash
kubectl --context kind-grafana-lab apply -f manifests/dashboards/mysql-overview.yaml
kubectl --context kind-grafana-lab apply -f manifests/dashboards/postgresql-overview.yaml
kubectl --context kind-grafana-lab apply -f manifests/dashboards/zabbix-overview.yaml
```

| Fichier | Folder | Requêtes |
|---|---|---|
| `dashboards/mysql-overview.yaml` | MySQL | CPU par hôte (`$__timeGroup`), table des incidents |
| `dashboards/postgresql-overview.yaml` | PostgreSQL | moyenne glissante (fonction fenêtre), p95 par hôte au-dessus d'un seuil (variable `$seuil`) |
| `dashboards/zabbix-overview.yaml` | Zabbix | items serveur (Metrics), triggers en Problem — voir le commentaire du fichier sur une limite du plugin observée en conditions réelles |

Chacun réutilise exactement les requêtes SQL des missions TP3/TP4 et le
sélecteur Group/Host/Item de la mission 5 du TP5 — rien de nouveau à
apprendre côté requête, seulement où elle vit (Git, pas la souris).

Ces mêmes trois dashboards, plus un quatrième multi-datasources (Prometheus,
MySQL, PostgreSQL, Zabbix, Loki, CSV/JSON via Infinity dans un seul écran,
avec plusieurs types de visualisation — stat, gauge, barchart, piechart,
logs, pas seulement timeseries/table), existent aussi côté
`homelab-plateform` (`infrastructure/baseline/monitoring/dashboards/`) —
mêmes principes, sur un vrai cluster de production plutôt qu'un kind
jetable.

## Pour aller plus loin

Comparer les quatre approches ci-dessus en pratique. Installer
`marcusolsson-csv-datasource`, exposer un CSV via nginx. Discuter des
limites du RBAC OSS.
