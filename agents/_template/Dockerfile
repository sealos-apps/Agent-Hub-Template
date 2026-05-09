FROM ghcr.io/gitlayzer/ubuntu:22.04-base

ARG AGENT_HOME=/opt/change-me
ENV AGENT_HOME=${AGENT_HOME} \
    AGENT_NAME=change-me \
    AGENT_RUNTIME_KIND=service

COPY agents/_template/build.env /tmp/build.env
COPY agents/_template/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && set -a \
    && . /tmp/build.env \
    && set +a \
    && /tmp/install.sh install agent \
    && rm -f /tmp/build.env /tmp/install.sh

COPY agents/_template/config.json /opt/agent/config.json
COPY agents/_template/config.sh /opt/agent/config.sh
COPY agents/_template/entrypoint.sh /opt/agent/entrypoint.sh
RUN getent group agent >/dev/null || groupadd --gid 10001 agent \
    && id -u agent >/dev/null 2>&1 || useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash agent \
    && chmod +x /opt/agent/config.sh /opt/agent/entrypoint.sh \
    && chmod 0644 /opt/agent/config.json \
    && mkdir -p /workspace "$AGENT_HOME" /home/agent/.change-me \
    && chown -R agent:agent /opt/agent "$AGENT_HOME" /workspace /home/agent/.change-me

WORKDIR /workspace
VOLUME ["/workspace"]
ENTRYPOINT ["/init", "/opt/agent/entrypoint.sh"]
CMD ["start"]
