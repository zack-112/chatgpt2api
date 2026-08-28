#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# quick-deploy.sh —— ChatGPT2API 一键部署/刷新（Docker Compose，零交互）
#
# 用途：
#   1) 全新机器第一次部署（自动创建目录、生成密钥与 .env、拉镜像、起服务）
#   2) 已有部署刷新到最新镜像（仅 pull + up -d，不会丢 data / config）
#
# 前置要求：
#   - Docker + docker compose v2（没有就先跑：bash deploy/install-docker.sh）
#
# 自定义：把下列变量以环境变量传入即可，例如：
#   PORT=8080 AUTH_KEY=xxx INSTALL_DIR=/data/chatgpt2api bash deploy/quick-deploy.sh
# ---------------------------------------------------------------------------
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/chatgpt2api}"
PORT="${CHATGPT2API_PORT:-${PORT:-3000}}"
THREAD_TOKENS="${CHATGPT2API_THREAD_TOKENS:-${THREAD_TOKENS:-120}}"
AUTH_KEY="${CHATGPT2API_AUTH_KEY:-${AUTH_KEY:-}}"
MODE="${MODE:-docker}"                        # 仅 docker 模式；本脚本不处理 python 源码模式
DATABASE_MODE="${DATABASE_MODE:-sqlite}"      # sqlite | postgres-local | postgres-url
DATABASE_URL="${DATABASE_URL:-}"
POSTGRES_DB="${POSTGRES_DB:-chatgpt2api}"
POSTGRES_USER="${POSTGRES_USER:-chatgpt2api}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
TZ="${TZ:-Asia/Shanghai}"
IMAGE="${CHATGPT2API_IMAGE:-ghcr.io/zack-112/chatgpt2api:latest}"
COMPOSE_FILES=(-f docker-compose.yml)

# ------- helpers ------------------------------------------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: 缺少命令 $1，请先安装。"; exit 1; }; }

generate_auth_key() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 24; return; fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then tr -d '-' </proc/sys/kernel/random/uuid; return; fi
  date +%s%N
}

ensure_dir() { mkdir -p "$1"; }

download_if_missing() {
  local src="$1" dst="$2"
  [[ -f "${dst}" ]] && return 0
  if [[ -f "${DEPLOY_REPO_LOCAL}/${src}" ]]; then
    cp "${DEPLOY_REPO_LOCAL}/${src}" "${dst}"
    return 0
  fi
  curl -fsSL "https://raw.githubusercontent.com/zack-112/chatgpt2api/main/${src}" -o "${dst}"
}

need_cmd docker
if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 未检测到 docker compose v2。请先安装 Docker："
  echo "       bash deploy/install-docker.sh  # 若存在该脚本"
  echo "       或参考 https://docs.docker.com/engine/install/"
  exit 1
fi

DEPLOY_REPO_LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd 2>/dev/null || echo "")"

# ------- database-specific compose overlay & validation --------------------
case "${DATABASE_MODE}" in
  sqlite)
    DATABASE_URL=""
    ;;
  postgres-local)
    COMPOSE_FILES+=(-f docker-compose.postgres.yml)
    DATABASE_URL=""
    [[ -n "${POSTGRES_PASSWORD}" ]] || POSTGRES_PASSWORD="$(generate_auth_key)"
    ;;
  postgres-url)
    if [[ -z "${DATABASE_URL}" ]]; then
      echo "ERROR: DATABASE_MODE=postgres-url 必须提供 DATABASE_URL。"
      exit 1
    fi
    ;;
  *)
    echo "ERROR: DATABASE_MODE 只能是 sqlite / postgres-local / postgres-url。"
    exit 1
    ;;
esac

[[ -n "${AUTH_KEY}" ]] || AUTH_KEY="$(generate_auth_key)"

ensure_dir "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

download_if_missing docker-compose.yml        "${INSTALL_DIR}/docker-compose.yml"
[[ "${DATABASE_MODE}" == "postgres-local" ]] && \
  download_if_missing docker-compose.postgres.yml "${INSTALL_DIR}/docker-compose.postgres.yml"

# ------- .env ---------------------------------------------------------------
ENV_FILE="${INSTALL_DIR}/.env"
# 保留用户已有值，只在缺省时写入
load_env() { [[ -f "${ENV_FILE}" ]] && set -a && source "${ENV_FILE}" && set +a || true; }
load_env
: "${CHATGPT2API_AUTH_KEY:=${AUTH_KEY}}"
: "${CHATGPT2API_PORT:=${PORT}}"
: "${CHATGPT2API_THREAD_TOKENS:=${THREAD_TOKENS}}"
: "${CHATGPT2API_IMAGE:=${IMAGE}}"
: "${CHATGPT2API_BASE_URL:=}"
: "${DATABASE_MODE:=${DATABASE_MODE}}"
: "${DATABASE_URL:=${DATABASE_URL}}"
: "${POSTGRES_DB:=${POSTGRES_DB}}"
: "${POSTGRES_USER:=${POSTGRES_USER}}"
: "${POSTGRES_PASSWORD:=${POSTGRES_PASSWORD}}"
: "${TZ:=${TZ}}"

cat >"${ENV_FILE}" <<EOF
CHATGPT2API_AUTH_KEY=${CHATGPT2API_AUTH_KEY}
CHATGPT2API_PORT=${CHATGPT2API_PORT}
CHATGPT2API_THREAD_TOKENS=${CHATGPT2API_THREAD_TOKENS}
CHATGPT2API_IMAGE=${CHATGPT2API_IMAGE}
CHATGPT2API_BASE_URL=${CHATGPT2API_BASE_URL}

DATABASE_MODE=${DATABASE_MODE}
DATABASE_URL=${DATABASE_URL}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
TZ=${TZ}
EOF
chmod 600 "${ENV_FILE}" || true

# ------- config.json --------------------------------------------------------
CONFIG_FILE="${INSTALL_DIR}/config.json"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  AUTH_ESCAPED="${CHATGPT2API_AUTH_KEY//\\/\\\\}"
  AUTH_ESCAPED="${AUTH_ESCAPED//\"/\\\"}"
  cat >"${CONFIG_FILE}.tmp" <<EOF
{
  "auth-key": "${AUTH_ESCAPED}"
}
EOF
  mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
  chmod 600 "${CONFIG_FILE}" || true
fi

mkdir -p "${INSTALL_DIR}/data"

# ------- deploy -------------------------------------------------------------
echo "==> 拉取镜像：${CHATGPT2API_IMAGE}"
docker compose "${COMPOSE_FILES[@]}" pull

echo "==> 启动 / 刷新容器（保留 data/ 与 config.json）"
# 对 volume 场景：chatgpt2api-runtime 内 marker 会判断镜像版本，
# 新镜像启动时 entrypoint 自动拷贝新 seed 到 runtime，无需手动清理 volume。
docker compose "${COMPOSE_FILES[@]}" up -d

# ------- summary ------------------------------------------------------------
echo
echo "=========================== 部署完成 ==========================="
echo "访问地址：  http://$(hostname -I 2>/dev/null | awk '{print $1}'):${CHATGPT2API_PORT}"
echo "            http://localhost:${CHATGPT2API_PORT}"
echo "管理员密钥：${CHATGPT2API_AUTH_KEY}"
echo "安装目录：  ${INSTALL_DIR}"
echo "日志查看：  cd ${INSTALL_DIR} && docker compose logs -f app"
echo "停机：      cd ${INSTALL_DIR} && docker compose down"
echo "升级镜像：  cd ${INSTALL_DIR} && docker compose pull && docker compose up -d"
echo "================================================================"
