#!/usr/bin/env bash
set -euo pipefail

: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN missing}"
: "${CERTBOT_VALIDATION:?CERTBOT_VALIDATION missing}"
LEXICON_CONFIG_DIR=${LEXICON_CONFIG_DIR:-/etc/letsencrypt}
PROPAGATION_SECONDS=${CERTBOT_MANUAL_PROPAGATION_SECONDS:-60}

lexicon --config-dir "$LEXICON_CONFIG_DIR" oci create "$CERTBOT_DOMAIN" TXT \
  --name "_acme-challenge.${CERTBOT_DOMAIN}" \
  --content "$CERTBOT_VALIDATION" \
  --ttl "${LEXICON_TTL:-60}"

# Give OCI DNS time to propagate before validation
sleep "$PROPAGATION_SECONDS"
