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
- The Moodle container is built from the official `moodlehq/moodle-php-apache:8.1` image and installs the official Moodle 4.5 release stream during build
- Moodle persists `/var/moodledata` while the application code is baked into the image

## Repository layout

- `docker-compose.yml`: local Moodle deployment
- `docker/moodlehq/`: Moodle HQ-based Docker build and startup logic
- `k8s/`: AKS-ready Moodle manifests
- `docs/service-design.md`: service strategy and architecture
- `docs/change-package.md`: non-functional change package
- `docs/service-operations.md`: operations runbook
- `docs/odoo-online-helpdesk.md`: Odoo trial setup for Helpdesk

## Quick start with Docker Compose

1. Copy `.env.example` to `.env`.
2. Replace the Moodle database and admin passwords.
3. If you have already started the old `5.0.2` stack, run `docker compose --env-file .env down -v` once so Docker creates a fresh Moodle 4.5 database and data volume.
4. Run `docker compose --env-file .env up -d --build`.
5. Open Moodle at `http://localhost:8080`.
6. Use your Odoo Online trial separately for Helpdesk.

## Kubernetes deployment

1. Build the Moodle image from `docker/moodlehq/Dockerfile`, push it to your registry, and replace `esmos-moodlehq:4.5` in `k8s/moodle.yaml` with that registry URL.
2. Review `k8s/secrets.template.yaml` and replace the placeholder values.
3. Update the Moodle hostname in `k8s/ingress.yaml` if needed.
4. If the cluster has old Moodle `5.0` PVCs, remove them or keep the new `*-405-*` PVC names so the downgrade does not reuse incompatible data.
5. Apply the manifests with `kubectl apply -k k8s`.
6. Point internal DNS for Moodle to the ingress controller.
7. Restrict Moodle access to internal CIDRs only.

## Final architecture

- Moodle is the self-hosted, containerized workload
- Odoo Helpdesk is an externally managed SaaS dependency
- Integration happens through:
  - course assignment in Odoo tickets
  - training completion in Moodle
  - screenshot or document proof uploaded back into Odoo Helpdesk
  - support approval and account creation in Odoo
