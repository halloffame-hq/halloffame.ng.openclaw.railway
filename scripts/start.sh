#!/usr/bin/env bash

set -euo pipefail

: "${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN is required}"

PORT="${PORT:-18789}"

: "${RAILWAY_VOLUME_MOUNT_PATH:?A persistent Railway volume is required for OpenClaw state. Mount the service volume at /data.}"

DATA_DIR="$RAILWAY_VOLUME_MOUNT_PATH"

export OPENCLAW_HOME="$DATA_DIR"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-$DATA_DIR/.openclaw}"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$OPENCLAW_STATE_DIR/openclaw.json}"
STATE_SENTINEL="$OPENCLAW_STATE_DIR/.railway-persistent-state"


ensure_latest_openclaw() {
  local current_version latest_version candidate

  current_version="$(
    openclaw --version 2>/dev/null \
      | grep -Eo '[0-9]{4}\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?' \
      | head -n 1
  )"

  latest_version="$(npm view openclaw@latest version --silent)"

  if [[ -z "$latest_version" ]]; then
    printf 'Unable to resolve openclaw@latest from npm.\n' >&2
    exit 1
  fi

  if [[ "$current_version" == "$latest_version" ]]; then
    printf 'OpenClaw is current: %s\n' "$current_version"
    return 0
  fi

  printf 'Updating OpenClaw from %s to %s...\n' \
    "${current_version:-unknown}" \
    "$latest_version"

  candidate="/opt/openclaw-runtime-next"
  rm -rf "$candidate"

  npm install \
    --global \
    --prefix "$candidate" \
    "openclaw@${latest_version}"

  test -x "$candidate/bin/openclaw"

  rm -rf /opt/openclaw-runtime
  mv "$candidate" /opt/openclaw-runtime
  ln -sfn /opt/openclaw-runtime/bin/openclaw /usr/local/bin/openclaw

  printf 'OpenClaw active version: '
  openclaw --version
}

ensure_latest_openclaw

run_openclaw() {
  gosu node env \
    OPENCLAW_HOME="$OPENCLAW_HOME" \
    OPENCLAW_STATE_DIR="$OPENCLAW_STATE_DIR" \
    OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG_PATH" \
    OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
    openclaw "$@"
}

normalize_agent_workspaces() {
  local workspace

  while IFS= read -r -d '' workspace; do
    chown -R node:node "$workspace"
    chmod -R u+rwX,go-rwx "$workspace"

    if [[ -f "$workspace/.env" ]]; then
      chmod 600 "$workspace/.env"
    fi

    printf 'Normalized agent workspace: %s\n' "$workspace"
  done < <(
    find "$OPENCLAW_STATE_DIR" \
      -maxdepth 1 \
      -type d \
      -name 'workspace*' \
      -print0
  )
}

# /*
#  * Railway volumes may be mounted with root ownership. OpenClaw runs as
#  * the node user (uid/gid 1000), so repair persisted state ownership
#  * before invoking any OpenClaw command.
#  */
install -d -m 0755 "$DATA_DIR"
install -d -m 0700 \
  "$OPENCLAW_STATE_DIR" \
  "$OPENCLAW_STATE_DIR/skills" \
  "$OPENCLAW_STATE_DIR/workspace"

chown node:node "$DATA_DIR"
chown -R node:node "$OPENCLAW_STATE_DIR"
normalize_agent_workspaces

rm -rf "$OPENCLAW_STATE_DIR/skills/halloffame"
cp -a /opt/openclaw-skills/halloffame "$OPENCLAW_STATE_DIR/skills/halloffame"
chown -R node:node "$OPENCLAW_STATE_DIR/skills/halloffame"
chmod +x "$OPENCLAW_STATE_DIR/skills/halloffame/scripts/api.sh"

# /*
#  * Existing installations created before the state sentinel was introduced
#  * are adopted automatically when their OpenClaw config is already present.
#  * An empty/replacement volume is never initialized silently.
#  */
if [[ -f "$OPENCLAW_CONFIG_PATH" ]]; then
  if [[ ! -f "$STATE_SENTINEL" ]]; then
    {
      printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'railway_volume_name=%s\n' "${RAILWAY_VOLUME_NAME:-unknown}"
    } > "$STATE_SENTINEL"

    chown node:node "$STATE_SENTINEL"
    chmod 600 "$STATE_SENTINEL"
    printf 'Adopted existing persistent OpenClaw state.\n'
  fi
else
  if [[ -f "$STATE_SENTINEL" ]]; then
    printf 'Persistent OpenClaw state marker exists, but %s is missing. Refusing to initialize over damaged state.\n' \
      "$OPENCLAW_CONFIG_PATH" >&2
    exit 1
  fi

  if [[ "${OPENCLAW_INITIALIZE_EMPTY_VOLUME:-0}" != "1" ]]; then
    printf 'The attached Railway volume contains no OpenClaw config.\n' >&2
    printf 'Refusing to create a fresh agent registry automatically.\n' >&2
    printf 'For the first installation only, set OPENCLAW_INITIALIZE_EMPTY_VOLUME=1, deploy once, then remove it.\n' >&2
    exit 1
  fi

  run_openclaw setup --baseline --workspace "$OPENCLAW_STATE_DIR/workspace"

  {
    printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'railway_volume_name=%s\n' "${RAILWAY_VOLUME_NAME:-unknown}"
  } > "$STATE_SENTINEL"

  chown node:node "$STATE_SENTINEL"
  chmod 600 "$STATE_SENTINEL"
  printf 'Initialized persistent OpenClaw state on the attached Railway volume.\n'
fi

normalize_agent_workspaces

run_openclaw config set gateway.mode local
run_openclaw config set gateway.bind lan
run_openclaw config set gateway.auth.mode token
run_openclaw config set skills.entries.halloffame.enabled true
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
