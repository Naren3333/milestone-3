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

## Every time you start the VM

On the VM:

1. SSH in:
   `ssh moodle_admin@moodlestaging.centralindia.cloudapp.azure.com`
2. Go to the repo:
   `cd ~/milestone-3`
3. If `git pull` is blocked by local secret edits, back them up first:
   `cp k8s/secrets.template.yaml ~/secrets.template.backup.yaml`
4. Discard the repo copy of the secret template and pull the latest code:
   `git restore k8s/secrets.template.yaml && git pull`
5. Reapply your real secret values in `k8s/secrets.template.yaml`.
6. Apply Kubernetes manifests:
   `sudo kubectl apply -k k8s`
7. Check that everything is healthy:
   `sudo kubectl -n esmos get pods`
8. Test Moodle:
   `curl -k -I https://moodlestaging.centralindia.cloudapp.azure.com`

Expected result:

- `moodle`, `moodledb`, and `uptimekuma` should all be `1/1 Running`
- the Moodle HTTPS check should return `HTTP/2 200`

To use Uptime Kuma from your laptop:

1. Open a terminal on your laptop, not on the VM.
2. Create an SSH tunnel:
   `ssh -L 3002:127.0.0.1:30081 moodle_admin@moodlestaging.centralindia.cloudapp.azure.com`
3. Keep that SSH session open.
4. Open:
   `http://localhost:3002`
5. Log in with the Uptime Kuma account you created earlier.

Uptime Kuma persistence:

- Uptime Kuma data is stored on the Kubernetes persistent volume claim `uptimekuma-data-pvc`
- your monitors and login should still be there after the VM is stopped and started again

## Live rollback demo

If you want to show Kubernetes self-healing during a demo:

1. SSH into the VM and go to the repo:
   `cd ~/milestone-3`
2. Run the demo script against Moodle:
   `bash scripts/rollback-demo.sh moodle`
3. Watch Kubernetes delete the current Moodle pod and bring up a replacement pod automatically.

The script uses `sudo kubectl` by default on the VM, so it matches the same K3s access pattern used elsewhere in this README.

You can also target:

- `bash scripts/rollback-demo.sh moodle`
- `bash scripts/rollback-demo.sh moodledb`
- `bash scripts/rollback-demo.sh uptimekuma`

What it does:

- picks one running pod for the app
- deletes that pod
- waits for the replacement pod to appear
- waits until the new pod is `Ready`
- for Moodle, it also does a quick HTTPS check at the end

This is a safe demo of Kubernetes self-healing because you are deleting a pod, not deleting the deployment or persistent data.

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
