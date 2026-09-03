# TP2 — Dashboards et datasource TestData

**Objectif :** prendre en main panels, options et variables, sans dépendre
d'une base externe. **Durée :** 60 min. **Niveau :** débutant.

## Lancer

```bash
./run.sh   # tp1 + rien d'autre à déployer : tout se fait avec TestData
```

## Comprendre

### Le chemin d'une donnée jusqu'au pixel

Un panel enchaîne toujours les mêmes quatre étapes :

```
datasource → query → [data frame] → transformations → visualisation
```

Le **data frame** est le format tabulaire interne de Grafana : des colonnes
typées (`time`, `number`, `string`) avec leurs métadonnées. Toute
datasource, qu'elle interroge du SQL, Prometheus ou un CSV collé à la main,
rend des data frames — c'est ce qui permet à n'importe quelle visualisation
d'afficher n'importe quelle source.

Deux conséquences pratiques :

- **La visualisation ne modifie jamais les données.** Passer d'un Time
  series à un Table ne fait que relire le même frame autrement. Si un panel
  est vide, le problème est en amont — jamais dans le choix du graphique.
- **Les transformations tournent dans le navigateur**, après la requête, sur
  les données déjà rapatriées. C'est instantané et sans SQL à écrire, mais
  ça ne soulage pas la base : filtrer 10 000 lignes en transformation, c'est
  avoir transféré 10 000 lignes. Dès le TP3, on filtrera à la source.

### Panel inspect, l'outil de diagnostic

`Panel inspect` (menu du panel) montre les couches séparément : *Data* (le
frame tel que le reçoit la visualisation), *Stats* (le temps de requête) et
*Query* (ce qui est réellement parti vers la datasource). C'est le premier
réflexe devant un panel qui n'affiche pas ce qu'on attend, et il servira à
chaque TP suivant.

### Variables

Une variable est un texte substitué dans les requêtes **avant** leur envoi :
`$env` n'existe pas côté base, Grafana remplace la chaîne puis exécute. Deux
types ici : *Custom* (liste écrite à la main) et, dès le TP3, *Query* (la
liste est elle-même le résultat d'une requête, donc elle se met à jour
toute seule).

### JSON model, versions et export

Un dashboard **est** un document JSON ; l'interface n'en est qu'un éditeur.
D'où deux mécanismes à ne pas confondre :

- **Versions** — chaque sauvegarde empile une version restaurable. C'est du
  versionnage *dans la base Grafana*, pas du Git : ça disparaît avec la base
  (voir TP1) et ça ne se relit pas en revue de code.
- **Export** — l'option *Export the dashboard to use in another instance*
  remplace les UID de datasource codés en dur par une entrée `DS_*` demandée
  à l'import. Sans elle, le JSON référence l'UID de *cette* instance et le
  dashboard sera vide ailleurs. Ce lab fixe volontairement des UID stables
  (`testdata`, `mysql-lab`, `pg-lab`, `zabbix`) dans
  `values/grafana-values.yaml` : c'est la parade inverse, celle qu'on
  utilise en entreprise pour que les mêmes UID existent sur tous les
  environnements.

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
