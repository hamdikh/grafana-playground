# TP6 — Alerting et notifications Microsoft Teams

**Objectif :** créer une règle d'alerte et la router vers Teams, avec un
repli webhook local. **Durée :** 75 min. **Niveau :** intermédiaire.

Microsoft a retiré les connecteurs Office 365 — les anciennes URL
d'Incoming Webhook Teams ne fonctionnent plus. La voie actuelle passe par un
workflow Power Automate. Toutes les missions ci-dessous marchent sans
tenant Teams, grâce à un récepteur de webhook local ; la dernière mission
en a besoin.

## Lancer

```bash
./run.sh   # tp1 + tp4 + manifests/alerting.yaml (webhook-echo, metrics-feeder, mailhog)
```

`metrics-feeder` insère une mesure par hôte chaque minute dans PostgreSQL —
sans lui, aucune alerte ne se déclenche (les données du TP4 sont figées à
l'instant du déploiement).

## Comprendre

### La chaîne complète

L'alerting unifié enchaîne cinq maillons, chacun avec son vocabulaire :

```
règle → requête + expressions → instances d'alerte → politique de notification → point de contact
        (évaluée périodiquement)  (une par jeu de labels)   (arbre de routage)      (Teams, email, webhook…)
```

Une **règle** ne produit pas « une alerte » mais autant d'**instances** que
de jeux de labels distincts renvoyés par son évaluation. Quatre hôtes en
dépassement, c'est quatre instances indépendantes : chacune a son état, son
historique, et peut être mise en silence séparément.

**Les labels sont l'identité d'une instance.** C'est par eux que la politique
route, groupe et déduplique. C'est aussi la clé du piège documenté plus bas :
si les séries ne portent pas de vrais labels, Grafana ne peut plus les
distinguer et refuse purement et simplement d'évaluer la règle.

### Requête, expressions, et pourquoi le format Table

Une règle se compose d'une requête (`A`) et d'**expressions** qui la
transforment, chacune identifiée par son `refId` :

- *Reduce* ramène une série temporelle à une valeur unique (`Last`, `Mean`…).
  Nécessaire quand la requête rend une courbe, puisqu'une alerte se décide
  sur un nombre, pas sur une courbe.
- *Threshold* compare à un seuil et rend 0 ou 1 : c'est la condition.
- *Math* permet de combiner plusieurs entrées (`$B > 80 && $C < 10`).

Ici la requête agrège déjà par hôte en SQL et rend un **tableau** : une ligne
par hôte, une colonne valeur, et les autres colonnes deviennent des labels.
Reduce est donc inutile — et nuisible, voir l'encadré ci-dessous. La règle
générale à retenir : avec une datasource SQL, agréger dans la base et
renvoyer du Table donne des labels propres ; c'est plus simple et moins
coûteux que de rapatrier des séries pour les réduire ensuite.

### Les états, et les deux durées qu'on confond

| État | Signification |
|---|---|
| `Normal` | la condition est fausse |
| `Pending` | la condition est vraie, mais depuis moins longtemps que la *pending period* |
| `Alerting` | la condition est vraie depuis assez longtemps — c'est ici, et seulement ici, que la notification part |
| `NoData` / `Error` | la requête n'a rien rendu / a échoué (comportement configurable par règle) |

Deux durées à ne pas mélanger :

- l'**intervalle d'évaluation**, réglé sur le *groupe* de règles : à quelle
  fréquence la condition est testée ;
- la **pending period**, réglée sur la *règle* : combien de temps la
  condition doit rester vraie avant de déclencher.

Une pending period de `2m` avec une évaluation à `1m` exige deux évaluations
consécutives en dépassement. Son rôle est d'absorber le pic d'une mesure
isolée. Trop courte, elle produit du bruit ; trop longue, on croit à une
panne de l'alerting alors que la règle est simplement encore en `Pending`.

### La politique de notification est un arbre

Chaque instance descend depuis la racine et emprunte la première route dont
les *matchers* correspondent — l'option *Continue matching* permettant d'en
emprunter plusieurs, ce dont se sert l'extension multicanal. Les quatre
paramètres de temporisation détaillés plus bas règlent le regroupement, et
c'est `group_by` qui définit ce qu'est « un message » : selon lui, vos quatre
hôtes arrivent en un seul message ou en quatre.

**Silence et mute timing** font tous deux taire une notification sans changer
l'état de la règle, mais ne répondent pas au même besoin : un *silence* est
ponctuel et se cible par labels (« db01, 30 minutes, on est au courant »), un
*mute timing* est récurrent et se cible par plage horaire (« jamais la
nuit »). Dans les deux cas la règle continue d'évaluer et de basculer en
`Alerting` : c'est l'envoi qui est supprimé, pas la détection.

## Contact point webhook et lecture du payload

Alerting > Contact points > Add — Name `webhook-local`, Integration
Webhook, URL `http://webhook-echo.lab.svc.cluster.local:8080/`. Bouton
Test, puis :

```bash
kubectl --context kind-grafana-lab -n lab logs -f deploy/webhook-echo
```

Le `groupKey` du payload est calculé depuis le `group by` de la politique —
c'est lui qui détermine si deux alertes arrivent dans le même message.

## Règle d'alerte "CPU élevé"

Requête A, datasource PostgreSQL-Lab, `now-5m` à `now`, **format Table**
(pas Time series) :

```sql
SELECT host, avg(cpu) AS value FROM metrics WHERE $__timeFilter(ts) GROUP BY host
```

Expression C (Threshold) — entrée `A`, `IS ABOVE 20`. Alert condition: `C`.
**Pas d'expression Reduce entre les deux.**

> **Piège vérifié :** le pipeline classique Query > Reduce > Threshold (A en
> Time series avec `host AS metric`, puis Reduce Last) échoue avec
> `invalid format of evaluation results ... has duplicate results with
> labels {}`. Une requête SQL en `metric AS host` génère une série par hôte,
> mais chacune est identifiée par le *nom* du champ, jamais par un vrai
> label — Reduce ne peut pas les distinguer. La requête qui marche fait
> l'agrégation par hôte directement en SQL et renvoie un **tableau** (une
> ligne par hôte) : Grafana transforme alors chaque colonne autre que la
> valeur (ici `host`) en label sur l'instance d'alerte correspondante.

