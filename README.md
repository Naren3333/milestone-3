# ESMOS Healthcare Go-Live

This repository now supports the architecture the team is actually using:

- `Moodle` is self-hosted in Docker and can be deployed to AKS
- `Odoo Helpdesk` is provided by an external Odoo Online Enterprise trial
- the systems are integrated through a process workflow, not APIs or SSO

## Solution overview

- `Moodle` delivers the mandatory compliance training course
- `MariaDB` stores Moodle data
- `Odoo Online Helpdesk` manages access-request tickets, proof review, and approval history
- Docker Compose is the baseline deployment path for Moodle
- Kubernetes manifests are included for an AKS deployment of Moodle
- The Moodle container is pinned to `bitnamilegacy/moodle:5.0.2`
- Moodle persists both `/bitnami/moodle` and `/bitnami/moodledata` so first-run bootstrap is retained across container restarts

## Repository layout

- `docker-compose.yml`: local Moodle deployment
- `k8s/`: AKS-ready Moodle manifests
- `docs/service-design.md`: service strategy and architecture
- `docs/change-package.md`: non-functional change package
- `docs/service-operations.md`: operations runbook
- `docs/odoo-online-helpdesk.md`: Odoo trial setup for Helpdesk

## Quick start with Docker Compose

1. Copy `.env.example` to `.env`.
2. Replace the Moodle database and admin passwords.
3. Run `docker compose --env-file .env up -d`.
4. Open Moodle at `http://localhost:8080`.
5. Use your Odoo Online trial separately for Helpdesk.

## Kubernetes deployment

1. Review `k8s/secrets.template.yaml` and replace the placeholder values.
2. Update the Moodle hostname in `k8s/ingress.yaml`.
3. Apply the manifests with `kubectl apply -k k8s`.
4. Point internal DNS for Moodle to the ingress controller.
5. Restrict Moodle access to internal CIDRs only.

## Final architecture

- Moodle is the self-hosted, containerized workload
- Odoo Helpdesk is an externally managed SaaS dependency
- Integration happens through:
  - course assignment in Odoo tickets
  - training completion in Moodle
  - screenshot or document proof uploaded back into Odoo Helpdesk
  - support approval and account creation in Odoo