#!/usr/bin/env bash
set -euo pipefail

# Default directories (override with env vars if needed)
CERTBOT_CONFIG_DIR=${CERTBOT_CONFIG_DIR:-/etc/letsencrypt}
CERTBOT_WORK_DIR=${CERTBOT_WORK_DIR:-/var/lib/letsencrypt}
CERTBOT_LOG_DIR=${CERTBOT_LOG_DIR:-/var/log/letsencrypt}
HOOK_DIR=/opt/certbot/hooks
LEXICON_CONFIG_PATH=${LEXICON_CONFIG_PATH:-${CERTBOT_CONFIG_DIR}/lexicon_oci.yml}
CERT_EXPORT_PATH=${CERT_EXPORT_PATH:-/export}

mkdir -p "$CERTBOT_CONFIG_DIR" "$CERTBOT_WORK_DIR" "$CERTBOT_LOG_DIR"

if [[ -d "$CERT_EXPORT_PATH" ]]; then
  export CERT_EXPORT_PATH
fi

# Helper for env validation
require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Environment variable $name is required" >&2
    exit 1
  fi
}

# Parse domains from CERT_DOMAINS (comma/space separated)
require_env CERT_DOMAINS
IFS=',' read -ra RAW_DOMAINS <<< "$CERT_DOMAINS"
DOMAINS=()
for raw in "${RAW_DOMAINS[@]}"; do
  trimmed=$(echo "$raw" | xargs)
  [[ -z "$trimmed" ]] && continue
  DOMAINS+=("$trimmed")
done

if [[ ${#DOMAINS[@]} -eq 0 ]]; then
  echo "CERT_DOMAINS did not contain any valid domains" >&2
  exit 1
fi
PRIMARY_DOMAIN=${CERT_PRIMARY_DOMAIN:-${DOMAINS[0]}}

require_env CERTBOT_EMAIL

# OCI credential templating (unless the user supplied the file themselves)
if [[ ! -f "$LEXICON_CONFIG_PATH" || "${LEXICON_CONFIG_FORCE_OVERWRITE:-false}" == "true" ]]; then
  require_env OCI_AUTH_USER
  require_env OCI_AUTH_TENANCY
  require_env OCI_AUTH_FINGERPRINT
  require_env OCI_AUTH_REGION
  require_env OCI_AUTH_COMPARTMENT
  OCI_AUTH_KEY_FILE=${OCI_AUTH_KEY_FILE:-/secrets/oci_api_key.pem}
  if [[ ! -f "$OCI_AUTH_KEY_FILE" ]]; then
    echo "OCI API key file $OCI_AUTH_KEY_FILE does not exist" >&2
    exit 1
  fi
  cat > "$LEXICON_CONFIG_PATH" <<EOF_CONF
auth_user: ${OCI_AUTH_USER}
auth_tenancy: ${OCI_AUTH_TENANCY}
auth_fingerprint: ${OCI_AUTH_FINGERPRINT}
auth_region: ${OCI_AUTH_REGION}
auth_compartment: ${OCI_AUTH_COMPARTMENT}
auth_key_file: ${OCI_AUTH_KEY_FILE}
ttl: ${LEXICON_TTL:-60}
EOF_CONF
fi

export LEXICON_CONFIG_DIR="$(dirname "$LEXICON_CONFIG_PATH")"
export CERTBOT_MANUAL_PROPAGATION_SECONDS=${CERTBOT_MANUAL_PROPAGATION_SECONDS:-60}

DOMAIN_FLAGS=()
for domain in "${DOMAINS[@]}"; do
  DOMAIN_FLAGS+=("-d" "$domain")
done

CERTBOT_BIN=${CERTBOT_BIN:-certbot}

CMD=("$CERTBOT_BIN" certonly \
  --manual \
  --preferred-challenges dns \
  --manual-auth-hook "$HOOK_DIR/auth.sh" \
  --manual-cleanup-hook "$HOOK_DIR/cleanup.sh" \
  --deploy-hook "$HOOK_DIR/deploy.sh" \
  --agree-tos \
  --non-interactive \
  --keep-until-expiring \
  --config-dir "$CERTBOT_CONFIG_DIR" \
  --work-dir "$CERTBOT_WORK_DIR" \
  --logs-dir "$CERTBOT_LOG_DIR" \
  --cert-name "$PRIMARY_DOMAIN" \
  --email "$CERTBOT_EMAIL"
)

if [[ "${CERTBOT_STAGING:-false}" == "true" ]]; then
  CMD+=(--staging)
fi

if [[ "${CERTBOT_FORCE_RENEWAL:-false}" == "true" ]]; then
  CMD+=(--force-renewal)
fi

if [[ "${CERTBOT_DRY_RUN:-false}" == "true" ]]; then
  CMD+=(--dry-run)
fi

if [[ -n "${CERTBOT_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=( ${CERTBOT_EXTRA_ARGS} )
  CMD+=("${EXTRA_ARGS[@]}")
fi

CMD+=("${DOMAIN_FLAGS[@]}")

exec "${CMD[@]}"
