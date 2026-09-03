# Grafana Playground

Hands-on Grafana training lab, from a bare `kind` cluster to alerting,
provisioning-as-code and RBAC. Seven exercises (TP1–TP7) plus a
multichannel-alerting extension, each self-contained under `exercises/`
with its own manifests, README and one-command launcher.

Companion materials: [`docs/LAB-MANUAL.md`](docs/LAB-MANUAL.md) (the full
step-by-step manual this repo implements) and
[`docs/PROGRAM.md`](docs/PROGRAM.md) (course overview/schedule).

## Prerequisites

Docker, `kubectl`, `helm`, `kind`, `jq`. 8GB RAM with at least 4GB free for
Docker — Zabbix (TP5) alone needs ~1.5GB, so if you're tight on RAM skip
`tp5`/`zabbix` and everything else still works.

## Quickstart

```bash
git clone git@github.com:hamdikh/grafana-playground.git
cd grafana-playground
./bootstrap.sh          # cluster + Grafana + MySQL + PostgreSQL + Zabbix + alerting
./bootstrap.sh status   # what's up and how to reach it
./scripts/validate.sh   # end-to-end check: is this machine ready for a session?
```

`scripts/validate.sh` is read-only and deploys nothing. Run it with `pre`
before bootstrapping to check the prerequisites alone
(`./scripts/validate.sh pre`). Exercises you haven't run yet are reported
`SKIP`, not `FAIL`, so a machine without Zabbix still validates clean.

Or exercise by exercise — each one bootstraps everything it depends on:

```bash
./exercises/tp3-mysql/run.sh
```

Or declaratively with Helmfile (Grafana + MySQL/PostgreSQL/alerting via
presync hooks; Zabbix stays opt-in, see `helmfile.yaml`):

```bash
kind create cluster --config kind-config.yaml
helmfile apply
```

Grafana: http://localhost:3000 (`admin` / `Grafana2025!`). Zabbix (once
`tp5`/`zabbix` has run): http://localhost:8080 (`Admin` / `zabbix`).

## Exercises

| # | Exercise | Launch | Duration |
|---|----------|--------|----------|
| TP1 | [Installation express](exercises/tp1-installation/) | `./exercises/tp1-installation/run.sh` | 30 min |
| TP2 | [Dashboards & TestData](exercises/tp2-dashboards/) | `./exercises/tp2-dashboards/run.sh` | 60 min |
| TP3 | [MySQL datasource](exercises/tp3-mysql/) | `./exercises/tp3-mysql/run.sh` | 75 min |
| TP4 | [PostgreSQL: datasource + internal DB](exercises/tp4-postgresql/) | `./exercises/tp4-postgresql/run.sh` | 75 min |
| TP5 | [Zabbix](exercises/tp5-zabbix/) | `./exercises/tp5-zabbix/run.sh` | 90 min |
| TP6 | [Alerting & Teams notifications](exercises/tp6-alerting/) | `./exercises/tp6-alerting/run.sh` | 75 min |
| TP7 | [Provisioning as code, RBAC, API](exercises/tp7-provisioning/) | `./exercises/tp7-provisioning/run.sh` | 60 min |
| Ext | [Multichannel alerting (Teams+Slack+Email)](exercises/extension-multichannel-alerting/) | `./exercises/extension-multichannel-alerting/run.sh` | 30–40 min |

TP2–TP7 build on the same cluster started by TP1 — running any later
exercise's `run.sh` bootstraps everything before it too, so you can jump
straight to e.g. `tp6-alerting` on a fresh machine.

## Cleaning up

```bash
./bootstrap.sh clean   # kind delete cluster --name grafana-lab
```

Nothing persists outside the kind cluster (`persistence.enabled: false` in
`values/grafana-values.yaml`) — delete it and you're back to zero.
