# OCI DNS Certbot – Developer Guide

This repository contains the container build files, hooks, and helper scripts that power the `docker.io/aljosavister/oci-dns-certbot` image. The image automates Let’s Encrypt DNS-01 challenges against OCI DNS via Lexicon.

Looking for day-to-day usage instructions? See [README.dockerhub.md](README.dockerhub.md). This README focuses on building, testing, and contributing to the project.

## Repository Layout
```
Dockerfile                         # Certbot + dns-lexicon image definition
entrypoint.sh                      # Validates env, templates Lexicon config, runs certbot
hooks/auth.sh|cleanup.sh|deploy.sh # Manual DNS hooks and certificate export logic
config/env.example                 # Reference environment file
scripts/run-once.sh                # Convenience wrapper for local Podman runs
scripts/build-multi-arch.sh        # buildx wrapper for publishing multi-arch images
podman/*.service|*.timer           # Sample systemd units for scheduled renewals
```

## Prerequisites
- Podman 4.8+ (recommended) or Docker 24+
- Access to an OCI tenancy for integration tests (optional)
- Bash, GNU coreutils, and `make`-style tooling if you script against these files

## Local image build
```bash
podman build -t docker.io/aljosavister/oci-dns-certbot:dev .
```
Run the container locally with the helper script (uses bind-mounted `state/` directories under the repo):
```bash
CERTBOT_DRY_RUN=true \
IMAGE_REF=docker.io/aljosavister/oci-dns-certbot:dev \
./scripts/run-once.sh
```
Provide a populated `config/env.example` copy plus a mock `/secrets/oci_api_key.pem` to test successful execution (Lexicon will fail without real OCI creds, so use `CERTBOT_DRY_RUN=true`).

## Multi-architecture publishing
`./scripts/build-multi-arch.sh` wraps `podman buildx` + `podman manifest push` so you can release both `linux/amd64` and `linux/arm64` layers:
```bash
podman login docker.io
IMAGE_TAG=docker.io/aljosavister/oci-dns-certbot:1.0.1 \
  ./scripts/build-multi-arch.sh
```
Environment variables:
- `PLATFORMS` – comma-separated targets (default `linux/amd64,linux/arm64`)
- `BUILD_CONTEXT` – defaults to `.`
- `PUSH` – set to `false` for local single-arch testing (requires `PLATFORMS` to contain one value)
- `MANIFEST_NAME` – override the temporary manifest reference (default `oci-dns-certbot-manifest`)
- `CLEANUP_MANIFEST` – disable cleanup by setting `false`
- `BUILDER_NAME`, `PODMAN_BIN` – customize the buildx builder or Podman binary

## Hooks and entrypoint
- `hooks/auth.sh` and `hooks/cleanup.sh` shell out to Lexicon’s OCI provider. They read `CERTBOT_DOMAIN`, `CERTBOT_VALIDATION`, respect `CERTBOT_MANUAL_PROPAGATION_SECONDS`, and default to `/etc/letsencrypt` for the Lexicon config.
- `hooks/deploy.sh` copies the renewed certificate/key pair into `/export`, handles ownership adjustments via `CERT_EXPORT_UID/GID`, and executes `POST_RENEW_COMMAND` when set.
- `entrypoint.sh` is responsible for:
  - Parsing `CERT_DOMAINS` and optional `CERT_PRIMARY_DOMAIN`
  - Writing `lexicon_oci.yml` from environment variables (unless already present)
  - Composing the `certbot certonly` command with manual hooks and non-interactive flags
  - Supporting `CERTBOT_{STAGING,FORCE_RENEWAL,DRY_RUN,EXTRA_ARGS}` toggles

Run `bash -n entrypoint.sh hooks/*.sh scripts/*.sh` to ensure changes remain shellcheck-friendly (we rely on simple syntax validation in CI for now).

## Testing changes
1. Build a dev tag (`podman build -t oci-dns-certbot:dev .`).
2. Provide mock secrets and run `CERTBOT_DRY_RUN=true ./scripts/run-once.sh` to ensure the hooks execute.
3. For integration tests, point to a staging OCI DNS zone and Let’s Encrypt staging by setting `CERTBOT_STAGING=true`.

## Automation artifacts
The `podman/oci-dns-certbot-renew.{service,timer}` files are templates for systemd-based scheduling. When you modify CLI flags or add new env vars, mirror the changes here so users who copy these units stay up to date.

## Releasing
1. Update `config/env.example`, docs, and changelog (if applicable).
2. Build/push multi-arch tags via `scripts/build-multi-arch.sh`.
3. Test the published tag with the documented Podman command from README.dockerhub.
4. Draft Docker Hub release notes referencing `README.dockerhub.md`.

For operational usage, refer end users to [README.dockerhub.md](README.dockerhub.md).
