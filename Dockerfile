ARG OPENCLAW_VERSION=latest
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gosu \
        jq \
        python3 \
        tar \
    && rm -rf /var/lib/apt/lists/*

# /*
#  * GHCR's moving `latest` tag can temporarily trail the npm stable release.
#  * Install the npm `latest` package into an isolated prefix and make it the
#  * active CLI/runtime for the rest of the image build.
#  */
ARG OPENCLAW_NPM_TAG=latest
RUN set -eux; \
    npm install --global --prefix /opt/openclaw-runtime "openclaw@${OPENCLAW_NPM_TAG}"; \
    ln -sfn /opt/openclaw-runtime/bin/openclaw /usr/local/bin/openclaw; \
    openclaw --version

COPY scripts/verify-halloffame-skill.py /usr/local/bin/verify-halloffame-skill
RUN chmod 0755 /usr/local/bin/verify-halloffame-skill

ARG HOF_SKILL_REF=@toneflix/halloffame
ARG HOF_SKILL_VERSION=

RUN set -eux; \
    skill_home=/tmp/halloffame-clawhub; \
    rm -rf "$skill_home" /opt/openclaw-skills/halloffame; \
    mkdir -p "$skill_home" /opt/openclaw-skills; \
    export HOME="$skill_home"; \
    export OPENCLAW_HOME="$skill_home"; \
    export OPENCLAW_STATE_DIR="$skill_home/.openclaw"; \
    export OPENCLAW_CONFIG_PATH="$OPENCLAW_STATE_DIR/openclaw.json"; \
    if [ -n "$HOF_SKILL_VERSION" ]; then \
      openclaw skills verify "$HOF_SKILL_REF" --version "$HOF_SKILL_VERSION"; \
      openclaw skills install "$HOF_SKILL_REF" --global --version "$HOF_SKILL_VERSION"; \
    else \
      openclaw skills verify "$HOF_SKILL_REF"; \
      openclaw skills install "$HOF_SKILL_REF" --global; \
    fi; \
    installed="$OPENCLAW_STATE_DIR/skills/halloffame"; \
    test -f "$installed/SKILL.md"; \
    test -f "$installed/scripts/api.sh"; \
    bash -n "$installed/scripts/api.sh"; \
    grep -q '^disable-model-invocation: false$' "$installed/SKILL.md"; \
    grep -q 'api.sh REGISTER' "$installed/SKILL.md"; \
    grep -q 'api.sh LOGIN' "$installed/SKILL.md"; \
    grep -q 'REGISTER)' "$installed/scripts/api.sh"; \
    grep -q 'LOGIN)' "$installed/scripts/api.sh"; \
    grep -q 'HOF_AGENT_PROVIDER' "$installed/SKILL.md"; \
    grep -q 'HOF_AGENT_PROVIDER' "$installed/scripts/api.sh"; \
    grep -q 'agent_provider: env.HOF_AGENT_PROVIDER' "$installed/scripts/api.sh"; \
    /usr/local/bin/verify-halloffame-skill "$installed/SKILL.md"; \
    if grep -q 'HOF_TOKEN.*Bearer token' "$installed/scripts/api.sh"; then \
      echo 'Published Hall Of Fame helper still requires a manual HOF_TOKEN.' >&2; \
      exit 1; \
    fi; \
    cp -a "$installed" /opt/openclaw-skills/halloffame; \
    chmod +x /opt/openclaw-skills/halloffame/scripts/api.sh; \
    rm -rf "$skill_home"

COPY scripts/start.sh /usr/local/bin/railway-openclaw-start
RUN chmod 0755 /usr/local/bin/railway-openclaw-start

ENV OPENCLAW_HOME=/data \
    OPENCLAW_STATE_DIR=/data/.openclaw \
    OPENCLAW_CONFIG_PATH=/data/.openclaw/openclaw.json

ENTRYPOINT ["tini", "-s", "--"]
CMD ["/usr/local/bin/railway-openclaw-start"]
