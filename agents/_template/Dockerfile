ARG BASE_PLATFORM=linux/amd64
ARG AGENT_BASE_IMAGE=ghcr.io/gitlayzer/agent-devbox-base:0.1.0
FROM --platform=${BASE_PLATFORM} ${AGENT_BASE_IMAGE}

ARG AGENT_NAME=change-me
ENV AGENT_NAME=${AGENT_NAME} \
    AGENT_HOME=/opt/agent \
    AGENT_DATA_DIR=/home/agent/.change-me \
    AGENT_WORKSPACE=/workspace \
    AGENT_PORT=8080 \
    AGENT_LOG_LEVEL=info \
    PATH=/opt/agent/bin:$PATH

LABEL org.opencontainers.image.title="${AGENT_NAME}" \
      org.opencontainers.image.description="Agent Hub runtime image" \
      org.opencontainers.image.source="agents/${AGENT_NAME}"

COPY agents/_template/build.env /tmp/build.env
COPY agents/_template/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install agent \
    && rm -f /tmp/build.env /tmp/install.sh

COPY agents/_template/entrypoint.sh /opt/agent/entrypoint.sh
RUN getent group agent >/dev/null || groupadd --gid 10001 agent \
    && id -u agent >/dev/null 2>&1 || useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash agent \
    && chmod +x /opt/agent/entrypoint.sh \
    && mkdir -p "${AGENT_WORKSPACE}" "${AGENT_HOME}" "${AGENT_DATA_DIR}" \
    && chown -R agent:agent /opt/agent "${AGENT_WORKSPACE}" "${AGENT_DATA_DIR}"

WORKDIR ${AGENT_WORKSPACE}
VOLUME ["/workspace", "/home/agent/.change-me"]
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
