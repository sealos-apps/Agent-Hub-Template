FROM ghcr.io/gitlayzer/ubuntu:22.04-base

ARG http_proxy
ARG https_proxy
ARG all_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG ALL_PROXY
ARG no_proxy
ARG NO_PROXY

ENV AGENT_NAME=hermes-agent \
    AGENT_RUNTIME_KIND=service \
    HERMES_HOME=/home/agent/.hermes \
    HERMES_SRC=/opt/hermes/src \
    HERMES_VENV=/opt/hermes/venv \
    API_SERVER_ENABLED=true \
    API_SERVER_HOST=0.0.0.0 \
    API_SERVER_PORT=8642 \
    API_SERVER_KEY=change-me-local-dev \
    PATH=/opt/hermes/venv/bin:$PATH

COPY agents/hermes-agent/build.env /tmp/build.env
COPY agents/hermes-agent/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install \
    && rm -f /tmp/build.env /tmp/install.sh

COPY agents/hermes-agent/config.json /opt/agent/config.json
COPY agents/hermes-agent/config.sh /opt/agent/config.sh
COPY agents/hermes-agent/entrypoint.sh /opt/agent/entrypoint.sh
RUN getent group agent >/dev/null || groupadd --gid 10001 agent \
    && id -u agent >/dev/null 2>&1 || useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash agent \
    && chmod +x /opt/agent/config.sh /opt/agent/entrypoint.sh \
    && chmod 0644 /opt/agent/config.json \
    && mkdir -p "$HERMES_HOME" /workspace \
    && chown -R agent:agent /opt/agent /opt/hermes /workspace "$HERMES_HOME"

WORKDIR /workspace
VOLUME ["/home/agent/.hermes"]
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
