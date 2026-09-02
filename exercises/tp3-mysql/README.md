# TP3 — Datasource et dashboards MySQL

**Objectif :** brancher MySQL et construire des panels SQL sur les 48h de
métriques du lab. **Durée :** 75 min. **Niveau :** intermédiaire.

## Lancer

```bash
./run.sh   # tp1 + manifests/mysql.yaml (namespace lab, base metricsdb, 2880 lignes/hôte)
```

## Vérifier le jeu de données

```bash
kubectl --context kind-grafana-lab -n lab exec deploy/mysql -- \
  mysql -ugrafana -pgrafanapass metricsdb \
  -e "SELECT host, COUNT(*) AS n, MIN(ts), MAX(ts) FROM metrics GROUP BY host;"
# 4 hôtes, 2880 lignes chacun (48h au pas de la minute)
```

## Datasource

Déjà provisionnée (`MySQL-Lab`, uid `mysql-lab`, voir
`../../values/grafana-values.yaml`) — comparez-la à une créée à la main via
Connections > Add new connection > MySQL avec les mêmes paramètres
(`mysql.lab.svc.cluster.local:3306`, `metricsdb`, `grafana`/`grafanapass`) :
la provisionnée affiche un bandeau et ses champs sont grisés.

## Requêtes clés

```sql
-- courbe agrégée
SELECT
  $__timeGroup(ts, $__interval) AS time,
  host AS metric,
  AVG(cpu) AS value
FROM metrics
WHERE $__timeFilter(ts)
GROUP BY 1, host
ORDER BY 1

-- pas fixe, trous remplis
SELECT $__timeGroupAlias(ts, 5m, 0), host AS metric, AVG(mem) AS value
FROM metrics WHERE $__timeFilter(ts) GROUP BY 1, host ORDER BY 1

-- table des incidents
SELECT opened_at AS "Date", host AS "Hote", severity AS "Severite", title AS "Titre"
FROM incidents WHERE $__timeFilter(opened_at) ORDER BY opened_at DESC
```

## Variables

- `env` (Query): `SELECT DISTINCT env FROM metrics ORDER BY env`
- `host` (Query, Multi-value + Include All):
  `SELECT DISTINCT host FROM metrics WHERE env IN ($env) ORDER BY host`
- Dans le `WHERE`, `host IN ($host)` — **sans guillemets** autour de
  `$host` : sur une liste multi-valeurs, Grafana génère déjà
  `'web01','web02'`. Testez avec `'$host'` pour voir l'échec.

## Panel repeat

Panel Gauge > Repeat options > Repeat by variable `host`, Horizontal, 4 par
ligne.

## Annotation

```sql
SELECT UNIX_TIMESTAMP(opened_at) * 1000 AS time, title AS text, severity AS tags
FROM incidents WHERE $__timeFilter(opened_at)
```

## Critères de réussite

- Vous savez expliquer le rôle de `$__timeFilter`, `$__timeGroup`,
  `$__timeGroupAlias`.
- Vous savez pourquoi Grafana attend des colonnes nommées `time`, `metric`,
  `value` en mode time series.
- Changer `env` met à jour la liste des hôtes disponibles.

## Pour aller plus loin

Pie chart des incidents par sévérité. Comparer les temps de réponse des deux
requêtes CPU via Panel inspect > Query. Variable de type Interval au lieu de
`$__interval`. Révoquer le SELECT sur `incidents` pour voir Grafana afficher
l'erreur de permission brute (il ne la masque jamais) :

```bash
kubectl --context kind-grafana-lab -n lab exec deploy/mysql -- \
  mysql -uroot -prootpass \
  -e "REVOKE SELECT ON metricsdb.incidents FROM 'grafana'@'%'; FLUSH PRIVILEGES;"
```
