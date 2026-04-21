FROM ghcr.io/gitlayzer/ubuntu:22.04-base

ARG AGENT_HOME=/opt/change-me
ENV AGENT_HOME=${AGENT_HOME}

COPY agents/change-me/install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh \
    && /tmp/install.sh install agent \
    && rm -f /tmp/install.sh

COPY agents/change-me/config.sh /opt/agent/config.sh
COPY agents/change-me/entrypoint.sh /opt/agent/entrypoint.sh
RUN chmod +x /opt/agent/config.sh /opt/agent/entrypoint.sh \
    && mkdir -p /workspace ${AGENT_HOME} /home/agent/.change-me \
    && chown -R agent:agent /opt/agent ${AGENT_HOME} /workspace /home/agent/.change-me

USER agent
WORKDIR /workspace
VOLUME ["/workspace"]
ENTRYPOINT ["/opt/agent/entrypoint.sh"]
CMD ["shell"]
