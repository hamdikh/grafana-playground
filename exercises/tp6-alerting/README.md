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
