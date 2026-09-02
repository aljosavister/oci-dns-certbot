#!/usr/bin/env bash
set -euo pipefail

# This script runs on the host, never in the certificate container. It consumes
# the marker written by hooks/deploy.sh only after a successful certificate copy.
ENV_FILE=${ENV_FILE:-}
HOST_CERT_EXPORT_PATH=${HOST_CERT_EXPORT_PATH:-}
HOST_POST_RENEW_COMMAND=${HOST_POST_RENEW_COMMAND:-}
POST_RENEW_COMMAND=${POST_RENEW_COMMAND:-}
CERT_EXPORT_DEPLOY_MARKER=${CERT_EXPORT_DEPLOY_MARKER:-}

read_env_value() {
  local name="$1"

  [[ -n "$ENV_FILE" && -r "$ENV_FILE" ]] || return 0
  awk -v name="$name" '
    index($0, name "=") == 1 {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$ENV_FILE"
}

if [[ -z "$HOST_CERT_EXPORT_PATH" ]]; then
  HOST_CERT_EXPORT_PATH=$(read_env_value HOST_CERT_EXPORT_PATH)
fi

if [[ -z "$HOST_POST_RENEW_COMMAND" ]]; then
  HOST_POST_RENEW_COMMAND=$(read_env_value HOST_POST_RENEW_COMMAND)
fi

if [[ -z "$CERT_EXPORT_DEPLOY_MARKER" ]]; then
  CERT_EXPORT_DEPLOY_MARKER=$(read_env_value CERT_EXPORT_DEPLOY_MARKER)
fi
CERT_EXPORT_DEPLOY_MARKER=${CERT_EXPORT_DEPLOY_MARKER:-.oci-dns-certbot-deployed}

# POST_RENEW_COMMAND was previously (and incorrectly) executed inside the
# certificate container. Keep it as a host-side compatibility fallback.
if [[ -z "$HOST_POST_RENEW_COMMAND" ]]; then
  HOST_POST_RENEW_COMMAND=${POST_RENEW_COMMAND:-$(read_env_value POST_RENEW_COMMAND)}
fi

if [[ -z "$HOST_CERT_EXPORT_PATH" ]]; then
  echo "[post-renew] HOST_CERT_EXPORT_PATH is required" >&2
  exit 1
fi

if [[ "$CERT_EXPORT_DEPLOY_MARKER" == */* || "$CERT_EXPORT_DEPLOY_MARKER" == "." || "$CERT_EXPORT_DEPLOY_MARKER" == ".." ]]; then
  echo "[post-renew] CERT_EXPORT_DEPLOY_MARKER must be a simple file name" >&2
  exit 1
fi

MARKER_PATH="${HOST_CERT_EXPORT_PATH}/${CERT_EXPORT_DEPLOY_MARKER}"

if [[ ! -f "$MARKER_PATH" ]]; then
  exit 0
fi

if [[ -z "$HOST_POST_RENEW_COMMAND" ]]; then
  echo "[post-renew] certificate changed, but no HOST_POST_RENEW_COMMAND is configured" >&2
  exit 0
fi

echo "[post-renew] running host post-renew command"
bash -c "$HOST_POST_RENEW_COMMAND"
rm -f -- "$MARKER_PATH"
