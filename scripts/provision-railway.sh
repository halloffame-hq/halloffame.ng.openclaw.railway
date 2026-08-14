#!/usr/bin/env bash

set -euo pipefail

MOUNT_PATH="${OPENCLAW_VOLUME_MOUNT_PATH:-/data}"

command -v railway >/dev/null 2>&1 || {
  printf 'Railway CLI is required.\n' >&2
  exit 64
}

command -v jq >/dev/null 2>&1 || {
  printf 'jq is required.\n' >&2
  exit 64
}

railway_args=()

if [[ -n "${RAILWAY_SERVICE_ID:-}" ]]; then
  railway_args+=(--service "$RAILWAY_SERVICE_ID")
fi

if [[ -n "${RAILWAY_ENVIRONMENT_ID:-}" ]]; then
  railway_args+=(--environment "$RAILWAY_ENVIRONMENT_ID")
fi

volumes_json="$(
  railway volume list \
    "${railway_args[@]}" \
    --json
)"

if jq -e \
  --arg mount "$MOUNT_PATH" \
  '
    .. |
    objects |
    select(
      (.mountPath? // .mount_path? // .mount? // "") == $mount
    )
  ' >/dev/null <<<"$volumes_json"
then
  printf 'Railway volume already mounted at %s.\n' "$MOUNT_PATH"
  exit 0
fi

printf 'No existing persistent volume found. Explicitly provisioning a new Railway volume at %s...\n' "$MOUNT_PATH"

railway volume add \
  "${railway_args[@]}" \
  --mount-path "$MOUNT_PATH"

printf 'Railway volume created and mounted at %s.\n' "$MOUNT_PATH"
