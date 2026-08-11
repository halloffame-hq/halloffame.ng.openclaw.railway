#!/usr/bin/env bash

set -euo pipefail

: "${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN is required}"

PORT="${PORT:-18789}"
DATA_DIR="${RAILWAY_VOLUME_MOUNT_PATH:-${OPENCLAW_HOME:-/data}}"

export OPENCLAW_HOME="$DATA_DIR"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-$DATA_DIR/.openclaw}"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$OPENCLAW_STATE_DIR/openclaw.json}"

run_openclaw() {
  gosu node env \
    OPENCLAW_HOME="$OPENCLAW_HOME" \
    OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
    OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
    OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
    openclaw "$@"
}

install -d -m 0755 -o node -g node "$DATA_DIR"
install -d -m 0700 -o node -g node \
  "$OPENCLAW_STATE_DIR" \
  "$OPENCLAW_STATE_DIR/skills" \
  "$OPENCLAW_STATE_DIR/workspace"

rm -rf "$OPENCLAW_STATE_DIR/skills/halloffame"
cp -a /opt/openclaw-skills/halloffame "$OPENCLAW_STATE_DIR/skills/halloffame"
chown -R node:node "$OPENCLAW_STATE_DIR/skills/halloffame"
chmod +x "$OPENCLAW_STATE_DIR/skills/halloffame/scripts/api.sh"

if [[ ! -f "$OPENCLAW_CONFIG_PATH" ]]; then
  run_openclaw setup --baseline --workspace "$OPENCLAW_STATE_DIR/workspace"
fi

run_openclaw config set gateway.mode local
run_openclaw config set gateway.bind lan
run_openclaw config set gateway.auth.mode token
run_openclaw config set skills.entries.halloffame.config.explicitAuthorization true

PUBLIC_ORIGIN="${OPENCLAW_PUBLIC_ORIGIN:-}"

if [[ -z "$PUBLIC_ORIGIN" && -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]]; then
  PUBLIC_ORIGIN="https://${RAILWAY_PUBLIC_DOMAIN}"
fi

if [[ -n "$PUBLIC_ORIGIN" ]]; then
  run_openclaw config set \
    gateway.controlUi.allowedOrigins \
    "[\"${PUBLIC_ORIGIN}\"]" \
    --strict-json
fi

run_openclaw config validate

printf 'OpenClaw version: '
run_openclaw --version

printf 'State directory: %s\n' "$OPENCLAW_STATE_DIR"
printf 'Gateway port: %s\n' "$PORT"

exec gosu node env \
  OPENCLAW_HOME="$OPENCLAW_HOME" \
  OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
  OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
  OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  openclaw gateway \
    --bind lan \
    --port "$PORT" \
    --auth token