Évaluation : folder `Alertes`, group `1m`, pending period `2m`. Séquence
observée : Normal → Pending (2 évaluations en dépassement) → Alerting —
c'est seulement là que la notification part.

Labels `severity=critical`, `equipe=infra`. Annotations :
`summary: CPU a {{ $values.A }} % sur {{ $labels.host }}`.

## Politique de notification

Par défaut : `webhook-local`, group by `alertname, host`, group wait `30s`,
group interval `5m`, repeat interval `4h`. Route imbriquée :
`severity = critical` → `teams-prod`, group wait `10s`, repeat interval
`1h`.

| Paramètre | Rôle |
|---|---|
| `group_by` | ce qui définit un groupe, donc un message |
| `group_wait` | délai avant le premier envoi |
| `group_interval` | délai avant d'envoyer les nouveautés d'un groupe déjà notifié |
| `repeat_interval` | fréquence de rappel tant que le problème dure |

## Mute timing et silence

Mute timing `nuit-et-weekend` (20:00–08:00 + weekend, `Europe/Paris`) sur la
route critique. Silence ponctuel : `host = db01`, 30 min, commentaire
obligatoire.

## Contact point Teams réel

Teams : canal > **Workflows** > modèle *"Post to a channel when a webhook
request is received"* > copier l'URL générée (canal privé : passer *Post
as* sur *User*). Grafana : Add contact point, intégration *Microsoft
Teams*, coller l'URL.

## Critères de réussite

- Une règle d'alerte génère une instance par hôte en dépassement.
- Vous savez décrire Normal/Pending/Alerting/NoData et la différence entre
  intervalle d'évaluation et pending period.

## Pour aller plus loin

Alerte deadman (No data → Alerting) pour détecter l'arrêt du feeder :

```bash
kubectl --context kind-grafana-lab -n lab patch cronjob metrics-feeder -p '{"spec":{"suspend":true}}'
```

Export des règles en YAML (Alert rules > Export rules) — directement
réutilisable en provisioning, transition vers TP7.

## Aller plus loin : multicanal

Voir [`../extension-multichannel-alerting/`](../extension-multichannel-alerting/)
pour router une même règle vers Teams **+** Slack **+** email (MailHog) en
même temps, avec templates partagés et time intervals.
