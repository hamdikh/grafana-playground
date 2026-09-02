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

Provisionnée (`Zabbix`, plugin `alexanderzobnin-zabbix-app` déjà installé
via `values/grafana-values.yaml`). Sinon à la main : Administration >
Plugins > Zabbix > Enable, puis Connections > Add new connection > Zabbix
(`http://zabbix-web.zabbix.svc.cluster.local:8080/api_jsonrpc.php`, auth
`Admin`/`zabbix`, Trends actif, After `7d`, Range `4d`, Cache TTL `1h`).

## Panels

| Panel | Query mode | Réglages |
|---|---|---|
| Items serveur | Metrics | Group `Zabbix servers`, Host `Zabbix server`, Item `Zabbix*` |
| Problèmes | Problems | Group `Zabbix servers` |
| Compteur | Triggers | count en état Problem |

Fonctions utiles (onglet Functions) : `groupBy(1m, avg)` (agrège chaque
série individuellement) vs `aggregateBy(1m, avg)` (fusionne toutes les
séries en une), `scale(0.01)`, `movingAverage(10)`, `setAlias(...)`.

Variables `$group` (Group `/.*/`) et `$host` (Host, group `$group`,
`/.*/`) — Repeat by variable `host` sur un panel.

## Dashboards livrés

Datasource Zabbix > onglet Dashboards > importer *Zabbix System Status* et
*Zabbix Server Health*. Génériques et lourds — point de départ, pas cible.

## Critères de réussite

- Un dashboard Zabbix générique avec métrique, problèmes et annotations.

## Pour aller plus loin

Item personnalisé `system.cpu.load[all,avg1]`. Trigger simple et son
apparition dans Problems. Dashboard mixte Zabbix + PostgreSQL sur la même
row. Export CSV d'un item.
