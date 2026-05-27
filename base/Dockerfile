ARG BASE_PLATFORM=linux/amd64
ARG UBUNTU_VERSION=22.04
FROM --platform=${BASE_PLATFORM} ubuntu:${UBUNTU_VERSION}

ARG BASE_IMAGE_VERSION=0.1.0
ARG DEFAULT_DEVBOX_USER=devbox
ARG NODE_MAJOR=22
ARG PYTHON_MAJOR_MINOR=3.11
ARG UV_VERSION=0.5.29
ARG L10N=en_US
ARG TARGETARCH
ARG ARCH=${TARGETARCH:-amd64}

ENV BASE_IMAGE_VERSION=${BASE_IMAGE_VERSION} \
    DEFAULT_DEVBOX_USER=${DEFAULT_DEVBOX_USER} \
    NODE_MAJOR=${NODE_MAJOR} \
    PYTHON_MAJOR_MINOR=${PYTHON_MAJOR_MINOR} \
    UV_VERSION=${UV_VERSION} \
    L10N=${L10N} \
    ARCH=${ARCH} \
    DEBIAN_FRONTEND=noninteractive \
    BASE_TOOLS_DIR=/opt/base-tools \
    PROJECT_DIR=/home/devbox/project \
    AGENT_HOME=/opt/agent \
    AGENT_WORKSPACE=/workspace \
    S6_STAGE2_HOOK=/etc/s6-overlay-hook/pre-rc-init.d/pre-rc-init.sh \
    S6_KILL_GRACETIME=500 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

LABEL org.opencontainers.image.title="Agent Hub Devbox Base" \
      org.opencontainers.image.description="Devbox-compatible base image for Agent Hub adapters" \
      org.opencontainers.image.version="${BASE_IMAGE_VERSION}" \
      org.opencontainers.image.source="base"

COPY devbox-runtime/tooling/scripts ${BASE_TOOLS_DIR}/scripts
COPY devbox-runtime/tooling/docs ${BASE_TOOLS_DIR}/docs
COPY base/install.sh /tmp/install-agent-devbox-base.sh

RUN chmod -R +x ${BASE_TOOLS_DIR}/scripts /tmp/install-agent-devbox-base.sh \
    && /tmp/install-agent-devbox-base.sh \
    && rm -f /tmp/install-agent-devbox-base.sh \
    && rm -rf ${BASE_TOOLS_DIR}

WORKDIR /workspace
ENTRYPOINT ["/init"]
