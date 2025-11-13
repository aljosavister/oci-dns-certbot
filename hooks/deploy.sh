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

: "${CERTBOT_FULLCHAIN_PATH:?CERTBOT_FULLCHAIN_PATH not provided}"
: "${CERTBOT_PRIVKEY_PATH:?CERTBOT_PRIVKEY_PATH not provided}"

install -D -m 0644 "${CERTBOT_FULLCHAIN_PATH}" "${CERT_EXPORT_PATH}/${CERT_EXPORT_PUBLIC_NAME}"
install -D -m 0640 "${CERTBOT_PRIVKEY_PATH}" "${CERT_EXPORT_PATH}/${CERT_EXPORT_PRIVATE_NAME}"

if [[ -n "${CERT_EXPORT_UID}" || -n "${CERT_EXPORT_GID}" ]]; then
  chown "${CERT_EXPORT_UID:-}"":"${CERT_EXPORT_GID:-}" \
    "${CERT_EXPORT_PATH}/${CERT_EXPORT_PUBLIC_NAME}" \
    "${CERT_EXPORT_PATH}/${CERT_EXPORT_PRIVATE_NAME}"
fi

if [[ -n "${POST_RENEW_COMMAND}" ]]; then
  echo "[deploy] running post-renew command"
  bash -c "${POST_RENEW_COMMAND}"
fi
