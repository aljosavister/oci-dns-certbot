# OCI DNS Certbot (Podman/Docker)

Container image that renews Let's Encrypt certificates for private services by solving DNS-01 challenges against Oracle Cloud (OCI) DNS via Lexicon. Run it on any host with Podman or Docker, mount your Let’s Encrypt directories plus the OCI API key, and it will copy renewed certs into a shared export volume for other workloads.

## Features
- Works completely inside a container (no host Python/Certbot install)
- Automates OCI DNS TXT record management via dns-lexicon hooks
- Copies `fullchain.pem` / `privkey.pem` into a bind-mounted export directory every renewal
- Optional post-renew command (e.g., reload another container)
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
   CERT_EXPORT_PATH=/export
   CERT_EXPORT_PUBLIC_NAME=public.crt
   CERT_EXPORT_PRIVATE_NAME=private.key
   POST_RENEW_COMMAND=
   CERTBOT_DRY_RUN=true  # remove after the first successful test
   ```
2. Place your OCI API key at `/etc/oci-dns-certbot/secrets/oci_api_key.pem` (chmod 600) and ensure the IAM policy allows DNS zone writes.
3. Create persistent directories for Certbot state and exported certs:
   ```bash
   sudo mkdir -p /srv/oci-certbot/{etc-letsencrypt,lib-letsencrypt,log-letsencrypt,export}
   sudo mkdir -p /etc/oci-dns-certbot/secrets
   sudo chcon -Rt container_file_t /srv/oci-certbot /etc/oci-dns-certbot/secrets  # on SELinux hosts
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
  docker.io/aljosavister/oci-dns-certbot:latest
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
  docker.io/aljosavister/oci-dns-certbot:latest
```
Leave `CERTBOT_DRY_RUN=true` for the first run; once you see "The dry run was successful", remove it to issue production certificates. The deploy hook writes `public.crt` / `private.key` inside the export directory after each renewal.

## Automation
- `podman/oci-dns-certbot-renew.service` and `.timer` show how to schedule daily renewals via systemd.
- Mount `/srv/oci-certbot/export` into dependent containers as read-only so they can consume the latest certs.

## Support
Issues and feature requests: https://github.com/aljosavister/oci-dns-certbot
