#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install-docker.sh —— 在 Debian/Ubuntu / CentOS/RHEL 上一键安装 Docker CE + Compose v2
#
# 参考官方文档，国内机器会自动探测并可选切到阿里云/清华镜像源。
# 仅在未安装 docker 或 docker compose 时执行安装，已安装会直接跳过。
# ---------------------------------------------------------------------------
set -euo pipefail

need_restart_docker=false

have_docker() { command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; }
have_compose() { docker compose version >/dev/null 2>&1; }

if have_docker && have_compose; then
  echo "Docker + docker compose 已安装，跳过。"
  docker --version
  docker compose version
  exit 0
fi

# ---- distro detection ------------------------------------------------------
. /etc/os-release 2>/dev/null || true
DISTRO_ID="${ID:-unknown}"
DISTRO_VER="${VERSION_ID:-}"
USE_MIRROR="${USE_MIRROR:-1}"                 # 0=官方源 1=自动选国内镜像

case "${DISTRO_ID}" in
  ubuntu|debian|linuxmint|pop|elementary|kali|neon|zorin)
    FAMILY="debian"
    ;;
  centos|rhel|rocky|almalinux|fedora|ol|amzn|cloudlinux)
    FAMILY="rhel"
    ;;
  *)
    FAMILY="unknown"
    ;;
esac

is_china_network() {
  # 轻量探测：100ms 内能否连通阿里云镜像站，大概率是国内
  local out
  out="$(curl -sS --max-time 1 -o /dev/null -w '%{http_code}' \
         https://mirrors.aliyun.com/docker-ce 2>/dev/null || echo 000)"
  [[ "${out}" =~ ^200|30[12]$ ]]
}

# ---- debian family ---------------------------------------------------------
install_debian() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  local keyring="/usr/share/keyrings/docker-archive-keyring.gpg"
  local repo_url="https://download.docker.com/linux/${DISTRO_ID}"

  if [[ "${USE_MIRROR}" == "1" ]] && is_china_network; then
    echo "(检测到国内网络) 使用阿里云 Docker CE 镜像源"
    repo_url="https://mirrors.aliyun.com/docker-ce/linux/${DISTRO_ID}"
  fi

  rm -f "${keyring}"
  curl -fsSL "${repo_url}/gpg" | gpg --dearmor -o "${keyring}"
  chmod a+r "${keyring}"

  local arch
  arch="$(dpkg --print-architecture)"
  local codename
  codename="$(lsb_release -cs 2>/dev/null || echo "${VERSION_CODENAME:-}")"
  [[ -n "${codename}" ]] || codename="stable"

  echo \
    "deb [arch=${arch} signed-by=${keyring}] ${repo_url} ${codename} stable" \
    >/etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  need_restart_docker=true
}

# ---- rhel family -----------------------------------------------------------
install_rhel() {
  local repo_url="https://download.docker.com/linux/${DISTRO_ID}"
  if [[ "${USE_MIRROR}" == "1" ]] && is_china_network; then
    echo "(检测到国内网络) 使用阿里云 Docker CE 镜像源"
    repo_url="https://mirrors.aliyun.com/docker-ce/linux/${DISTRO_ID}"
  fi

  if command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
  else
    PKG_MGR="yum"
  fi

  "${PKG_MGR}" install -y yum-utils device-mapper-persistent-data lvm2
  "${PKG_MGR}" config-manager --add-repo "${repo_url}/docker-ce.repo"
  "${PKG_MGR}" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker || true
  need_restart_docker=true
}

# ---- dispatch --------------------------------------------------------------
case "${FAMILY}" in
  debian) install_debian ;;
  rhel)   install_rhel ;;
  *)
    echo "不支持的系统：${DISTRO_ID}。请手动安装 Docker + docker compose v2。"
    echo "参考：https://docs.docker.com/engine/install/"
    exit 1
    ;;
esac

if [[ "${need_restart_docker}" == "true" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable docker || true
    if systemctl is-system-running --quiet 2>/dev/null || systemctl is-active --quiet systemd 2>/dev/null; then
      systemctl restart docker || true
    fi
  fi
fi

# ---- verify ---------------------------------------------------------------
echo
docker --version
docker compose version
echo
echo "Docker 安装完成。接下来部署 ChatGPT2API："
echo "  bash deploy/quick-deploy.sh"
