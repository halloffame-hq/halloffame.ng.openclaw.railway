ARG OPENCLAW_VERSION=latest
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gosu \
        jq \
        tar \
    && rm -rf /var/lib/apt/lists/*

ARG HOF_PLUGINS_REPO=halloffame-hq/halloffame.plugins
ARG HOF_PLUGINS_REF=main

RUN set -eux; \
    mkdir -p /tmp/halloffame-plugins /opt/openclaw-skills/halloffame; \
    curl -fsSL \
      "https://codeload.github.com/${HOF_PLUGINS_REPO}/tar.gz/${HOF_PLUGINS_REF}" \
      | tar -xz --strip-components=1 -C /tmp/halloffame-plugins; \
    test -f /tmp/halloffame-plugins/agents/halloffame/SKILL.md; \
    test -f /tmp/halloffame-plugins/agents/halloffame/scripts/api.sh; \
    bash -n /tmp/halloffame-plugins/agents/halloffame/scripts/api.sh; \
    cp -a /tmp/halloffame-plugins/agents/halloffame/. /opt/openclaw-skills/halloffame/; \
    chmod +x /opt/openclaw-skills/halloffame/scripts/api.sh; \
    rm -rf /tmp/halloffame-plugins

COPY scripts/start.sh /usr/local/bin/railway-openclaw-start
RUN chmod 0755 /usr/local/bin/railway-openclaw-start

ENV OPENCLAW_HOME=/data \
    OPENCLAW_STATE_DIR=/data/.openclaw \
    OPENCLAW_CONFIG_PATH=/data/.openclaw/openclaw.json

ENTRYPOINT ["tini", "-s", "--"]
CMD ["/usr/local/bin/railway-openclaw-start"]
