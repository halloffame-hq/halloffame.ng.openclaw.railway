# OpenClaw on Railway (With Hall Of Fame skill)

A small Railway-native OpenClaw deployment that uses the official OpenClaw container image directly.

This repository exists to keep the OpenClaw binary, Gateway lifecycle, persistent state, and Hall Of Fame skill installation predictable.

## What it does

- Uses the official `ghcr.io/openclaw/openclaw` image.
- Selects the OpenClaw version at image build time.
- Runs one OpenClaw Gateway directly as the Railway foreground process.
- Persists OpenClaw state on a Railway Volume.
- Configures token authentication for the Gateway.
- Configures the Railway public origin for the Control UI.
- Fetches the Hall Of Fame skill from `halloffame-hq/halloffame.plugins/agents/halloffame`.
- Copies that skill into the persistent OpenClaw managed skills directory on each deployment.

## Repository structure

```text
.
├── Dockerfile
├── railway.json
├── .env.example
└── scripts/
    └── start.sh
```

The Hall Of Fame skill is intentionally not duplicated in this repository.

Its source of truth is:

```text
halloffame-hq/halloffame.plugins
└── agents/
    └── halloffame/
        ├── SKILL.md
        └── scripts/
            └── api.sh
```

## One-command Railway provisioning and deploy

The repository includes a wrapper that provisions the persistent volume before deploying:

```bash
./scripts/deploy.sh
```

The wrapper runs:

```text
check selected Railway service
        ↓
look for a volume mounted at /data
        ↓
create it when missing
        ↓
railway up
```

It uses the Railway CLI and `jq`.

Install the Railway CLI and authenticate it, then link the repository to the intended Railway project/service:

```bash
railway login
railway link
```

After that, deploy with:

```bash
./scripts/deploy.sh
```

The volume provisioning step can also be run independently:

```bash
./scripts/provision-railway.sh
```

The default mount path is:

```text
/data
```

It can be overridden with:

```bash
OPENCLAW_VOLUME_MOUNT_PATH=/some/path ./scripts/deploy.sh
```

For automation where the service and environment are supplied explicitly, the scripts also accept Railway's standard context variables:

```bash
RAILWAY_SERVICE_ID=<service-id> \
RAILWAY_ENVIRONMENT_ID=<environment-id> \
./scripts/deploy.sh
```

The provisioning script is idempotent: if the selected service already has a volume mounted at the configured path, it leaves it in place and continues.

## Deploy to Railway

Create a new Railway service from this GitHub repository.

Railway detects the root `Dockerfile` automatically.

### Add a persistent volume

Attach one Railway Volume to the service and mount it at:

```text
/data
```

The deployment stores its OpenClaw state under:

```text
/data/.openclaw
```

This includes configuration, agents, sessions, workspaces, credentials, and managed skills.

### Add variables

At minimum:

```env
OPENCLAW_GATEWAY_TOKEN=<long-random-secret>
```

Recommended build variables:

```env
OPENCLAW_VERSION=latest
HOF_PLUGINS_REPO=halloffame-hq/halloffame.plugins
HOF_PLUGINS_REF=main
```

For a deterministic production deployment, replace `latest` with an exact official OpenClaw release tag:

```env
OPENCLAW_VERSION=<release-tag>
```

`HOF_PLUGINS_REF` can also be an exact commit SHA when you want the Hall Of Fame skill pinned to a known revision.

Add whichever model/provider credentials your OpenClaw agents require.

For example:

```env
OPENAI_API_KEY=...
```

or configure the provider later through OpenClaw.

### Generate a Railway domain

Generate a public domain for the service under Railway Networking.

On the next deployment Railway exposes it as `RAILWAY_PUBLIC_DOMAIN`, and `scripts/start.sh` adds:

```text
https://<RAILWAY_PUBLIC_DOMAIN>
```

to OpenClaw's `gateway.controlUi.allowedOrigins`.

For a custom domain, set:

```env
OPENCLAW_PUBLIC_ORIGIN=https://openclaw.example.com
```

## Startup flow

Each container start performs:

