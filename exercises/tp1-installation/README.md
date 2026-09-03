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

## Comprendre

Quatre briques empilées. Savoir laquelle fait quoi évite de chercher une
panne au mauvais étage.

**kind** (*Kubernetes in Docker*) fait tourner un cluster complet dans un
conteneur Docker : le « nœud » est un conteneur, les pods tournent dedans.
Conséquence directe, le cluster n'a pas d'adresse routable depuis votre
poste. C'est pourquoi `kind-config.yaml` déclare des `extraPortMappings` :
ils percent le conteneur-nœud pour exposer 3000 et 8080 sur `localhost`.
Sans eux, il faudrait un `kubectl port-forward` à chaque fois.

**Helm** est le gestionnaire de paquets de Kubernetes. Trois mots à
distinguer :

| Terme | Ce que c'est |
|---|---|
| *chart* | le paquet : des manifests Kubernetes écrits en templates Go |
| *values* | vos réglages, qui alimentent ces templates (`grafana-values.yaml`) |
| *release* | une installation nommée du chart dans le cluster (ici `grafana`) |

`helm upgrade --install` est idempotent : première exécution = installation,
suivantes = mise à jour. C'est ce qui rend `./bootstrap.sh` rejouable sans
risque, autant de fois que nécessaire.

**Le chemin réseau fait trois sauts.** Grafana écoute sur 3000 dans le pod,
le Service de type NodePort le publie sur le port 30000 du nœud, et le
mapping kind relie ce 30000 au 3000 de votre poste. Trois sauts, trois
endroits où ça peut casser — utile à garder en tête quand `localhost:3000`
ne répond pas.

**Le pattern sidecar** est la brique la plus structurante du lab. Le pod
Grafana contient trois conteneurs : Grafana lui-même, et deux sidecars qui
surveillent en permanence l'API Kubernetes. Dès qu'une ConfigMap portant le
label `grafana_dashboard: "1"` (ou `grafana_datasource: "1"`) apparaît dans
le cluster, le sidecar en écrit le contenu dans un fichier du répertoire de
provisioning, que Grafana charge. C'est ce mécanisme qui rend le TP7
possible : livrer un dashboard reviendra à créer une ConfigMap, sans jamais
toucher à l'interface ni redémarrer quoi que ce soit.

**L'état est jetable, et c'est voulu.** Avec `persistence.enabled: false`,
la base SQLite interne de Grafana vit dans un `emptyDir`, effacé avec le
pod. Tout ce que vous créez à la souris disparaît si le pod redémarre ;
seul ce qui est provisionné par fichier survit. Retenez-le, c'est
l'argument central du TP7.

Dernier point contre-intuitif : `adminPassword` dans les values n'est
appliqué qu'à la **première** initialisation de la base. Un `helm upgrade`
avec un nouveau mot de passe ne le changera pas — il faudra passer par
`grafana-cli admin reset-admin-password` ou l'API.

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
