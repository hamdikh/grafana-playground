# TP3 — Datasource et dashboards MySQL

**Objectif :** brancher MySQL et construire des panels SQL sur les 48h de
métriques du lab. **Durée :** 75 min. **Niveau :** intermédiaire.

## Lancer

```bash
./run.sh   # tp1 + manifests/mysql.yaml (namespace lab, base metricsdb, 2880 lignes/hôte)
```

## Comprendre

### Ce que Grafana attend en retour d'une requête SQL

Une datasource SQL renvoie des lignes ; c'est Grafana qui décide comment les
lire, selon le **Format** choisi sous l'éditeur de requête :

| Format | Attendu | Usage |
|---|---|---|
| *Time series* | une colonne `time`, une colonne `value` numérique, et facultativement `metric` (texte) qui nomme la série | courbes |
| *Table* | n'importe quelles colonnes, telles quelles | tableaux, et alerting au TP6 |

En *Time series*, ces noms de colonnes ne sont pas décoratifs : c'est le
contrat. D'où les `AS time`, `AS metric`, `AS value` dans les requêtes
ci-dessous. `host AS metric` produit une courbe par hôte parce que Grafana
éclate les lignes en séries d'après cette colonne.

### Les macros

Une macro est un raccourci que la datasource **remplace par du SQL** avant
l'envoi. Elle ne sert pas à taper moins : elle injecte le contexte du
dashboard — fenêtre temporelle, largeur du panel — dans la requête.

| Macro | Devient, en substance | À quoi ça sert |
|---|---|---|
| `$__timeFilter(ts)` | `ts BETWEEN <début> AND <fin>` | applique le sélecteur de temps du dashboard **dans le `WHERE`**, donc côté base |
| `$__timeGroup(ts, $__interval)` | une expression qui arrondit `ts` à un pas régulier | regroupe les points en intervalles |
| `$__timeGroupAlias(ts, 5m, 0)` | idem, avec `AS time` et remplissage des intervalles vides par `0` | pas fixe, série continue |
| `$__interval` | une durée (`30s`, `2m`…) calculée par Grafana | environ un point par pixel du panel |

Trois idées se cachent derrière ce tableau, et ce sont elles qu'il faut
savoir réexpliquer :

**Sans `$__timeFilter`, le sélecteur de temps ne sert à rien.** La requête
ramènerait les 48 h complètes quel que soit le zoom, et Grafana n'en
afficherait qu'une découpe côté navigateur. C'est l'erreur la plus coûteuse
du métier : la base travaille pour rien à chaque rafraîchissement, sur
chaque panel, pour chaque utilisateur connecté.

**`$__interval` s'adapte à la fenêtre et à la largeur du panel.** Sur 6 h il
vaudra quelques secondes, sur 30 jours plusieurs minutes. Le nombre de
points renvoyés reste donc à peu près constant quel que soit le zoom —
c'est ce qui évite de rapatrier 40 000 points pour les écraser dans 800
pixels.

**Le troisième argument de `$__timeGroupAlias` décide du sens des trous.**
`0` force les intervalles sans donnée à zéro, `NULL` laisse un trou visible,
l'absence d'argument supprime la ligne. Ce n'est pas cosmétique : « aucune
mesure » et « mesure à zéro » ne racontent pas la même chose, et sur un
graphe de disponibilité la confusion se paie cher.

### Interpolation des variables multi-valeurs

`$host` en *Multi-value* n'est pas une simple chaîne : Grafana le remplace
par `'web01','web02'`, guillemets compris. D'où `host IN ($host)` **sans
rien autour**. Écrire `IN ('$host')` produit `IN (''web01','web02'')`, une
erreur de syntaxe. La règle générale : la façon dont une variable
s'interpole dépend de la datasource et du contexte ; en cas de doute,
`Panel inspect > Query` montre le SQL réellement envoyé.

### Annotations

Une annotation est un **événement daté** superposé aux panels d'un
dashboard, pas une série de mesures. Sa requête doit rendre un instant
(`time` en millisecondes epoch — d'où le `UNIX_TIMESTAMP() * 1000` en
MySQL), un `text` et des `tags`. C'est la manière standard de poser « un
déploiement a eu lieu ici » sur des courbes de métriques, et donc de relier
une dégradation à sa cause.

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
