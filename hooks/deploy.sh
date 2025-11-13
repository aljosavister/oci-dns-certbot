#!/usr/bin/env bash
set -euo pipefail

CERT_EXPORT_ENABLED=${CERT_EXPORT_ENABLED:-true}
CERT_EXPORT_PATH=${CERT_EXPORT_PATH:-/export}
CERT_EXPORT_PUBLIC_NAME=${CERT_EXPORT_PUBLIC_NAME:-public.crt}
CERT_EXPORT_PRIVATE_NAME=${CERT_EXPORT_PRIVATE_NAME:-private.key}
CERT_EXPORT_UID=${CERT_EXPORT_UID:-}
CERT_EXPORT_GID=${CERT_EXPORT_GID:-}
POST_RENEW_COMMAND=${POST_RENEW_COMMAND:-}

if [[ "${CERT_EXPORT_ENABLED}" != "true" ]]; then
  exit 0
fi

if [[ ! -d "${CERT_EXPORT_PATH}" ]]; then
  echo "[deploy] export path ${CERT_EXPORT_PATH} does not exist; skipping copy" >&2
  exit 0
fi

FULLCHAIN_PATH=${CERTBOT_FULLCHAIN_PATH:-}
PRIVKEY_PATH=${CERTBOT_PRIVKEY_PATH:-}

if [[ -z "$FULLCHAIN_PATH" || -z "$PRIVKEY_PATH" ]]; then
  if [[ -n "${RENEWED_LINEAGE:-}" ]]; then
    FULLCHAIN_PATH="${RENEWED_LINEAGE}/fullchain.pem"
    PRIVKEY_PATH="${RENEWED_LINEAGE}/privkey.pem"
  else
    echo "[deploy] cert/key paths missing (CERTBOT_FULLCHAIN_PATH or RENEWED_LINEAGE not provided)" >&2
    exit 1
  fi
fi

install -D -m 0644 "${FULLCHAIN_PATH}" "${CERT_EXPORT_PATH}/${CERT_EXPORT_PUBLIC_NAME}"
install -D -m 0640 "${PRIVKEY_PATH}" "${CERT_EXPORT_PATH}/${CERT_EXPORT_PRIVATE_NAME}"

if [[ -n "${CERT_EXPORT_UID}" || -n "${CERT_EXPORT_GID}" ]]; then
  chown "${CERT_EXPORT_UID:-}:${CERT_EXPORT_GID:-}" \
    "${CERT_EXPORT_PATH}/${CERT_EXPORT_PUBLIC_NAME}" \
    "${CERT_EXPORT_PATH}/${CERT_EXPORT_PRIVATE_NAME}"
fi

if [[ -n "${POST_RENEW_COMMAND}" ]]; then
  echo "[deploy] running post-renew command"
  bash -c "${POST_RENEW_COMMAND}"
fi
