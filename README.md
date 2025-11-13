# OCI DNS Certbot Podman Tool

Containerized helper that issues and renews Let's Encrypt certificates for private services by solving the DNS-01 challenge with Oracle Cloud (OCI) DNS. The image wraps Certbot and `dns-lexicon` plus bespoke hooks so you can run everything inside Podman and share the resulting certificate files with other workloads on the host.

## Features
- Runs entirely in a Podman container – no host-level Python or Certbot install.
- Uses Lexicon's OCI provider from non-interactive hooks to create and clean up `_acme-challenge` TXT records.
- Templates the Lexicon configuration from environment variables (or consumes a mounted file) so no credentials live in Git.
- Copies renewed certificates into a bind-mounted export directory and optionally runs a post-renew command (e.g., notify another service or reload a reverse proxy).
- Example Podman run script plus systemd timer/service units for unattended renewals.

## Directory Layout
```
Dockerfile                         # Builds the certbot+lexicon image
entrypoint.sh                      # Validates env, templates Lexicon config, runs certbot
hooks/                             # Auth, cleanup, and deploy hooks executed by certbot
config/env.example                 # Annotated environment file
scripts/run-once.sh                # Helper to test the container locally with Podman
scripts/build-multi-arch.sh        # Uses buildx to publish linux/amd64+arm64 images
podman/*.service|*.timer           # Example systemd units for automated renewals
```

## Building the image
```bash
podman build -t docker.io/aljosavister/oci-dns-certbot:latest .
```

### Multi-architecture build & push
To publish a manifest that contains both amd64 and arm64 layers (eliminating the “image platform … does not match” warning), use the helper script. It wraps `podman buildx` and pushes by default:
```bash
podman login docker.io
IMAGE_TAG=docker.io/aljosavister/oci-dns-certbot:latest \
  ./scripts/build-multi-arch.sh
```
The script honors the following environment variables:
- `PLATFORMS` (default `linux/amd64,linux/arm64`)
- `BUILD_CONTEXT` (default `.`)
- `PUSH` (`true` pushes a multi-arch manifest; set `false` and `PLATFORMS=linux/amd64` to load into the local daemon)
- `MANIFEST_NAME` if you want a custom local manifest reference (defaults to `oci-dns-certbot-manifest`)
- `CLEANUP_MANIFEST` (`true` removes the temporary manifest after a push; set `false` to keep it locally)
- `BUILDER_NAME` / `PODMAN_BIN` if you maintain multiple buildx builders. The script exports `BUILDX_BUILDER` so it works even on older Podman releases without `buildx use`.
Internally the script runs `podman buildx build --manifest ...` for all requested platforms and then `podman manifest push` to publish the manifest list, which avoids the `--push` flag that some Podman versions lack.

## Preparing configuration
1. Copy `config/env.example` to a secure location (e.g., `/etc/oci-dns-certbot.env`) and update the values:
   - `CERT_DOMAINS`: comma-separated list (`service.example.com,*.service.example.com`). The first entry becomes the certificate name.
   - `CERTBOT_EMAIL`: email for ACME registration.
   - `OCI_AUTH_*`: OCIDs, fingerprint, region, compartment, plus the API key path mounted at runtime.
   - Optional knobs such as `CERTBOT_MANUAL_PROPAGATION_SECONDS`, `CERT_EXPORT_*`, and `POST_RENEW_COMMAND`.
2. Place your OCI API key PEM file on the host (e.g., `/etc/oci-dns-certbot/secrets/oci_api_key.pem`). The entrypoint checks that the path from `OCI_AUTH_KEY_FILE` exists inside the container.
3. Create persistent directories on the host that Podman can mount:
   - `/srv/oci-certbot/etc-letsencrypt`
   - `/srv/oci-certbot/lib-letsencrypt`
   - `/srv/oci-certbot/log-letsencrypt`
   - `/srv/oci-certbot/export` (read by other containers for `public.crt` / `private.key`)
   - `/etc/oci-dns-certbot/secrets` (contains the OCI API key and stays `0600`; more detail below)

