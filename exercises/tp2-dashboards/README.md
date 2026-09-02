# TP2 — Dashboards et datasource TestData

**Objectif :** prendre en main panels, options et variables, sans dépendre
d'une base externe. **Durée :** 60 min. **Niveau :** débutant.

## Lancer

```bash
./run.sh   # tp1 + rien d'autre à déployer : tout se fait avec TestData
```

## Étapes

1. **Panel Time series** — Add visualization > datasource TestData >
   Scenario `Random Walk`. Trois queries A/B/C, alias `web01`/`web02`/`db01`.
   Standard options : Unit `Misc > Percent (0-100)`, Min 0, Max 100.
   Thresholds à 70 (orange) et 90 (rouge). Legend Table, Last/Mean/Max.
2. **Cinq panels supplémentaires** :

   | Panel | Scenario | Visualisation |
   |---|---|---|
   | CPU moyen | Random Walk | Stat (Mean) |
   | Charge instantanée | Random Walk | Gauge |
   | Répartition | CSV Content | Bar chart |
   | Inventaire | CSV Content | Table |
   | Logs applicatifs | Logs (50 lignes) | Logs |

   Coller le contenu de [`csv/inventory.csv`](csv/inventory.csv) dans le
   champ CSV Content.
3. **Transformations** sur *Inventaire* : `Organize fields by name` (renommer
   `host`→Hôte, `cpu`→CPU), `Filter data by values` (`env` Matches `prod`),
   Cell type Gauge sur CPU.
4. **Bar chart Répartition** : transformation `Group by` — `env` en Group
   by, `cpu` en Calculate Mean.
5. **Rows** — Add > Row : *Vue globale* et *Détail par hôte*, glisser les
   panels dedans.
6. **Variable** — Dashboard settings > Variables > `env`, type Custom,
   values `prod,staging`. Panel Text (Markdown) : `Environnement
   sélectionné : $env`.
7. **Versions** — Dashboard settings > Versions, sélectionner une version
   antérieure, `Restore`.
8. **Export/Import** — Share > Export > activer *Export the dashboard to use
   in another instance*. Sans cette option, l'UID de datasource est écrit en
   dur et le dashboard ne fonctionne que sur cette instance.

## Critères de réussite

- Vous savez expliquer la différence entre le JSON model interne et l'export
  pour partage externe.
- Le dashboard réimporté fonctionne sans modification manuelle des UID (les
  UID de `values/grafana-values.yaml` sont fixes — `testdata`, `mysql-lab`,
  etc. — exactement pour rendre cet export sûr).

## Pour aller plus loin

Scénario `Slow Query` à 5s de latence. Lien de dashboard vers le dashboard
importé. Extraction CSV d'un panel via Panel inspect.
