#!/usr/bin/env bash
set -euo pipefail

PODMAN_BIN=${PODMAN_BIN:-podman}
IMAGE_REF=${IMAGE_REF:-docker.io/aljosavister/oci-dns-certbot:latest}
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
ENV_FILE=${ENV_FILE:-${PROJECT_ROOT}/config/env.example}
STATE_ROOT=${STATE_ROOT:-${PROJECT_ROOT}/state}
SECRETS_DIR=${SECRETS_DIR:-${PROJECT_ROOT}/secrets}
EXPORT_DIR=${EXPORT_DIR:-${PROJECT_ROOT}/export}

mkdir -p "$STATE_ROOT/etc-letsencrypt" "$STATE_ROOT/lib-letsencrypt" "$STATE_ROOT/log-letsencrypt" "$EXPORT_DIR" "$SECRETS_DIR"

$PODMAN_BIN run --rm \
  --name oci-dns-certbot \
  --env-file "$ENV_FILE" \
  -v "$STATE_ROOT/etc-letsencrypt:/etc/letsencrypt" \
  -v "$STATE_ROOT/lib-letsencrypt:/var/lib/letsencrypt" \
  -v "$STATE_ROOT/log-letsencrypt:/var/log/letsencrypt" \
  -v "$EXPORT_DIR:/export" \
  -v "$SECRETS_DIR:/secrets:ro" \
  "$IMAGE_REF" "$@"
