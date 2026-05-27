#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DEVBOX_USER="${DEFAULT_DEVBOX_USER:-devbox}"
NODE_MAJOR="${NODE_MAJOR:-22}"
PYTHON_MAJOR_MINOR="${PYTHON_MAJOR_MINOR:-3.11}"
UV_VERSION="${UV_VERSION:-0.5.29}"
BASE_TOOLS_DIR="${BASE_TOOLS_DIR:-/opt/base-tools}"
L10N="${L10N:-en_US}"

log() {
  printf '[%s] [base] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

normalize_arch() {
  case "${ARCH:-$(uname -m)}" in
    amd64|x86_64)
      printf 'amd64'
      ;;
    arm64|aarch64)
      printf 'arm64'
      ;;
    armv7|armhf)
      printf 'armv7'
      ;;
    *)
      printf '%s' "${ARCH:-$(uname -m)}"
      ;;
  esac
}

install_devbox_runtime() {
  log "installing devbox runtime services"
  "${BASE_TOOLS_DIR}/scripts/install-base-pkg-deb.sh"
  "${BASE_TOOLS_DIR}/scripts/install-crond.sh"
  "${BASE_TOOLS_DIR}/scripts/install-s6.sh"
  "${BASE_TOOLS_DIR}/scripts/install-sdk-server.sh"
  "${BASE_TOOLS_DIR}/scripts/configure-svc.sh"
  "${BASE_TOOLS_DIR}/scripts/configure-logrotate.sh"
  "${BASE_TOOLS_DIR}/scripts/configure-login.sh"
  "${BASE_TOOLS_DIR}/scripts/configure-l10n.sh"
  "${BASE_TOOLS_DIR}/scripts/configure-user.sh" "${DEFAULT_DEVBOX_USER}"

  install -d /usr/share/devbox/docs
  cp "${BASE_TOOLS_DIR}"/docs/README.s6-user-guide*.md /usr/share/devbox/docs/
  chmod 0644 /usr/share/devbox/docs/README.s6-user-guide*.md
}

prepare_agent_paths() {
  log "preparing root agent runtime paths"
  mkdir -p /opt/agent /workspace "/home/${DEFAULT_DEVBOX_USER}/project" "/home/${DEFAULT_DEVBOX_USER}/workspace"
  chown -R "${DEFAULT_DEVBOX_USER}:${DEFAULT_DEVBOX_USER}" "/home/${DEFAULT_DEVBOX_USER}/project" "/home/${DEFAULT_DEVBOX_USER}/workspace"
  chmod 0775 /workspace
}

install_node_runtime() {
  log "installing Node.js ${NODE_MAJOR}"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y --no-install-recommends nodejs
  npm cache clean --force

  if [[ "${L10N}" == "zh_CN" ]]; then
    npm config set --global registry https://registry.npmmirror.com/
    printf '%s\n' 'registry=https://registry.npmmirror.com/' >/etc/npmrc
    printf '%s\n' 'registry=https://registry.npmmirror.com/' >/root/.npmrc
    for user in "${DEFAULT_DEVBOX_USER}"; do
      local home_dir
      home_dir="$(getent passwd "$user" | cut -d: -f6)"
      printf '%s\n' 'registry=https://registry.npmmirror.com/' >"${home_dir}/.npmrc"
      chown "$user:$user" "${home_dir}/.npmrc"
    done
  fi
}

install_python_runtime() {
  log "installing Python ${PYTHON_MAJOR_MINOR} tooling"
  apt-get update
  apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv

  python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel

  if [[ "${PYTHON_MAJOR_MINOR}" != "$(python3 - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)" ]]; then
    log "requested Python ${PYTHON_MAJOR_MINOR} differs from distro python; keeping distro python for base layer"
  fi

  if [[ "${L10N}" == "zh_CN" ]]; then
    python3 -m pip config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
  fi
}

install_uv() {
  log "installing uv ${UV_VERSION}"
  local arch
  arch="$(normalize_arch)"
  case "$arch" in
    amd64)
      uv_arch=x86_64-unknown-linux-gnu
      ;;
    arm64)
      uv_arch=aarch64-unknown-linux-gnu
      ;;
    *)
      log "skipping uv binary install for unsupported architecture: $arch"
      return
      ;;
  esac

  curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${uv_arch}.tar.gz" -o /tmp/uv.tar.gz
  mkdir -p /tmp/uv
  tar -xzf /tmp/uv.tar.gz -C /tmp/uv --strip-components=1
  install -m 0755 /tmp/uv/uv /usr/local/bin/uv
  if [[ -f /tmp/uv/uvx ]]; then
    install -m 0755 /tmp/uv/uvx /usr/local/bin/uvx
  fi
  mkdir -p /root/.local/bin
  ln -sf /usr/local/bin/uv /root/.local/bin/uv
  ln -sf /usr/local/bin/uvx /root/.local/bin/uvx || true
  rm -rf /tmp/uv /tmp/uv.tar.gz
}

install_common_agent_packages() {
  log "installing minimal common tools"
  apt-get update
  apt-get install -y --no-install-recommends \
    file \
    less \
    zip \
    unzip \
    netbase \
    gawk \
    findutils \
    grep \
    sed \
    tar \
    gzip \
    ripgrep
  # Devbox runtime installs these, but they are intentionally outside the minimal base.
  apt-get purge -y jq vim
  apt-get clean
  rm -rf /var/lib/apt/lists/*
}

cleanup_image() {
  log "cleaning package caches"
  apt-get clean
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
  find /var/log -type f -delete || true
}

verify_base() {
  log "verifying base image contract"
  test -x /init
  id "${DEFAULT_DEVBOX_USER}" >/dev/null
  command -v node >/dev/null
  command -v npm >/dev/null
  command -v python3 >/dev/null
  command -v pip3 >/dev/null
  python3 -m venv /tmp/base-venv-check
  rm -rf /tmp/base-venv-check
  command -v uv >/dev/null
  command -v rg >/dev/null
  for tool in bash busybox curl wget git file less openssl tar gzip xz zip unzip rsync ssh sshd locale logrotate ps ip ping lsof getent find grep sed gawk; do
    if ! command -v "$tool" >/dev/null; then
      log "required tool is missing: $tool"
      exit 1
    fi
  done
  test -x /usr/sbin/devbox-sdk-server
  test -f /etc/s6-overlay/s6-rc.d/startup/run
  test -f /etc/s6-overlay/s6-rc.d/sdk-server/run
  test -f /etc/s6-overlay-hook/pre-rc-init.d/pre-rc-init.sh
  test -d /workspace
}

main() {
  export DEBIAN_FRONTEND=noninteractive
  export ARCH="${ARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}"

  install_devbox_runtime
  prepare_agent_paths
  install_node_runtime
  install_python_runtime
  install_uv
  install_common_agent_packages
  verify_base
  cleanup_image
}

main "$@"
