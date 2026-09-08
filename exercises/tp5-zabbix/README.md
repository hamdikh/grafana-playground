# TP5 — Datasource et dashboards Zabbix

**Objectif :** brancher la stack Zabbix du lab et exploiter métriques,
problèmes et annotations. **Durée :** 90 min. **Niveau :** intermédiaire.
**~1.5GB RAM** — le plus lourd des TP, optionnel si vous êtes limité.

## Lancer

```bash
./run.sh   # tp1 + tp3 + tp4 + manifests/zabbix.yaml (namespace zabbix)
```

Compter quelques minutes de démarrage (import de schéma). Frontend sur
http://localhost:8080, `Admin` / `zabbix`.

## Le trafic synthétique

Un Zabbix qui ne supervise que lui-même donne des panels plats : c'est le
premier réflexe de frustration du TP. `manifests/traffic.yaml` (appliqué par
`run.sh`) déploie `zabbix-traffic`, qui crée par API trois hôtes applicatifs
dans le host group **Lab apps** et les alimente **en continu, toutes les
10 secondes** :

| Hôte | Profil | Items |
|---|---|---|
| `lab-web-01` | nominal | `app.requests`, `app.errors`, `app.error_rate` (%) |
| `lab-web-02` | trafic plus faible | `app.latency_ms` (ms), `app.users` |
| `lab-api-01` | plus de volume, plus d'erreurs | idem |

Le débit suit une onde lente (cycle jour/nuit) plutôt qu'un bruit blanc, et
**toutes les 10 minutes une fenêtre d'incident de 2 minutes** fait grimper le
taux d'erreur au-dessus de 12 % et la latence au-dessus de 650 ms. Trois
triggers par hôte sont créés avec les items :

- `avg(/<host>/app.error_rate,1m)>10` — sévérité High
- `avg(/<host>/app.latency_ms,1m)>500` — sévérité Average
- `nodata(/<host>/app.requests,5m)=1` — sévérité Warning

Noter que les fenêtres d'évaluation (`1m`) sont plus courtes que la fenêtre
d'incident (2 min) : un `min(/<host>/app.error_rate,2m)>10` demanderait un
dépassement sur *toute* la fenêtre et ne déclencherait quasiment jamais — le
piège classique quand on écrit un trigger sur un phénomène bref.

Ils passent donc en *Problem* puis se referment seuls : de quoi remplir un
panel Problems et voir les annotations apparaître et disparaître sans rien
provoquer à la main. Compter ~5 minutes après le déploiement pour les
premières séries, ~10 pour le premier incident.

L'hôte `Zabbix server`, lui, reçoit deux items poussés en plus de ce que
l'agent collecte : `lab.queue.depth` (profondeur de file) et
`lab.service.status` (0/1). Ils suivent la même fenêtre d'incident et
portent deux triggers supplémentaires :

- `avg(/Zabbix server/lab.queue.depth,1m)>500` — sévérité Average
- `last(/Zabbix server/lab.service.status)=0` — sévérité High

Le groupe **Zabbix servers** a donc lui aussi des *Problems*, et cet hôte
devient un cas d'école : ses items `system.cpu.*` sont *collectés* par
l'agent (le serveur va les chercher), ses items `lab.*` sont *poussés* par
`zabbix_sender`. Même hôte, deux modes de collecte — le panneau *Latest
data* de Zabbix les affiche côte à côte sans les distinguer, seule la
colonne *Type* de la configuration le dit.

Les items applicatifs sont de type **Zabbix trapper** : l'hôte ne collecte rien, c'est le
générateur qui *pousse* les valeurs avec `zabbix_sender` (port 10051 du
serveur). C'est le mode qu'on retrouve en production pour tout ce que Zabbix
ne sait pas aller chercher lui-même — batchs, jobs, scripts métier. Corollaire
qui surprend souvent : un item trapper n'a pas d'intervalle de collecte, donc
un trapper muet ne remonte aucune erreur — d'où le trigger `nodata()`.

Le script est dans la ConfigMap `zabbix-traffic` et est idempotent : il
détecte les hôtes déjà créés et se contente d'émettre. Pour couper le trafic
(par exemple pour observer `nodata()` déclencher) :

```bash
kubectl -n zabbix scale deploy/zabbix-traffic --replicas=0
```

## Comprendre

### Le modèle de données Zabbix

Cinq objets, du plus large au plus fin :

| Objet | Définition |
|---|---|
| *Host group* | regroupement logique d'hôtes (ici `Zabbix servers`) |
| *Host* | la machine supervisée |
| *Item* | une métrique collectée, identifiée par une **clé** (`system.cpu.load[all,avg1]`) |
| *Trigger* | une expression booléenne sur des items ; vraie = *Problem* |
| *Template* | un paquet d'items et de triggers appliqué en masse à des hôtes |

Différence de fond avec le TP3 : en SQL, *vous* écrivez la requête et les
données sont déjà là. Ici, la donnée n'existe que si un item la collecte —
pas d'item, pas de courbe, quelle que soit la requête Grafana. D'où la
première mission ci-dessous : tant que l'interface Agent de l'hôte n'est pas
joignable, `Availability` reste rouge et les items restent vides. Un panel
Zabbix désespérément plat se diagnostique d'abord dans Zabbix, pas dans
Grafana.