```text
Railway volume mounted at /data
        ↓
repair /data/.openclaw ownership to node (uid/gid 1000)
        ↓
baseline OpenClaw state created when missing
        ↓
Hall Of Fame skill copied into /data/.openclaw/skills/halloffame
        ↓
gateway.mode = local
gateway.bind = lan
gateway.auth.mode = token
        ↓
Railway/custom Control UI origin configured
        ↓
OpenClaw config validated
        ↓
Gateway starts on Railway's $PORT
```

The Gateway is the foreground process supervised by Railway.

## Automatic volume ownership recovery

Railway may mount a persistent volume with root ownership. The container startup script repairs the OpenClaw state before invoking the CLI:

```bash
chown node:node "$DATA_DIR"
chown -R node:node "$OPENCLAW_STATE_DIR"
```

This runs on every container start, before `openclaw setup`, `openclaw config`, validation, or Gateway startup.

If a previous deployment wrote `/data/.openclaw/openclaw.json` as root, deploying a new image with this startup script repairs the persisted file automatically. Shell access to the failed deployment is not required.

## Verify the deployment

Open a Railway shell and run:

```bash
openclaw --version
```

Check the service port:

```bash
echo "$PORT"
```

Probe the running Gateway:

```bash
openclaw gateway probe \
  --url "ws://127.0.0.1:$PORT" \
  --token "$OPENCLAW_GATEWAY_TOKEN"
```

Connect the TUI:

```bash
openclaw tui \
  --url "ws://127.0.0.1:$PORT" \
  --token "$OPENCLAW_GATEWAY_TOKEN"
```

## Hall Of Fame skill

The image fetches the Hall Of Fame skill at build time from:

```text
https://github.com/halloffame-hq/halloffame.plugins/tree/main/agents/halloffame
```

At runtime it is installed at:

```text
/data/.openclaw/skills/halloffame
```

Verify:

```bash
openclaw skills list
```

and:

```bash
openclaw skills check
```

The startup script also enables the skill's explicit authorization gate:

```text
skills.entries.halloffame.config.explicitAuthorization = true
```

Once an agent is configured, connect through the Gateway-backed TUI and invoke the skill using the command supported by that version of the Hall Of Fame skill.

## Create agents

List agents:

```bash
openclaw agents list
```

Create an agent:

```bash
openclaw agents add ada \
  --workspace "$OPENCLAW_STATE_DIR/workspace-ada"
```

Then verify:

```bash
openclaw agents list
```

Each OpenClaw agent gets its own workspace and session state under the persistent volume.

## Upgrading OpenClaw

OpenClaw upgrades are image upgrades.

Change:

```env
OPENCLAW_VERSION=<new-official-release-tag>
```

and redeploy the Railway service.

The official OpenClaw container performs startup-safe migrations against the persisted state when an image is replaced.

The running container is never responsible for replacing its own OpenClaw binary.

## Updating the Hall Of Fame skill

The Hall Of Fame skill is fetched during image build.

To pull the newest `main` revision, trigger a new Railway deployment.

For a pinned revision:

```env
HOF_PLUGINS_REF=<commit-sha>
```

Redeploy after changing the value.

## Local Docker test

Build:

```bash
docker build \
  --build-arg OPENCLAW_VERSION=latest \
  --build-arg HOF_PLUGINS_REF=main \
  -t openclaw-railway .
```

Create a local state directory:

```bash
mkdir -p .local-data
```

Run:

```bash
docker run --rm \
  -p 18789:18789 \
  -e PORT=18789 \
  -e OPENCLAW_GATEWAY_TOKEN=local-development-token-change-me \
  -e OPENCLAW_PUBLIC_ORIGIN=http://localhost:18789 \
  -v "$PWD/.local-data:/data" \
  openclaw-railway
```

Then probe:

```bash
docker exec <container-id> \
  openclaw gateway probe \
  --url ws://127.0.0.1:18789 \
  --token local-development-token-change-me
```

## Railway healthcheck

`railway.json` configures:

```text
GET /healthz
```

as the deployment healthcheck.

## Important paths

```text
/data
└── .openclaw
    ├── openclaw.json
    ├── agents/
    ├── skills/
    │   └── halloffame/
    └── workspace*
```
