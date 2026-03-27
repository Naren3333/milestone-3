# ESMOS Healthcare Go-Live

This repository now supports the architecture the team is actually using:

- `Moodle` is self-hosted in Docker and can be deployed to a single-node Kubernetes VM
- `Odoo Helpdesk` is provided by an external Odoo Online Enterprise trial
- the systems are integrated through a process workflow, not APIs or SSO

## Solution overview

- `Moodle` delivers the mandatory compliance training course
- `MariaDB` stores Moodle data
- `Uptime Kuma` provides a lightweight uptime dashboard for Moodle
- `Odoo Online Helpdesk` manages access-request tickets, proof review, and approval history
- Docker Compose is the baseline deployment path for Moodle
- Kubernetes manifests are included for a single-node Linux VM deployment of Moodle
- The Moodle container is built from the official `moodlehq/moodle-php-apache:8.1` image and installs the official Moodle 4.5 release stream during build
- Moodle persists `/var/moodledata` while the application code is baked into the image

## Repository layout

- `docker-compose.yml`: local Moodle deployment
- `docker/moodlehq/`: Moodle HQ-based Docker build and startup logic
- `k8s/`: K3s-ready Moodle manifests for a single Linux VM
- `deploy/nginx/`: host Nginx reverse-proxy template for HTTPS and domain routing
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
6. Open Uptime Kuma at `http://localhost:3001` and create the first admin account.
7. In Uptime Kuma, add an HTTP monitor for `http://moodle/login/index.php` so the check runs from inside the Docker network.
8. Use your Odoo Online trial separately for Helpdesk.

## Kubernetes deployment on a single VM with Nginx HTTPS

1. Provision a Linux VM with Docker, `curl`, and enough free disk for Moodle, MariaDB, and persistent volumes.
2. Point your DNS records at the VM public IP:
   - `moodle.yourdomain.com` -> VM public IP
   - `status.yourdomain.com` -> VM public IP
3. Install K3s on the VM with Traefik disabled:
   `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -`
4. Confirm the cluster is ready:
   `sudo kubectl get nodes`
5. Build the Moodle image from `docker/moodlehq/Dockerfile`, push it to your registry, and replace `chocobar333/esmos-moodlehq:4.5` in `k8s/moodle.yaml` if you want to use your own image.
6. Edit `k8s/secrets.template.yaml` and replace:
   - `MARIADB_ROOT_PASSWORD`
   - `MOODLE_DATABASE_PASSWORD`
   - `MOODLE_ADMIN_PASSWORD`
   - `MOODLE_ADMIN_EMAIL`
   - `MOODLE_WWWROOT` with `https://moodle.yourdomain.com`
7. Apply the manifests:
   `sudo kubectl apply -k k8s`
8. Wait for the workloads:
   `sudo kubectl -n esmos get pods`
9. Install Nginx on the VM and copy `deploy/nginx/esmos.conf.example` into your Nginx sites-enabled path.
10. Replace the example hostnames in that file with your real domains:
   - `moodle.yourdomain.com`
   - `status.yourdomain.com`
11. Test and reload Nginx:
   `sudo nginx -t && sudo systemctl reload nginx`
12. Use Certbot with the Nginx plugin to issue and install HTTPS certificates:
   `sudo certbot --nginx -d moodle.yourdomain.com -d status.yourdomain.com`
13. Open:
   - Moodle: `https://moodle.yourdomain.com/`
   - Uptime Kuma: `https://status.yourdomain.com/`
14. In Uptime Kuma, create the first admin account, then add an HTTP monitor for `https://moodle.yourdomain.com/login/index.php`

Useful checks:

- `sudo kubectl -n esmos get svc,pvc`
- `sudo kubectl -n esmos logs deploy/moodle`
- `sudo kubectl -n esmos logs deploy/uptimekuma`
- `sudo kubectl -n esmos get svc moodle uptimekuma`
- `curl -I http://127.0.0.1:30080/login/index.php`
- `curl -I http://127.0.0.1:30081/`

If the VM firewall is enabled, allow inbound TCP ports `80` and `443`. Moodle and Uptime Kuma stay on local Kubernetes NodePorts `30080` and `30081` behind Nginx.

## Final architecture

- Moodle is the self-hosted, containerized workload
- Uptime Kuma runs beside Moodle for VM-level uptime visibility
- Odoo Helpdesk is an externally managed SaaS dependency
- Integration happens through:
  - course assignment in Odoo tickets
  - training completion in Moodle
  - screenshot or document proof uploaded back into Odoo Helpdesk
  - support approval and account creation in Odoo
