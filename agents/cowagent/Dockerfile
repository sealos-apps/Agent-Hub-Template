ARG BASE_PLATFORM=linux/amd64
ARG AGENT_BASE_IMAGE=ghcr.io/nightwhite/agent-devbox-base
FROM --platform=${BASE_PLATFORM} ${AGENT_BASE_IMAGE}

ENV AGENT_NAME=cowagent \
    AGENT_HOME=/opt/agent \
    AGENT_DATA_DIR=/root/.cowagent \
    AGENT_WORKSPACE=/workspace \
    AGENT_PORT=9899 \
    AGENT_LOG_LEVEL=info \
    COWAGENT_SRC=/opt/cowagent/src \
    COWAGENT_VENV=/opt/cowagent/venv \
    COWAGENT_HOME=/root/.cowagent \
    PATH=/opt/agent/bin:/opt/cowagent/venv/bin:$PATH

LABEL org.opencontainers.image.title="CowAgent" \
      org.opencontainers.image.description="CowAgent runtime image packaged for Agent Hub" \
      org.opencontainers.image.source="agents/cowagent" \
      org.opencontainers.image.version="latest" \
      org.sealos.agent.version="latest"

COPY agents/cowagent/build.env /tmp/build.env
COPY agents/cowagent/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env \
    && rm -f /tmp/install.sh

COPY agents/cowagent/entrypoint.sh /opt/agent/entrypoint.sh
RUN chmod +x /opt/agent/entrypoint.sh \
    && mkdir -p "$COWAGENT_HOME" "$AGENT_WORKSPACE" \
    && chmod 0775 "$AGENT_WORKSPACE"

WORKDIR ${AGENT_WORKSPACE}
VOLUME ["/workspace", "/root/.cowagent"]
EXPOSE 9899
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${AGENT_PORT:-9899}/auth/check" >/dev/null || exit 1
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
