# OCI DNS Certbot – Developer Guide

This repository contains the container build files, hooks, and helper scripts that power the `docker.io/unsopenhub/oci-dns-certbot` image. The image automates Let’s Encrypt DNS-01 challenges against OCI DNS via Lexicon.

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
podman/oci-dns-certbot-post-renew.sh # Host-side reload helper
```

## Prerequisites
- Podman 4.8+ (recommended) or Docker 24+
- Access to an OCI tenancy for integration tests (optional)
- Bash, GNU coreutils, and `make`-style tooling if you script against these files

## Publishing to Docker Hub
Use the buildx helper to build and push multi-arch manifests (linux/amd64 + linux/arm64):
```bash
podman login docker.io
IMAGE_TAG=docker.io/unsopenhub/oci-dns-certbot:1.1.1 \
  ./scripts/build-multi-arch.sh
```
Set `IMAGE_TAG` to the desired version before running. The script wraps `podman buildx build --manifest ...` followed by `podman manifest push`, so it works across Podman versions. Environment variables you can customize:
- `PLATFORMS` – comma-separated targets (default `linux/amd64,linux/arm64`)
- `BUILD_CONTEXT` – defaults to `.`
- `PUSH` – set to `false` for local single-arch testing (requires `PLATFORMS` to contain one value)
- `MANIFEST_NAME` – override the temporary manifest reference (default `oci-dns-certbot-manifest`)
- `PUSH_LATEST` – set to `true` to push the same manifest to a `:latest` tag alongside your versioned tag
- `CLEANUP_MANIFEST` – disable cleanup by setting `false`
- `BUILDER_NAME`, `PODMAN_BIN` – customize the buildx builder or Podman binary

## Hooks and entrypoint
- `hooks/auth.sh` and `hooks/cleanup.sh` shell out to Lexicon’s OCI provider. They read `CERTBOT_DOMAIN`, `CERTBOT_VALIDATION`, respect `CERTBOT_MANUAL_PROPAGATION_SECONDS`, and default to `/etc/letsencrypt` for the Lexicon config.
- `hooks/deploy.sh` atomically replaces each renewed export file in `/export` (unless `CERT_EXPORT_ENABLED=false`) and writes a deploy marker last. `CERT_EXPORT_UID/GID` accept numeric host IDs only.
- `podman/oci-dns-certbot-post-renew.sh` runs `HOST_POST_RENEW_COMMAND` on the host after an actual export, then consumes that marker. This deliberately avoids giving the certificate container access to a Podman/Docker socket.
- `entrypoint.sh` is responsible for:
  - Parsing `CERT_DOMAINS` and optional `CERT_PRIMARY_DOMAIN`
  - Writing `lexicon_oci.yml` from environment variables (unless already present)
  - Composing the `certbot certonly` command with manual hooks and non-interactive flags
  - Supporting `CERTBOT_{STAGING,FORCE_RENEWAL,DRY_RUN,RUN_DEPLOY_HOOKS,EXTRA_ARGS}` toggles

Run `bash -n entrypoint.sh hooks/*.sh scripts/*.sh podman/oci-dns-certbot-post-renew.sh` to ensure changes remain shellcheck-friendly (we rely on simple syntax validation in CI for now).

## Testing changes
1. Build a dev tag (`podman build -t oci-dns-certbot:dev .`).
2. Provide mock secrets and run `CERTBOT_DRY_RUN=true ./scripts/run-once.sh` to test DNS validation. Set `CERTBOT_RUN_DEPLOY_HOOKS=true` only when testing the export/deploy hook.
3. For integration tests, point to a staging OCI DNS zone and Let’s Encrypt staging by setting `CERTBOT_STAGING=true`.

## Automation artifacts
The `podman/oci-dns-certbot-renew.{service,timer}` files are templates for systemd-based scheduling. When you modify CLI flags or add new env vars, mirror the changes here so users who copy these units stay up to date.

## Releasing
1. Update `config/env.example`, docs, and changelog (if applicable).
2. Build/push multi-arch tags via `scripts/build-multi-arch.sh`.
3. Test the published tag with the documented Podman command from README.dockerhub.
4. Draft Docker Hub release notes referencing `README.dockerhub.md`.

For operational usage, refer end users to [README.dockerhub.md](README.dockerhub.md).
