# TP1 — Installation express de Grafana avec Helm sur Kind

**Objectif :** monter le cluster jetable et Grafana, socle commun à tous les
TP suivants. **Durée :** 30 min. **Niveau :** débutant.

## Lancer

```bash
./run.sh
# équivalent à :
#   kind create cluster --config ../../kind-config.yaml
#   helm upgrade --install grafana grafana/grafana -n observability \
#     --create-namespace --values ../../values/grafana-values.yaml
```

## Étapes (si vous préférez à la main)

1. Créer le cluster avec `kind-config.yaml` (ports 3000 et 8080 mappés).
2. `helm repo add grafana https://grafana.github.io/helm-charts && helm repo update`
3. Installer Grafana dans le namespace `observability` avec
   `values/grafana-values.yaml`.
4. Se connecter sur http://localhost:3000 (`admin` / `Grafana2025!`) et
   changer le mot de passe.

## À vérifier

```bash
kubectl --context kind-grafana-lab -n observability get pods
# le pod grafana-* doit avoir 3/3 conteneurs prêts :
# grafana, grafana-sc-dashboard, grafana-sc-datasources
```

Ce pattern sidecar (deux sidecars qui surveillent des ConfigMaps labellisées
pour charger dashboards et datasources) ressert tel quel jusqu'au TP7 —
jamais désactivé entre-temps.

## Critères de réussite

- Connections > Data sources affiche `TestData` marquée par défaut, avec un
  bandeau "provisioned".
- Le pod Grafana tourne avec 3/3 conteneurs prêts.

## Pour aller plus loin

- Activer `persistence.enabled: true`, supprimer le pod, comparer le
  comportement (actuellement la base SQLite vit dans un `emptyDir` : tout
  disparaît à la suppression du pod).
- Changer le mot de passe admin par `helm upgrade` : il n'est appliqué qu'à
  la première initialisation de la base ; ensuite il faut `grafana-cli admin
  reset-admin-password` ou l'API.