### Providing the OCI API key
Create the secrets directory and copy the PEM that matches your CLI fingerprint:
```bash
sudo mkdir -p /etc/oci-dns-certbot/secrets
sudo cp ~/oci_api_key.pem /etc/oci-dns-certbot/secrets/oci_api_key.pem
sudo chmod 600 /etc/oci-dns-certbot/secrets/oci_api_key.pem
sudo chown root:root /etc/oci-dns-certbot/secrets/oci_api_key.pem
```
The default `OCI_AUTH_KEY_FILE=/secrets/oci_api_key.pem` expects you to mount this directory read-only into the container (as shown in `scripts/run-once.sh` and the systemd service). If you store the key elsewhere, update the environment variable or mount path accordingly. The file never needs to be in the repository—only on the host (or provided via Podman/Kubernetes secrets).

## Running manually with Podman
```bash
./scripts/run-once.sh \
  --cert-name override-if-needed
```
By default the script uses `config/env.example`, local `state/` directories, and the image tag `docker.io/aljosavister/oci-dns-certbot:latest`. Override using environment variables (`ENV_FILE`, `STATE_ROOT`, `EXPORT_DIR`, `SECRETS_DIR`, `IMAGE_REF`).

### Direct Podman/Docker command
If you prefer to run the container manually on the server (without the helper script), use the same volume layout referenced above:
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
Swap `podman` for `docker` if you are using the Docker Engine; the arguments stay the same. Ensure `/etc/oci-dns-certbot.env` and `/etc/oci-dns-certbot/secrets/oci_api_key.pem` exist before running. Use `CERTBOT_DRY_RUN=true` in the env file for your first test run.

If SELinux blocks writes into the bind-mounted directories, either append the `:Z`/`:z` suffixes (as shown) so Podman relabels the paths automatically, or run:
```bash
sudo chcon -Rt container_file_t /srv/oci-certbot/etc-letsencrypt \
                                 /srv/oci-certbot/lib-letsencrypt \
                                 /srv/oci-certbot/log-letsencrypt \
                                 /srv/oci-certbot/export \
                                 /etc/oci-dns-certbot/secrets
```
to permanently grant the container write access.

## Systemd timer
Copy `podman/oci-dns-certbot-renew.service` and `podman/oci-dns-certbot-renew.timer` into `/etc/systemd/system/`, edit the volume paths/image reference to suit your host, and load your env file via `/etc/oci-dns-certbot.env` (referenced by `EnvironmentFile=`). Then enable the timer:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now oci-dns-certbot-renew.timer
```
The timer runs daily and triggers the Podman container, which in turn only renews when certificates are close to expiry because Certbot is invoked with `--keep-until-expiring`.

## Consuming the certificates
Mount `/srv/oci-certbot/export` (or whichever export directory you chose) into dependent containers as read-only. The deploy hook writes `public.crt` (full chain) and `private.key` every successful issuance and can `chown` them to a service user or execute `POST_RENEW_COMMAND` to reload or notify a consumer.

## Security notes
- Never commit real OCI OCIDs, fingerprints, or private keys. Use the provided `.example` files for documentation only.
- Restrict filesystem permissions on the secrets directory (`chmod 600`).
- If you rotate OCI API keys, restart the Podman renewal service so the new PEM is copied into the container.
- Consider running `podman secret` / `podman kube` workflows if you already manage secrets that way; point `OCI_AUTH_KEY_FILE` to `/run/secrets/...` accordingly.

## Testing and troubleshooting
- Add `CERTBOT_DRY_RUN=true` to perform a full ACME staging flow without issuing production certificates.
- `CERTBOT_STAGING=true` toggles Let's Encrypt's staging endpoint for real DNS writes but rate-limit–free testing.
- Logs are persisted under the mounted logs directory. Use `podman logs oci-dns-certbot` or inspect `/srv/oci-certbot/log-letsencrypt/letsencrypt.log`.
- To increase DNS propagation wait time, bump `CERTBOT_MANUAL_PROPAGATION_SECONDS`; the auth hook simply sleeps for that duration before Certbot proceeds.
