ARG BASE_PLATFORM=linux/amd64
ARG AGENT_BASE_IMAGE=ghcr.io/sealos-apps/agent-devbox-base
FROM --platform=${BASE_PLATFORM} ${AGENT_BASE_IMAGE}

ARG http_proxy
ARG https_proxy
ARG all_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG no_proxy
ARG NO_PROXY

ENV AGENT_NAME=openclaw \
    AGENT_HOME=/opt/agent \
    AGENT_DATA_DIR=/root/.openclaw \
    AGENT_WORKSPACE=/workspace \
    AGENT_PORT=18789 \
    AGENT_LOG_LEVEL=info \
    OPENCLAW_STATE_DIR=/root/.openclaw \
    OPENCLAW_CONFIG_PATH=/root/.openclaw/openclaw.json \
    OPENCLAW_WORKSPACE=/workspace \
    PATH=/opt/agent/bin:/usr/local/bin:$PATH

LABEL org.opencontainers.image.title="OpenClaw" \
      org.opencontainers.image.description="OpenClaw gateway adapter for Agent Hub" \
      org.opencontainers.image.source="agents/openclaw" \
      org.opencontainers.image.version="latest" \
      org.sealos.agent.version="latest"

COPY agents/openclaw/build.env /tmp/build.env
COPY agents/openclaw/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env /tmp/install.sh

COPY agents/openclaw/entrypoint.sh /opt/agent/entrypoint.sh
RUN chmod +x /opt/agent/entrypoint.sh \
    && mkdir -p "$OPENCLAW_STATE_DIR" "$AGENT_WORKSPACE" \
    && chmod 0775 "$AGENT_WORKSPACE"

WORKDIR ${AGENT_WORKSPACE}
VOLUME ["/workspace", "/root/.openclaw"]
EXPOSE 18789
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
