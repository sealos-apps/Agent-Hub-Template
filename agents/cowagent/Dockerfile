ARG BASE_PLATFORM=linux/amd64
FROM --platform=${BASE_PLATFORM} ghcr.io/gitlayzer/ubuntu:22.04-base

ARG AI_AGENT_SWITCH_VERSION
ARG AI_AGENT_SWITCH_METADATA
ARG AI_AGENT_SWITCH_SOURCE_URL
ARG AI_AGENT_SWITCH_SOURCE_REF

ENV AGENT_NAME=cowagent \
    AGENT_HOME=/opt/agent \
    AGENT_DATA_DIR=/home/agent/.cowagent \
    AGENT_WORKSPACE=/workspace \
    AGENT_PORT=9899 \
    AGENT_LOG_LEVEL=info \
    COWAGENT_SRC=/opt/cowagent/src \
    COWAGENT_VENV=/opt/cowagent/venv \
    COWAGENT_HOME=/home/agent/.cowagent \
    PATH=/opt/agent/bin:/opt/cowagent/venv/bin:$PATH

LABEL org.opencontainers.image.title="CowAgent" \
      org.opencontainers.image.description="CowAgent runtime image packaged for Agent Hub" \
      org.opencontainers.image.source="agents/cowagent" \
      org.opencontainers.image.version="2.0.8" \
      org.sealos.agent.version="2.0.8" \
      org.sealos.ai-agent-switch.version="${AI_AGENT_SWITCH_VERSION}" \
      org.sealos.ai-agent-switch.metadata="${AI_AGENT_SWITCH_METADATA}"

COPY agents/cowagent/build.env /tmp/build.env
COPY agents/cowagent/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && export AI_AGENT_SWITCH_VERSION="${AI_AGENT_SWITCH_VERSION}" \
    && export AI_AGENT_SWITCH_SOURCE_URL="${AI_AGENT_SWITCH_SOURCE_URL}" \
    && export AI_AGENT_SWITCH_SOURCE_REF="${AI_AGENT_SWITCH_SOURCE_REF}" \
    && /tmp/install.sh install agent \
    && rm -f /tmp/build.env \
    && rm -f /tmp/install.sh

COPY agents/cowagent/entrypoint.sh /opt/agent/entrypoint.sh
RUN getent group agent >/dev/null || groupadd --gid 10001 agent \
    && id -u agent >/dev/null 2>&1 || useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash agent \
    && chmod +x /opt/agent/entrypoint.sh \
    && mkdir -p "$COWAGENT_HOME" "$AGENT_WORKSPACE" \
    && chown -R agent:agent /opt/agent /opt/cowagent "$AGENT_WORKSPACE" "$COWAGENT_HOME"

WORKDIR ${AGENT_WORKSPACE}
VOLUME ["/workspace", "/home/agent/.cowagent"]
EXPOSE 9899
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${AGENT_PORT:-9899}/auth/check" >/dev/null || exit 1
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
