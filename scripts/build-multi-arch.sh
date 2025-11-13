#!/usr/bin/env bash
set -euo pipefail

PODMAN_BIN=${PODMAN_BIN:-podman}
BUILDER_NAME=${BUILDER_NAME:-oci-dns-certbot-builder}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64}
IMAGE_TAG=${IMAGE_TAG:-${1:-}}
PUSH_LATEST=${PUSH_LATEST:-false}
BUILD_CONTEXT=${BUILD_CONTEXT:-.}
PUSH=${PUSH:-true}

if [[ -z "$IMAGE_TAG" ]]; then
  echo "Usage: IMAGE_TAG=registry/namespace/oci-dns-certbot:<tag> ./scripts/build-multi-arch.sh" >&2
  echo "Or pass the tag as the first argument." >&2
  exit 1
fi

CLEANUP_MANIFEST=${CLEANUP_MANIFEST:-true}
MANIFEST_NAME=${MANIFEST_NAME:-oci-dns-certbot-manifest}

if ! "$PODMAN_BIN" buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
  "$PODMAN_BIN" buildx create --name "$BUILDER_NAME" >/dev/null
fi
export BUILDX_BUILDER="$BUILDER_NAME"

if [[ "$PUSH" == "true" ]]; then
  BUILD_CMD=("$PODMAN_BIN" buildx build "$BUILD_CONTEXT" \
    --platform "$PLATFORMS" \
    -t "$IMAGE_TAG" \
    --manifest "$MANIFEST_NAME")
else
  if [[ "$PLATFORMS" == *,* ]]; then
    echo "Local loads only support a single platform; set PLATFORMS=linux/amd64 (for example)." >&2
    exit 1
  fi
  BUILD_CMD=("$PODMAN_BIN" buildx build "$BUILD_CONTEXT" \
    --platform "$PLATFORMS" \
    -t "$IMAGE_TAG" \
    --load)
fi

echo "Running: ${BUILD_CMD[*]}"
"${BUILD_CMD[@]}"

if [[ "$PUSH" == "true" ]]; then
  echo "Pushing manifest $MANIFEST_NAME to $IMAGE_TAG"
  "$PODMAN_BIN" manifest push "$MANIFEST_NAME" "$IMAGE_TAG"
  if [[ "$PUSH_LATEST" == "true" ]]; then
    LATEST_TAG="${IMAGE_TAG%:*}:latest"
    echo "Also pushing $LATEST_TAG"
    "$PODMAN_BIN" manifest push "$MANIFEST_NAME" "$LATEST_TAG"
  fi
  if [[ "$CLEANUP_MANIFEST" == "true" ]]; then
    "$PODMAN_BIN" manifest rm "$MANIFEST_NAME" >/dev/null 2>&1 || true
  fi
fi
