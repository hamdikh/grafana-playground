# Formation Grafana Labs — programme

Formation de 21h (3 jours), Kapheira. Intervenant : Hamdi LION.

## Objectifs et parcours

1. **Installation express** — cluster kind jetable, un seul script.
2. **Utiliser les dashboards** — navigation, plages de temps, variables,
   annotations, Explore, partage et mode kiosk.
3. **Construire les dashboards** — panels, requêtes, transformations,
   galerie de visualisations, réutilisation.
4. **Sources de données** — CSV via Infinity, SQL, Prometheus (PromQL) et
   Zabbix.
5. **Alertes et incidents** — règles sur métriques, points de contact
   (Slack, PagerDuty, Email), politiques et silences.
6. **Logs et traces** — Loki (LogQL) et Tempo (TraceQL), corrélation logs /
   métriques / traces. En démo formateur.
7. **Stockage distribué (Mimir)** — stockage long terme, scalable et
   multi-tenant des métriques. En démo formateur.
8. **Avancé, IaC, RBAC, DaaS** — dashboards dynamiques, provisioning as
   code, sécurité et service.
9. **Récap et pratique** — sept TP guidés, deux démos formateur, un
   mini-projet de synthèse.

## Déroulé des 3 jours

| Créneau | Contenu |
|---|---|
| J1 matin | Introduction, concepts clés, installation du lab, TP1 |
| J1 après-midi | Utiliser les dashboards, TP2 (TestData) |
| J2 matin | Construire les dashboards, sources SQL, TP3 (MySQL) |
| J2 après-midi | PostgreSQL, base interne et haute dispo, TP4 |
| J3 matin | Zabbix (TP5), alerting (TP6) |
| J3 après-midi | IaC, RBAC, DaaS, TP7, démos, mini-projet |

## Ce que ce dépôt couvre

Les TP1-TP7 et l'extension multicanal (`exercises/`) — l'installation,
l'exploitation de dashboards, les sources SQL/Zabbix, l'alerting et le
provisioning as code. Les sections 6 (Loki/Tempo) et 7 (Mimir) du programme
sont traitées en démo formateur sur play.grafana.org dans le cours
original — hors périmètre "hands-on" de ce dépôt.

## Qui est Hamdi LION

Kubestronaut (CKA, CKAD, CKS, KCNA, KCSA, + CAPA, LFCS) et maintainer des
charts Helm Thanos. Platform engineering, Kubernetes, GitOps et cloud.
