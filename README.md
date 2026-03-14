# ESMOS Healthcare Go-Live

This repository is a Odoo + Moodle healthcare scenario:

- Docker Compose for a low-cost single-host deployment
- AKS-ready Kubernetes manifests for the advanced deployment path
- Documentation for service strategy, change management, and operations

## Solution overview

- `Odoo` provides ERP and helpdesk workflows for access requests, proof uploads, and support tracking.
- `Moodle` provides mandatory compliance training for internal staff.
- `PostgreSQL` stores Odoo data.
- `MariaDB` stores Moodle data.
- Docker Compose is the baseline deployment path
- Kubernetes manifests are included for an AKS-based bonus or stretch deployment using the same logical architecture.
- The Moodle container is pinned to `bitnamilegacy/moodle:5.0.2`
- Moodle persists both `/bitnami/moodle` and `/bitnami/moodledata` so first-run bootstrap is retained across container restarts.

## Quick start with Docker Compose
1. Run `docker compose --env-file .env up -d`.
2. Open:
   - Odoo: `http://localhost:8069`
   - Moodle: `http://localhost:8080`

## Kubernetes deployment

1. Review `k8s/secrets.template.yaml` and replace the placeholder values.
2. Update ingress hostnames in `k8s/ingress.yaml`.
3. Apply the manifests with `kubectl apply -k k8s`.
4. Point internal DNS names to the ingress controller.
5. Restrict Moodle access to internal CIDRs only.