**History et trends.** Zabbix conserve les valeurs brutes (*history*) sur une
durée courte, puis n'en garde que des agrégats horaires min/avg/max
(*trends*) sur le long terme. Les réglages `Trends`, `After 7d` et
`Range 4d` de la datasource indiquent à Grafana à partir de quelle ancienneté
basculer sur les trends. Sur une fenêtre de six mois vous lisez donc des
trends : les pics courts ont déjà été lissés par Zabbix à la collecte, pas
par Grafana à l'affichage.

### Le plugin est une *app*, pas seulement une datasource

`alexanderzobnin-zabbix-app` est une **app** Grafana : elle embarque une
datasource, des panels et des dashboards livrés. Une app doit être *activée*
avant que sa datasource soit exploitable — c'est l'origine du message
*Unable to select configuration* sur une datasource dont l'app est restée
désactivée. Ce lab l'active par provisioning (`sidecar.plugins` et une
ConfigMap labellisée `grafana_plugin: "1"` dans `values/grafana-values.yaml`)
: il n'y a rien à cliquer, mais il faut connaître le symptôme, il est
fréquent en production.

### Query modes et fonctions

L'éditeur propose plusieurs *query modes*, qui n'interrogent pas les mêmes
objets : **Metrics** (valeurs d'items, donc des séries temporelles),
**Problems** (triggers actuellement en défaut, donc un tableau), **Triggers**
(comptage d'états). Choisir le mauvais mode donne un panel vide *sans message
d'erreur* — le plugin considère qu'il a répondu correctement, avec zéro
résultat.

Les **fonctions** de l'onglet *Functions* s'appliquent après la récupération,
en pipeline. La nuance à retenir : `groupBy(1m, avg)` agrège chaque série
séparément (n séries en entrée, n en sortie), là où `aggregateBy(1m, avg)`
fusionne toutes les séries en une seule. Confondre les deux fait disparaître
le détail par hôte, silencieusement.

## Rendre l'hôte réellement supervisé

Data collection > Hosts > `Zabbix server` > interface Agent : effacer l'IP,
DNS name `zabbix-agent`, Connect to DNS, port `10050`. Patienter 1-2 min,
Availability passe au vert.

> **Piège connu :** l'agent peut rejeter la connexion
> (`connection from "10.244.0.11" rejected`) car Kubernetes ne réécrit pas
> l'IP source pod-à-pod en IP de Service — l'agent voit l'IP réelle du pod
> serveur, jamais celle du Service, donc une liste blanche par nom ne peut
> jamais matcher. `manifests/zabbix.yaml` désamorce ça avec
> `ZBX_PASSIVESERVERS: "0.0.0.0/0"` (pas `ZBX_SERVER_HOST` — cette variable
> alimente aussi `ServerActive` et refuse la notation CIDR, elle ferait
> planter le conteneur).

## Datasource

Provisionnée (`Zabbix`, plugin `alexanderzobnin-zabbix-app` installé *et*
activé via `values/grafana-values.yaml` — l'app est enable dès le
déploiement, rien à cliquer). Sinon à la main : Administration >
Plugins > Zabbix > Enable, puis Connections > Add new connection > Zabbix
(`http://zabbix-web.zabbix.svc.cluster.local:8080/api_jsonrpc.php`, auth
`Admin`/`zabbix`, Trends actif, After `7d`, Range `4d`, Cache TTL `1h`).

## Panels

| Panel | Query mode | Réglages |
|---|---|---|
| Trafic applicatif | Metrics | Group `Lab apps`, Host `/.*/`, Item `Requests (10s)` |
| Taux d'erreur | Metrics | Group `Lab apps`, Host `/.*/`, Item `Error rate` — seuil à 10 |
| Latence p95 | Metrics | Group `Lab apps`, Host `/.*/`, Item `Latency p95` |
| Items serveur | Metrics | Group `Zabbix servers`, Host `Zabbix server`, Item `Zabbix*` |
| Problèmes | Problems | Group `Lab apps` (ou `Zabbix servers`) |
| Compteur | Triggers | count en état Problem |

Pour les annotations : dans les options du dashboard, *Annotations > New*,
datasource `Zabbix`, group `Lab apps` — les fenêtres d'incident apparaissent
alors en bandes verticales sous les courbes.

Fonctions utiles (onglet Functions) : `groupBy(1m, avg)` (agrège chaque
série individuellement) vs `aggregateBy(1m, avg)` (fusionne toutes les
séries en une), `scale(0.01)`, `movingAverage(10)`, `setAlias(...)`.

Variables `$group` (Group `/.*/`) et `$host` (Host, group `$group`,
`/.*/`) — Repeat by variable `host` sur un panel : avec les trois hôtes de
`Lab apps`, le repeat produit enfin trois panels distincts.

## Dashboards livrés

Datasource Zabbix > onglet Dashboards > importer *Zabbix System Status* et
*Zabbix Server Health*. Génériques et lourds — point de départ, pas cible.

## Critères de réussite

- Un dashboard Zabbix générique avec métrique, problèmes et annotations.
- Au moins un *Problem* observé apparaissant puis se refermant tout seul.
- Savoir dire, pour un item de `Zabbix server`, s'il est collecté ou poussé.

## Pour aller plus loin

Item personnalisé `system.cpu.load[all,avg1]`. Trigger simple et son
apparition dans Problems. Dashboard mixte Zabbix + PostgreSQL sur la même
row. Export CSV d'un item.
