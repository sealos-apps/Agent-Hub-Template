FROM ghcr.io/gitlayzer/ubuntu:22.04-base

ENV HERMES_HOME=/home/agent/.hermes \
    HERMES_SRC=/opt/hermes/src \
    HERMES_VENV=/opt/hermes/venv \
    PATH=/opt/hermes/venv/bin:$PATH

COPY agents/hermes/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && /tmp/install.sh \
    && rm -f /tmp/install.sh

COPY agents/hermes/config.sh /opt/agent/config.sh
COPY agents/hermes/entrypoint.sh /opt/agent/entrypoint.sh
RUN chmod +x /opt/agent/config.sh /opt/agent/entrypoint.sh \
    && mkdir -p "$HERMES_HOME" \
    && chown -R agent:agent /opt/agent /opt/hermes /workspace "$HERMES_HOME"

USER agent
WORKDIR /workspace
VOLUME ["/home/agent/.hermes"]
ENTRYPOINT ["/opt/agent/entrypoint.sh"]
CMD ["start"]
