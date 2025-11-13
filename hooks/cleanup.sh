#!/usr/bin/env bash
set -euo pipefail

: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN missing}"
: "${CERTBOT_VALIDATION:?CERTBOT_VALIDATION missing}"
LEXICON_CONFIG_DIR=${LEXICON_CONFIG_DIR:-/etc/letsencrypt}

lexicon --config-dir "$LEXICON_CONFIG_DIR" oci delete "$CERTBOT_DOMAIN" TXT \
  --name "_acme-challenge.${CERTBOT_DOMAIN}" \
  --content "$CERTBOT_VALIDATION"
