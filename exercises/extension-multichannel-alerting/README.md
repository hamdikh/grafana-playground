# Extension — notifier en temps réel sur Teams, Slack et email

Bloc à insérer après TP6 mission 10. Aucune renumérotation des TP
existants. **Durée ajoutée :** 30-40 min.

## Objectif

Router une même règle d'alerte vers trois canaux différents selon le label
`severity`, avec un contenu de message unifié, et voir les trois
notifications arriver en direct pendant la séance.

## Prérequis

MailHog et le SMTP Grafana (voir `manifests/alerting.yaml` /
`values/grafana-values.yaml` du TP6, déjà en place si vous avez lancé
`tp6-alerting`).

```bash
./run.sh   # = ../tp6-alerting/run.sh
kubectl --context kind-grafana-lab -n lab port-forward svc/mailhog 8025:8025 &
```

MailHog est accessible sur http://localhost:8025 et capture tout ce que
Grafana envoie — aucun compte email réel n'est nécessaire.

## Missions

1. Vérifier que le SMTP répond : Alerting > Contact points, éditer
   `grafana-default-email`, bouton Test. Le message doit apparaître dans
   MailHog en moins de 5 secondes. Si rien n'arrive, consulter l'onglet
   *Notifications* du point de contact plutôt que les logs.

2. Créer trois points de contact distincts, un par canal :

   | Nom | Intégration | Paramètre principal |
   |---|---|---|
   | `email-ops` | Email | `ops@formation.local` |
   | `slack-alerts` | Slack | URL du webhook entrant |
   | `teams-alerts` | Microsoft Teams | URL du workflow (TP6 mission 9) |

   Pour Slack : api.slack.com > Your apps > Create New App > From scratch >
   Incoming Webhooks > Add New Webhook to Workspace. Tester chaque point de
   contact avant de continuer.

3. Créer un template de notification `tp-templates` partagé par les trois
   canaux (voir `alerting-provisioning.tpl.yaml`), puis le référencer dans
   les trois points de contact (Title/Text ou Subject/Message selon le
   canal) :

   ```gotemplate
   {{ define "tp.title" }}[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }} ({{ .CommonLabels.severity }}){{ end }}

   {{ define "tp.message" }}
   {{ len .Alerts.Firing }} alerte(s) active(s) et {{ len .Alerts.Resolved }} résolue(s)
   {{ range .Alerts }}
   Hôte : {{ .Labels.host }}
   Valeur mesurée : {{ index .Values "B" }}
   Résumé : {{ .Annotations.summary }}
   Dashboard : {{ .DashboardURL }}
   Silence : {{ .SilenceURL }}
   {{ end }}
   {{ end }}
   ```

   `{{ index .Values "B" }}` correspond au `refId` de l'expression Reduce —
   le template ne connaît que le *résultat* des expressions, pas la requête.

4. Compléter la politique de notification avec trois routes enfants, régler
   les timings de la route racine sur Group wait `10s`, Group interval
   `30s`, Repeat interval `5m` :

   | Route | Matcher | Point de contact | Continue matching |
   |---|---|---|---|
   | 1 | `severity = critical` | `teams-alerts` | oui |
   | 2 | `severity = critical` | `email-ops` | oui |
   | 3 | `severity = warning` | `slack-alerts` | non |

5. Rendre et appliquer la config (webhook URLs jamais commitées, voir
   `render.sh`) :

   ```bash
   export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx"
   export TEAMS_WORKFLOW_URL="https://prod-xx.westeurope.logic.azure.com/workflows/..."
   ./render.sh
   kubectl --context kind-grafana-lab apply -f alerting-configmap.yaml
   ```

6. Déclencher l'alerte en direct — écran partagé en trois zones : Grafana à
   gauche, MailHog et le canal Teams ou Slack à droite. `metrics-feeder`
   alimente déjà PostgreSQL, il suffit de forcer une valeur au-dessus du
   seuil :

   ```bash
   kubectl --context kind-grafana-lab -n lab exec deploy/postgres -- \
     psql -U grafana -d metricsdb -c \
     "INSERT INTO metrics (ts, host, env, cpu, mem) VALUES (now(), 'web01', 'prod', 95, 60);"
   ```

   Chronométrer, puis revenir sous le seuil et observer le message
   `RESOLVED` sur les trois canaux :

   ```bash
   kubectl --context kind-grafana-lab -n lab exec deploy/postgres -- \
     psql -U grafana -d metricsdb -c \
     "INSERT INTO metrics (ts, host, env, cpu, mem) VALUES (now(), 'web01', 'prod', 12, 40);"
   ```

   Basculer le label de la règle de `critical` vers `warning`, redéclencher :
   seul Slack doit recevoir la notification. Remettre `critical` ensuite.

## Chronologie attendue (mission 6)

| T | Ce qui se passe | Où le voir |
|---|---|---|
| 0s | insertion de la valeur 95 | terminal |
| 0–10s | évaluation, passage en `Alerting` | page Alert rules |
| +10s | fin du group wait, envoi | onglet Notifications du point de contact |
| +10–15s | messages dans Teams, Slack, MailHog | les trois clients |

## Critères de réussite

- Le test du point de contact email arrive dans MailHog.
- Les tests Slack et Teams arrivent dans leurs canaux respectifs.
- Une valeur à 95 déclenche les trois notifications en moins de 30 secondes.
- Le passage en `warning` n'envoie plus que sur Slack.
- Le retour sous le seuil génère un message `RESOLVED` dont le titre change
  automatiquement.
- Un silence actif bloque la notification sans modifier l'état de la règle.

## Pièges à anticiper

- SMTP non activé dans Grafana → l'intégration email échoue en silence, le
  diagnostic se trouve dans l'onglet Notifications du point de contact, pas
  dans les logs du pod.
- Pending period trop longue → la règle reste en `Pending`, on croit à une
  panne.
- Group wait laissé à sa valeur par défaut de 30s → même effet.
- URL de workflow Teams expirée ou workflow désactivé côté Power Automate →
  vérifier l'historique d'exécution du workflow.
- Slack tronque les messages longs → ne pas boucler sur des dizaines
  d'alertes dans le template.
- MailHog n'est plus maintenu depuis plusieurs années (sans incidence sur le
  lab) — Mailpit en est le successeur si vous voulez l'installer en interne.

## Plan B sans Slack ni Teams

Le point de contact `webhook-local` du TP6 (pod `webhook-echo`) suffit :

```bash
kubectl --context kind-grafana-lab -n lab logs -f deploy/webhook-echo
```

Le JSON complet apparaît avec `status`, `alerts`, `commonLabels` et
`externalURL` — utile même pour les stagiaires équipés, c'est le meilleur
moyen de montrer ce que Grafana envoie réellement avant transformation par
Slack ou Teams.

## Pour aller plus loin

Regrouper par `host` dans la route racine et comparer le nombre de messages
reçus. Placer les trois intégrations dans un seul point de contact et
discuter du cas où c'est préférable à trois routes. Exporter la politique de
notification au format YAML depuis l'interface, en vue du TP7.
