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

ENV AGENT_NAME=deepseek-harness \
    AGENT_HOME=/opt/agent \
    AGENT_DATA_DIR=/root/.dsh \
    AGENT_WORKSPACE=/workspace \
    AGENT_PORT=3080 \
    AGENT_LOG_LEVEL=info \
    DSH_HOME=/root/.dsh \
    PATH=/opt/agent/bin:/usr/local/bin:$PATH

LABEL org.opencontainers.image.title="DeepSeek Harness" \
      org.opencontainers.image.description="DeepSeek Harness web workbench adapter for Agent Hub" \
      org.opencontainers.image.source="agents/deepseek-harness" \
      org.opencontainers.image.version="latest" \
      org.sealos.agent.version="latest"

COPY agents/deepseek-harness/build.env /tmp/build.env
COPY agents/deepseek-harness/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env /tmp/install.sh

COPY agents/deepseek-harness/entrypoint.sh /opt/agent/entrypoint.sh
RUN chmod +x /opt/agent/entrypoint.sh \
    && mkdir -p "$DSH_HOME" "$AGENT_WORKSPACE" \
    && chmod 0775 "$AGENT_WORKSPACE"

WORKDIR ${AGENT_WORKSPACE}
VOLUME ["/workspace", "/root/.dsh"]
EXPOSE 3080
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
