# TP4 — PostgreSQL, comme datasource puis comme base interne de Grafana

**Objectif :** utiliser Postgres comme datasource, puis comme base interne
de Grafana. **Durée :** 75 min. **Niveau :** avancé.

## Lancer

```bash
./run.sh   # tp1 + tp3 + manifests/postgres.yaml (même schéma que TP3, en PostgreSQL)
```

## Comprendre

Ce TP fait jouer deux rôles sans rapport au même PostgreSQL. Ne pas les
confondre est l'essentiel de la séance.

| Rôle | Ce que Grafana y fait | Partie |
|---|---|---|
| **Datasource** | il *lit* vos données métier pour les afficher | A |
| **Base interne** (*backend database*) | il *écrit* son propre état : dashboards, utilisateurs, datasources, permissions | B |

### Partie A — ce que Postgres apporte de plus que MySQL

Les macros sont les mêmes qu'au TP3 (`$__timeFilter`, `$__timeGroup`…) et le
type `timestamptz` évite les conversions epoch. L'intérêt réel est ailleurs :
les **fonctions fenêtre** (`OVER (PARTITION BY … ORDER BY …)`) calculent une
valeur par ligne *en fonction des lignes voisines* — moyenne glissante, rang,
écart au précédent — sans auto-jointure ni post-traitement côté Grafana. Le
calcul reste là où sont les données.

Et `percentile_cont(0.95)` plutôt que `avg()` : une moyenne dissimule les
pics, or c'est le pic qui dégrade l'expérience utilisateur. Un serveur à 40 %
de CPU moyen mais 98 % de p95 est saturé un vingtième du temps. C'est pour
cette raison que les SLA se formulent en percentiles et jamais en moyennes —
savoir le justifier fait partie des acquis du TP.

### Partie B — pourquoi la base interne compte

Par défaut, Grafana écrit son état dans un fichier SQLite local au pod. Deux
conséquences :

- **Pas de haute disponibilité possible.** Deux réplicas, ce serait deux
  fichiers SQLite indépendants, donc deux Grafana qui divergent
  immédiatement. Passer sur PostgreSQL est le prérequis technique du
  multi-replica, pas un raffinement d'architecte.
- **La bascule n'est pas une migration.** Au démarrage, Grafana applique ses
  migrations de schéma sur la base qu'on lui désigne : il y crée des tables
  vides. Il ne lit jamais l'ancien SQLite, et rien ne l'y invite. Tout ce qui
  n'était pas provisionné par fichier est perdu.

C'est l'argument qui amène directement le TP7 : si l'état durable de votre
Grafana tient dans des fichiers versionnés, changer de base, de cluster ou de
version devient un non-événement.

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
