# ESMOS Healthcare Go-Live

This repo runs:

- `Moodle` as the self-hosted training platform
- `MariaDB` as the Moodle database
- `Uptime Kuma` for uptime monitoring
- `Odoo Online Helpdesk` as the external ticketing system

## Repo layout

- `docker-compose.yml`: local Docker Compose stack
- `k8s/`: single-VM K3s deployment manifests
- `deploy/nginx/`: Nginx reverse-proxy template for domains and HTTPS
- `docker/moodlehq/`: Moodle image build files

## Local run with Docker Compose

1. Copy `.env.example` to `.env`.
2. Replace the placeholder passwords.
3. Start the stack:
   `docker compose --env-file .env up -d --build`
4. Open:
   - Moodle: `http://localhost:8080`
   - Uptime Kuma: `http://localhost:3001`
5. In Uptime Kuma, add a monitor for:
   `http://moodle/login/index.php`

## Production VM with K3s + Nginx + HTTPS

Current VM details:

- OS: `Ubuntu 24.04`
- Size: `Standard B2als v2`
- Public IP: `40.81.228.67`
- Azure DNS: `moodlestaging.centralindia.cloudapp.azure.com`

1. Use the current Azure DNS name for Moodle:
   `moodlestaging.centralindia.cloudapp.azure.com`
2. Install K3s without Traefik:
   `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -`
3. Check the cluster:
   `sudo kubectl get nodes`
4. Edit `k8s/secrets.template.yaml` and set:
   - strong database and admin passwords
   - `MOODLE_WWWROOT=https://moodlestaging.centralindia.cloudapp.azure.com`
   - `MOODLE_REVERSE_PROXY="0"`
   - `MOODLE_SSL_PROXY="1"`
5. Apply the manifests:
   `sudo kubectl apply -k k8s`
   This also updates the mounted Moodle entrypoint script, so HTTPS proxy fixes can be picked up without rebuilding the container image.
6. Wait for pods:
   `sudo kubectl -n esmos get pods`
7. Install Nginx on the VM.
8. Copy `deploy/nginx/esmos.conf.example` into your Nginx config.
9. Reload Nginx:
   `sudo nginx -t && sudo systemctl reload nginx`
10. Install HTTPS certificates:
   `sudo certbot --nginx -d moodlestaging.centralindia.cloudapp.azure.com`
11. Open:
   - Moodle: `https://moodlestaging.centralindia.cloudapp.azure.com`
   - Uptime Kuma on the VM itself: `http://127.0.0.1:30081`
12. In Uptime Kuma, add a monitor for:
   `https://moodlestaging.centralindia.cloudapp.azure.com/login/index.php`

## Optional custom domain later

If you later connect your own domain:

- point `moodle.yourdomain.com` to `40.81.228.67`
- update `MOODLE_WWWROOT` in `k8s/secrets.template.yaml`
- update the Nginx `server_name`
- rerun:
  `sudo certbot --nginx -d moodle.yourdomain.com`

If you want public HTTPS for Uptime Kuma too, add a second hostname such as `status.yourdomain.com`, update the second Nginx server block, and run:
`sudo certbot --nginx -d status.yourdomain.com`

## Useful checks

- `sudo kubectl -n esmos get svc,pvc`
- `sudo kubectl -n esmos logs deploy/moodle`
- `sudo kubectl -n esmos logs deploy/uptimekuma`
- `curl -I http://127.0.0.1:30080/login/index.php`
- `curl -I http://127.0.0.1:30081/`

## Notes

- Keep only `80` and `443` public on the VM.
- Keep Kubernetes NodePorts `30080` and `30081` private.
- If you use your own Moodle image, update `k8s/moodle.yaml` first.
