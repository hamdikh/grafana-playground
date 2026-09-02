# TP4 — PostgreSQL, comme datasource puis comme base interne de Grafana

**Objectif :** utiliser Postgres comme datasource, puis comme base interne
de Grafana. **Durée :** 75 min. **Niveau :** avancé.

## Lancer

```bash
./run.sh   # tp1 + tp3 + manifests/postgres.yaml (même schéma que TP3, en PostgreSQL)
```

## Partie A — datasource

Déjà provisionnée (`PostgreSQL-Lab`, uid `pg-lab`). Mêmes macros qu'en
MySQL, mais un vrai `timestamptz` (pas de `UNIX_TIMESTAMP` nécessaire) et
des fonctionnalités que MySQL n'a pas :

```sql
-- moyenne glissante (fonction fenêtre)
SELECT ts AS time, host AS metric, cpu AS value,
  avg(cpu) OVER (PARTITION BY host ORDER BY ts ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS moyenne_glissante
FROM metrics WHERE $__timeFilter(ts) ORDER BY ts

-- percentile 95 (ce que demandent les SLA, pas la moyenne)
SELECT host AS "Hote", round(avg(cpu), 2) AS "CPU moyen",
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY cpu)::numeric, 2) AS "CPU p95",
  round(max(cpu), 2) AS "CPU max"
FROM metrics WHERE $__timeFilter(ts) GROUP BY host ORDER BY 3 DESC
```

Variable `seuil` (Text box, défaut `80`) utilisée dans un `HAVING avg(cpu) >
$seuil`.

## Partie B — PostgreSQL comme base interne de Grafana

Par défaut Grafana stocke dashboards/utilisateurs/datasources dans un
SQLite embarqué — impossible de faire du multi-replica. Basculer sur
Postgres (ajouter à `values/grafana-values.yaml` avant de réappliquer) :

```yaml
grafana.ini:
  database:
    type: postgres
    host: postgres.lab.svc.cluster.local:5432
    name: grafana
    user: grafana_app
    password: $__env{GF_DATABASE_PASSWORD}
    ssl_mode: disable
envRenderSecret:
  GF_DATABASE_PASSWORD: grafanaapp
```

```bash
helm --kube-context kind-grafana-lab upgrade grafana grafana/grafana \
  -n observability -f ../../values/grafana-values.yaml
kubectl --context kind-grafana-lab -n observability logs deploy/grafana -c grafana | grep -i migrat
```

**⚠️ Les dashboards des TP2/TP3 disparaissent** — Grafana crée un schéma
vierge, il ne migre rien depuis SQLite. C'est un repartir-de-zéro, pas une
migration. Seule `TestData` survit (provisionnée par fichier, pas par
base). Parades : (1) tout provisionner en code (TP7), (2) exporter les
dashboards par API avant bascule.

Puis 2 réplicas :

```bash
kubectl --context kind-grafana-lab -n observability scale deploy/grafana --replicas=2
```

## Critères de réussite

- `\dt` dans la base `grafana` liste `dashboard`, `data_source`, `user`.
- Les deux pods Grafana affichent les mêmes dashboards.
- Vous savez expliquer pourquoi SQLite→PostgreSQL n'est pas une migration.

## Pour aller plus loin

Comparer les macros SQL MySQL/PostgreSQL. Activer TimescaleDB dans la
datasource. Mesurer la taille de la base `grafana` après import de
dashboards.
