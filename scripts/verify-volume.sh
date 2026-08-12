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
  printf 'Persistent Railway volume confirmed at %s.\n' "$MOUNT_PATH"
  exit 0
fi

printf 'No Railway volume is mounted at %s.\n' "$MOUNT_PATH" >&2
printf 'Deployment aborted to protect persistent OpenClaw agent state.\n' >&2
printf 'Run scripts/provision-railway.sh only when intentionally provisioning the service for the first time.\n' >&2
exit 1
