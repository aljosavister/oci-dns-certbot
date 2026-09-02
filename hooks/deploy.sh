#!/usr/bin/env bash
set -euo pipefail

CERT_EXPORT_ENABLED=${CERT_EXPORT_ENABLED:-true}
CERT_EXPORT_PATH=${CERT_EXPORT_PATH:-/export}
CERT_EXPORT_PUBLIC_NAME=${CERT_EXPORT_PUBLIC_NAME:-public.crt}
CERT_EXPORT_PRIVATE_NAME=${CERT_EXPORT_PRIVATE_NAME:-private.key}
CERT_EXPORT_UID=${CERT_EXPORT_UID:-}
CERT_EXPORT_GID=${CERT_EXPORT_GID:-}
CERT_EXPORT_PUBLIC_MODE=${CERT_EXPORT_PUBLIC_MODE:-0644}
CERT_EXPORT_PRIVATE_MODE=${CERT_EXPORT_PRIVATE_MODE:-0640}
CERT_EXPORT_DEPLOY_MARKER=${CERT_EXPORT_DEPLOY_MARKER:-.oci-dns-certbot-deployed}

require_simple_filename() {
  local value="$1"
  local variable_name="$2"

  if [[ -z "$value" || "$value" == */* || "$value" == "." || "$value" == ".." ]]; then
    echo "[deploy] $variable_name must be a simple file name" >&2
    exit 1
  fi
}

require_octal_mode() {
  local value="$1"
  local variable_name="$2"

  if [[ ! "$value" =~ ^0?[0-7]{3}$ ]]; then
    echo "[deploy] $variable_name must be a three- or four-digit octal mode" >&2
    exit 1
  fi
}

require_numeric_id() {
  local value="$1"
  local variable_name="$2"

  if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
    echo "[deploy] $variable_name must be a numeric host ID, not a user or group name" >&2
    exit 1
  fi
}

TEMP_FILES=()

cleanup_temp_files() {
  local temporary_file

  for temporary_file in "${TEMP_FILES[@]}"; do
    [[ -n "$temporary_file" ]] && rm -f -- "$temporary_file"
  done
}

trap cleanup_temp_files EXIT

if [[ "${CERT_EXPORT_ENABLED}" != "true" ]]; then
  exit 0
fi

if [[ ! -d "${CERT_EXPORT_PATH}" ]]; then
  echo "[deploy] export path ${CERT_EXPORT_PATH} does not exist; skipping copy" >&2
  exit 0
fi

require_simple_filename "$CERT_EXPORT_PUBLIC_NAME" CERT_EXPORT_PUBLIC_NAME
require_simple_filename "$CERT_EXPORT_PRIVATE_NAME" CERT_EXPORT_PRIVATE_NAME
require_simple_filename "$CERT_EXPORT_DEPLOY_MARKER" CERT_EXPORT_DEPLOY_MARKER
require_octal_mode "$CERT_EXPORT_PUBLIC_MODE" CERT_EXPORT_PUBLIC_MODE
require_octal_mode "$CERT_EXPORT_PRIVATE_MODE" CERT_EXPORT_PRIVATE_MODE
require_numeric_id "$CERT_EXPORT_UID" CERT_EXPORT_UID
require_numeric_id "$CERT_EXPORT_GID" CERT_EXPORT_GID

if [[ "$CERT_EXPORT_PUBLIC_NAME" == "$CERT_EXPORT_PRIVATE_NAME" || "$CERT_EXPORT_PUBLIC_NAME" == "$CERT_EXPORT_DEPLOY_MARKER" || "$CERT_EXPORT_PRIVATE_NAME" == "$CERT_EXPORT_DEPLOY_MARKER" ]]; then
  echo "[deploy] public, private, and marker file names must be distinct" >&2
  exit 1
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

if [[ ! -f "$FULLCHAIN_PATH" || ! -r "$FULLCHAIN_PATH" ]]; then
  echo "[deploy] certificate file is missing or unreadable: $FULLCHAIN_PATH" >&2
  exit 1
fi

if [[ ! -f "$PRIVKEY_PATH" || ! -r "$PRIVKEY_PATH" ]]; then
  echo "[deploy] private-key file is missing or unreadable: $PRIVKEY_PATH" >&2
  exit 1
fi

PUBLIC_TARGET="${CERT_EXPORT_PATH}/${CERT_EXPORT_PUBLIC_NAME}"
PRIVATE_TARGET="${CERT_EXPORT_PATH}/${CERT_EXPORT_PRIVATE_NAME}"
MARKER_TARGET="${CERT_EXPORT_PATH}/${CERT_EXPORT_DEPLOY_MARKER}"

stage_file() {
  local source_path="$1"
  local target_path="$2"
  local mode="$3"

  STAGED_FILE=$(mktemp "${target_path}.tmp.XXXXXX")
  TEMP_FILES+=("$STAGED_FILE")
  install -m "$mode" "$source_path" "$STAGED_FILE"

  if [[ -n "${CERT_EXPORT_UID}" || -n "${CERT_EXPORT_GID}" ]]; then
    chown "${CERT_EXPORT_UID:-}:${CERT_EXPORT_GID:-}" "$STAGED_FILE"
  fi
}

stage_file "$FULLCHAIN_PATH" "$PUBLIC_TARGET" "$CERT_EXPORT_PUBLIC_MODE"
PUBLIC_TEMP=$STAGED_FILE
stage_file "$PRIVKEY_PATH" "$PRIVATE_TARGET" "$CERT_EXPORT_PRIVATE_MODE"
PRIVATE_TEMP=$STAGED_FILE

# Rename only fully written, permissioned files into place. The marker is
# created last, so host-side reload helpers never observe a half-deployed pair.
mv -f -- "$PUBLIC_TEMP" "$PUBLIC_TARGET"
mv -f -- "$PRIVATE_TEMP" "$PRIVATE_TARGET"
TEMP_FILES=()

MARKER_TEMP=$(mktemp "${MARKER_TARGET}.tmp.XXXXXX")
TEMP_FILES+=("$MARKER_TEMP")
printf 'renewed_at=%s\nrenewed_lineage=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${RENEWED_LINEAGE:-}" > "$MARKER_TEMP"
chmod 0600 "$MARKER_TEMP"
mv -f -- "$MARKER_TEMP" "$MARKER_TARGET"
TEMP_FILES=()
