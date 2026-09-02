![UNS OpenHub](https://www.uns-openhub.com/assets/logo-mark.svg)

# OCI DNS Certbot (Podman/Docker)

Container image that renews Let's Encrypt certificates for private services by solving DNS-01 challenges against Oracle Cloud (OCI) DNS via Lexicon. Run it on any host with Podman or Docker, mount your Let’s Encrypt directories plus the OCI API key, and it will copy renewed certs into a shared export volume for other workloads.

## Features
- Works completely inside a container (no host Python/Certbot install)
- Automates OCI DNS TXT record management via dns-lexicon hooks
- Copies `fullchain.pem` / `privkey.pem` into a bind-mounted export directory every renewal
- Optional host-side post-renew command (e.g., reload another container)
- Systemd timer/service examples for unattended scheduling

## Requirements
- OCI IAM user with DNS zone access and an API key (PEM) that matches the fingerprint passed in env vars
- Let’s Encrypt account email and domains to issue
- Podman or Docker 24+

## Configuration
1. Create `/etc/oci-dns-certbot.env` from this template:
   ```ini
   CERT_DOMAINS=service.example.com,*.service.example.com
   CERTBOT_EMAIL=admin@example.com
   CERTBOT_MANUAL_PROPAGATION_SECONDS=90
   OCI_AUTH_USER=ocid1.user.oc1..example
   OCI_AUTH_TENANCY=ocid1.tenancy.oc1..example
   OCI_AUTH_FINGERPRINT=aa:bb:cc:dd:...
   OCI_AUTH_REGION=eu-frankfurt-1
   OCI_AUTH_COMPARTMENT=ocid1.compartment.oc1..example
   OCI_AUTH_KEY_FILE=/secrets/oci_api_key.pem
   CERT_EXPORT_ENABLED=true
   CERT_EXPORT_PATH=/export
   CERT_EXPORT_PUBLIC_NAME=public.crt
   CERT_EXPORT_PRIVATE_NAME=private.key
   CERT_EXPORT_UID=
   CERT_EXPORT_GID=
   CERT_EXPORT_PUBLIC_MODE=0644
   CERT_EXPORT_PRIVATE_MODE=0640
   CERT_EXPORT_DEPLOY_MARKER=.oci-dns-certbot-deployed
   HOST_CERT_EXPORT_PATH=/srv/oci-certbot/export
   HOST_POST_RENEW_COMMAND=
   # Keep this true for the first DNS/issuance test, then set it to false.
   CERTBOT_DRY_RUN=true
   # Set true only when testing the deploy/export hook itself during dry-run.
   CERTBOT_RUN_DEPLOY_HOOKS=false
   ```
2. Create persistent directories for Certbot state and exported certs:
   ```bash
   sudo mkdir -p /srv/oci-certbot/{etc-letsencrypt,lib-letsencrypt,log-letsencrypt,export}
   sudo mkdir -p /etc/oci-dns-certbot/secrets
   sudo chcon -Rt container_file_t /srv/oci-certbot /etc/oci-dns-certbot/secrets  # on SELinux hosts
   ```
3. Place your OCI API key at `/etc/oci-dns-certbot/secrets/oci_api_key.pem` (chmod 600) and ensure the IAM policy allows DNS zone writes.
   ```bash
   sudo nano /etc/oci-dns-certbot/secrets/oci_api_key.pem
   ```

   ```bash
   sudo chmod 600 /etc/oci-dns-certbot/secrets/oci_api_key.pem
   ```
## Running manually
Podman (recommended):
```bash
sudo podman run --rm \
  --name oci-dns-certbot \
  --env-file /etc/oci-dns-certbot.env \
  -v /srv/oci-certbot/etc-letsencrypt:/etc/letsencrypt:Z \
  -v /srv/oci-certbot/lib-letsencrypt:/var/lib/letsencrypt:Z \
  -v /srv/oci-certbot/log-letsencrypt:/var/log/letsencrypt:Z \
  -v /srv/oci-certbot/export:/export:Z \
  -v /etc/oci-dns-certbot/secrets:/secrets:ro,Z \
  docker.io/unsopenhub/oci-dns-certbot:latest
```
Docker:
```bash
sudo docker run --rm \
  --name oci-dns-certbot \
  --env-file /etc/oci-dns-certbot.env \
  -v /srv/oci-certbot/etc-letsencrypt:/etc/letsencrypt \
  -v /srv/oci-certbot/lib-letsencrypt:/var/lib/letsencrypt \
  -v /srv/oci-certbot/log-letsencrypt:/var/log/letsencrypt \
  -v /srv/oci-certbot/export:/export \
  -v /etc/oci-dns-certbot/secrets:/secrets:ro \
  docker.io/unsopenhub/oci-dns-certbot:latest
```
Leave `CERTBOT_DRY_RUN=true` for the first run; once you see "The dry run was successful", set it to `false` to issue production certificates. Certbot skips deploy hooks during a dry-run unless `CERTBOT_RUN_DEPLOY_HOOKS=true`; when enabled, Certbot deploys the current active certificate rather than its temporary staging certificate. Set `CERT_EXPORT_ENABLED=false` only when you do not need export or a host post-renew command. `CERT_EXPORT_UID` and `CERT_EXPORT_GID` must be numeric host IDs, for example `1000`; group names such as `caddy` are resolved inside the image and are not portable.
The deploy hook writes `CERT_EXPORT_DEPLOY_MARKER` only after both exported files are fully written. `HOST_POST_RENEW_COMMAND` runs on the host only when that marker exists, then consumes it. This permits `podman exec …` or `systemctl reload …` without mounting a container-engine socket into the certificate image. `POST_RENEW_COMMAND` remains a deprecated compatibility alias for the host command.
When using the direct `podman run` or `docker run` examples, invoke `oci-dns-certbot-post-renew.sh` on the host afterwards if you configure a host post-renew command. The supplied systemd service and `scripts/run-once.sh` do this automatically.
This container runs as a short-lived job: it issues/renews certificates, copies files into the mounted directories, then exits. Schedule it via systemd/cron (see below) to check daily—Certbot skips work when certificates are still valid.

## Automation
- `podman/oci-dns-certbot-renew.service` and `.timer` show how to schedule daily renewals via systemd.
- On Oracle Linux and other RHEL-style hosts, copy the sample unit files from `podman/oci-dns-certbot-renew.service` and `podman/oci-dns-certbot-renew.timer`, then create matching units under `/etc/systemd/system`:
  ```bash
  sudo nano /etc/systemd/system/oci-dns-certbot-renew.service
  ```
  ```bash
  sudo nano /etc/systemd/system/oci-dns-certbot-renew.timer
  ```
  Install the host-side post-renew helper next to the units. It executes `HOST_POST_RENEW_COMMAND` only after an actual certificate export; leave the setting empty if no reload is required.
  ```bash
  sudo install -D -m 0755 podman/oci-dns-certbot-post-renew.sh /usr/local/libexec/oci-dns-certbot-post-renew
  ```
  After saving the files, reload systemd and enable the timer so it starts immediately:
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl enable --now oci-dns-certbot-renew.timer
  ```
  To kick off a renewal job on demand:
  ```bash
  sudo systemctl start oci-dns-certbot-renew
  ```
  Adjust the volume paths, `HOST_CERT_EXPORT_PATH`, or image tag inside the service file if you changed them during setup. The service already uses `:Z` relabels on the host mounts so Podman can access them under SELinux. The timer fires daily; Certbot only renews when certificates are near expiry.
- Mount `/srv/oci-certbot/export` into dependent containers as read-only so they can consume the latest certs.
- Certbot’s success message references `/etc/letsencrypt/live/...` inside the container; on the host that directory is your bind mount (`/srv/oci-certbot/etc-letsencrypt/live/...`) and the deploy hook copies `public.crt` / `private.key` into `/srv/oci-certbot/export` for convenience.
- Logs persist under `/srv/oci-certbot/log-letsencrypt`. Inspect them with `sudo tail -f /srv/oci-certbot/log-letsencrypt/letsencrypt.log` or by running `sudo podman logs oci-dns-certbot` immediately after a manual run.
- For systemd-managed runs, use `sudo journalctl -u oci-dns-certbot-renew.service -u oci-dns-certbot-renew.timer -f` to follow the timer/service logs.

## Support
Issues and feature requests: https://github.com/aljosavister/oci-dns-certbot
