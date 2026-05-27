ARG BASE_PLATFORM=linux/amd64
ARG AGENT_BASE_IMAGE=ghcr.io/nightwhite/agent-devbox-base
FROM --platform=${BASE_PLATFORM} ${AGENT_BASE_IMAGE}

ARG http_proxy
ARG https_proxy
ARG all_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG no_proxy
ARG NO_PROXY

ENV AGENT_NAME=hermes-agent \
    AGENT_HOME=/opt/agent \
    AGENT_DATA_DIR=/root/.hermes \
    AGENT_WORKSPACE=/workspace \
    AGENT_PORT=8642 \
    AGENT_LOG_LEVEL=info \
    HERMES_HOME=/root/.hermes \
    HERMES_SRC=/opt/hermes/src \
    HERMES_VENV=/opt/hermes/venv \
    API_SERVER_ENABLED=true \
    API_SERVER_HOST=0.0.0.0 \
    API_SERVER_PORT=8642 \
    PATH=/opt/agent/bin:/opt/hermes/venv/bin:$PATH

LABEL org.opencontainers.image.title="Hermes Agent" \
      org.opencontainers.image.description="Hermes adapter for Agent Hub" \
      org.opencontainers.image.source="agents/hermes-agent" \
      org.opencontainers.image.version="latest" \
      org.sealos.agent.version="latest"

COPY agents/hermes-agent/build.env /tmp/build.env
COPY agents/hermes-agent/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env /tmp/install.sh

COPY agents/hermes-agent/entrypoint.sh /opt/agent/entrypoint.sh
RUN chmod +x /opt/agent/entrypoint.sh \
    && mkdir -p "$HERMES_HOME" "$AGENT_WORKSPACE" \
    && chmod 0775 "$AGENT_WORKSPACE"

WORKDIR ${AGENT_WORKSPACE}
VOLUME ["/workspace", "/root/.hermes"]
EXPOSE 8642
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD test -n "$API_SERVER_KEY" && curl -fsS -H "Authorization: Bearer ${API_SERVER_KEY}" "http://127.0.0.1:${API_SERVER_PORT:-8642}/v1/models" >/dev/null || exit 1
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
