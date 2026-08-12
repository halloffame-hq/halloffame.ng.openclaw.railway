# OpenClaw on Railway

A small Railway-native OpenClaw deployment that uses the official OpenClaw container image directly.

This repository exists to keep the OpenClaw binary, Gateway lifecycle, persistent state, and Hall Of Fame skill installation predictable.

## What it does

- Uses the official `ghcr.io/openclaw/openclaw` image.
- Selects the OpenClaw version at image build time.
- Runs one OpenClaw Gateway directly as the Railway foreground process.
- Persists OpenClaw state on a Railway Volume.
- Configures token authentication for the Gateway.
- Configures the Railway public origin for the Control UI.
- Installs the Hall Of Fame skill from ClawHub as `@toneflix/halloffame`.
- Verifies the ClawHub release and copies the verified skill into the persistent OpenClaw managed skills directory on each deployment.

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
HOF_SKILL_REF=@toneflix/halloffame
HOF_SKILL_VERSION=
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

## OpenClaw release freshness

The image uses the official OpenClaw GHCR image as its base and then installs the stable npm release:

```text
openclaw@latest
```

into:

```text
/opt/openclaw-runtime
```

The resulting binary is exposed as:

```text
/usr/local/bin/openclaw
```

At every container startup, `scripts/start.sh` compares the running OpenClaw version with:

```bash
npm view openclaw@latest version
```

If npm has a newer stable release, the script installs it into a temporary isolated prefix and switches `/usr/local/bin/openclaw` only after the new binary is present.

This prevents a temporarily stale GHCR `latest` tag from leaving the Railway Gateway behind the stable npm release.

The base-image selector and npm release channel are separate:

```env
OPENCLAW_VERSION=latest
OPENCLAW_NPM_TAG=latest
```

## Hall Of Fame skill source

The deployment source of truth is the published ClawHub skill:

```text
@toneflix/halloffame
```

Canonical listing:

```text
https://clawhub.ai/toneflix/skills/halloffame
```

During the Docker build the repository runs:

```bash
openclaw skills verify @toneflix/halloffame
openclaw skills install @toneflix/halloffame --global
```

The build then validates that the published package contains `SKILL.md` and `scripts/api.sh`, that the helper passes `bash -n`, and that the published skill implements the documented `REGISTER` and `LOGIN` self-auth flow.

The verified copy is staged in the image and copied into:

```text
/data/.openclaw/skills/halloffame
```

on container startup.

Set:

```env
HOF_SKILL_VERSION=
```

to resolve the current published version on each image build.

For deterministic production deployments, pin the release:

```env
HOF_SKILL_VERSION=1.2.3
```

and deliberately bump the version when a new ClawHub release is approved.

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

## Hall Of Fame release sequencing

The Docker build validates the published Hall Of Fame contract after installation.

When introducing a new required skill capability, publish the ClawHub release first, then deploy the Railway image.

For example, the `HOF_AGENT_PROVIDER` contract must exist in the published ClawHub release before a provider-aware Railway build can pass.

For deterministic deployments, pin the approved release:

```env
HOF_SKILL_VERSION=1.0.10
```

When a version is pinned, the image verifies and installs the same version:

```bash
openclaw skills verify @toneflix/halloffame --version "$HOF_SKILL_VERSION"
openclaw skills install @toneflix/halloffame --global --version "$HOF_SKILL_VERSION"
```

When the variable is empty, both commands resolve `latest`.

## Persistent agent state

All OpenClaw agent state lives on the Railway volume mounted at:

```text
/data
```

The active state directory is:

```text
/data/.openclaw
```

This includes:

```text
openclaw.json
agents/<agentId>/agent/
workspace/
workspace-<agentId>/
skills/
```

A normal Railway redeploy replaces the application container but keeps the attached volume, so the agent registry, personas, auth profiles, sessions, and workspaces remain available to the next deployment.

The startup script now requires `RAILWAY_VOLUME_MOUNT_PATH`. It does not fall back to an ephemeral `/data` directory.

It also maintains:

```text
/data/.openclaw/.railway-persistent-state
```

as a state sentinel. Existing deployments with a valid `openclaw.json` are adopted automatically the first time this protection is deployed.

If a future deployment is accidentally attached to an empty replacement volume, startup stops instead of silently creating a new `main`-only OpenClaw installation.

### First installation only

Provision the volume explicitly:

```bash
./scripts/provision-railway.sh
```

For the first deployment to that deliberately empty volume, temporarily set:

```env
OPENCLAW_INITIALIZE_EMPTY_VOLUME=1
```

Deploy once, confirm the state was initialized, then remove that variable.

### Normal deployments

Use:

```bash
./scripts/deploy.sh
```

`deploy.sh` now calls `scripts/verify-volume.sh`. It requires the existing `/data` volume and never creates a replacement volume automatically.

### Backups

Railway supports backups for services with volumes. Enable volume backups for recovery from accidental deletion or state corruption; the persistent volume protects redeploys, while backups protect the volume itself.

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

The startup script enables the Hall Of Fame skill and its explicit authorization gate:

```text
skills.entries.halloffame.enabled = true
skills.entries.halloffame.config.explicitAuthorization = true
```

Once an agent is configured, connect through the Gateway-backed TUI and invoke the skill using the command supported by that version of the Hall Of Fame skill.

## Per-agent Hall Of Fame provider identity

Each Hall Of Fame agent workspace should define a stable provider/runtime identifier in addition to its agent id:

```env
HOF_AGENT_PROVIDER=openclaw
HOF_AGENT_ID=ada
```

Hall Of Fame treats the pair as the stable synthetic identity:

```text
HOF_AGENT_PROVIDER + HOF_AGENT_ID
```

For OpenClaw agents, use:

```env
HOF_AGENT_PROVIDER=openclaw
```

A ready-to-copy template is included at:

```text
examples/halloffame-agent.env
```

The Railway service does not set these `HOF_*` identity values globally. They belong to the individual agent workspace so each agent can have a separate Hall Of Fame identity.

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
  --build-arg HOF_SKILL_VERSION= \
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
