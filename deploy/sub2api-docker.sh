#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Sub2API Docker Compose 一键部署（官方镜像版）
# 端口: 3002
# 镜像: weishaw/sub2api:latest（官方 Docker Hub）
# 组件: sub2api + postgres:15 + redis:7
# ============================================================

DEPLOY_DIR="$HOME/sub2api-docker"
SERVER_PORT=3002

echo "========================================"
echo "  Sub2API Docker 部署（官方镜像版）"
echo "  端口: ${SERVER_PORT}"
echo "  目录: ${DEPLOY_DIR}"
echo "========================================"

# ============================================================
# 第 1 步：清理 systemd 裸金属版本（如果存在）
# ============================================================
echo ""
echo "[步骤 1/5] 检查并清理 systemd 裸金属版本..."
if systemctl is-active --quiet sub2api 2>/dev/null; then
    echo "  -> 停止 sub2api systemd 服务..."
    sudo systemctl stop sub2api || true
    sudo systemctl disable sub2api || true
    echo "  -> 已停止并禁用 systemd 服务"
fi
if [ -f /etc/systemd/system/sub2api.service ] || [ -d /opt/sub2api ]; then
    echo "  -> 检测到旧安装，是否卸载？（可选，不卸载也不冲突）"
fi
echo "  -> OK"

# ============================================================
# 第 2 步：检查 Docker
# ============================================================
echo ""
echo "[步骤 2/5] 检查 Docker 环境..."
if ! command -v docker &>/dev/null; then
    echo "  -> 未检测到 Docker，正在安装..."
    curl -fsSL https://get.docker.com | sudo bash
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "  -> Docker 已安装，新组权限需要重新登录或执行: newgrp docker"
fi
if ! docker compose version &>/dev/null; then
    echo "[错误] Docker Compose 不可用"
    exit 1
fi
echo "  -> OK ($(docker -v), $(docker compose version))"

# ============================================================
# 第 3 步：准备部署目录和配置
# ============================================================
echo ""
echo "[步骤 3/5] 准备部署目录和配置..."
mkdir -p "${DEPLOY_DIR}"
cd "${DEPLOY_DIR}"

# 生成安全密钥
JWT_SECRET=$(openssl rand -hex 32)
TOTP_KEY=$(openssl rand -hex 32)
PG_PASSWORD=$(openssl rand -hex 16)
POSTGRES_USER="sub2api"
POSTGRES_DB="sub2api"

# 创建数据目录
mkdir -p data postgres_data redis_data

# 写 docker-compose.yml
cat > docker-compose.yml << 'YAML_EOF'
version: "3.8"

services:
  postgres:
    image: postgres:15-alpine
    container_name: sub2api-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    container_name: sub2api-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ./redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10

  sub2api:
    image: weishaw/sub2api:latest
    container_name: sub2api-app
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ulimits:
      nofile:
        soft: 100000
        hard: 100000
    ports:
      - "${BIND_HOST}:${SERVER_PORT}:8080"
    volumes:
      - ./data:/app/data
    environment:
      # Server
      BIND_HOST: 0.0.0.0
      SERVER_PORT: 8080
      SERVER_MODE: release
      # Auth
      JWT_SECRET: ${JWT_SECRET}
      TOTP_ENCRYPTION_KEY: ${TOTP_KEY}
      ADMIN_INITIAL_PASSWORD:
      # Database
      DATABASE_HOST: postgres
      DATABASE_PORT: 5432
      DATABASE_USER: ${POSTGRES_USER}
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
      DATABASE_NAME: ${POSTGRES_DB}
      DATABASE_SSL_MODE: disable
      # Redis
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD:
      REDIS_DB: 0
      REDIS_USE_TLS: "false"
      # Logging
      LOG_LEVEL: info
      LOG_FORMAT: json
      LOG_SERVICE_NAME: sub2api
      LOG_ENV: production
      LOG_CALLER: "true"
      LOG_STACKTRACE_LEVEL: error
      # Data
      DATA_DIR: /app/data
      ENABLE_PPROF: "false"
      ENABLE_METRICS: "false"
      MAXMIND_GEOIP_DB_PATH:
      GEOIP2_ACCOUNT_ID:
      GEOIP2_LICENSE_KEY:
      GIN_TRUSTED_PROXIES:
      CSRF_TRUSTED_ORIGINS:
      # Feature flags
      FEATURE_FLAG_EMAIL_TWO_FACTOR: "true"
      FEATURE_FLAG_SOCIAL_PROVIDERS: "true"
      FEATURE_FLAG_TICKET_SYSTEM: "true"
      FEATURE_FLAG_DISABLE_SIGNUP: "true"
      FEATURE_FLAG_DISABLE_PASSWORD_RESET: "false"
      FEATURE_FLAG_ENABLE_INVITE_ONLY: "false"
      FEATURE_FLAG_ENABLE_MAINTENANCE_MODE: "false"
      SESSION_INACTIVITY_TIMEOUT_MINUTES: 0
      SESSION_ABSOLUTE_TIMEOUT_MINUTES: 0
      DEFAULT_USER_TOKENS: 0
      DEFAULT_USER_LEVEL: 0
      DEFAULT_MAX_CONVERSATION_THREADS: 0
      DEFAULT_USER_EXPIRES_AT:
      ELASTIC_EMAIL_USERNAME:
      ELASTIC_EMAIL_API_KEY:
      EMAIL_FROM_NAME:
      EMAIL_FROM_ADDRESS:
      SMTP_HOST:
      SMTP_PORT: 587
      SMTP_USERNAME:
      SMTP_PASSWORD:
      SMTP_SECURITY: starttls
      OAUTH_GITHUB_CLIENT_ID:
      OAUTH_GITHUB_CLIENT_SECRET:
      OAUTH_GOOGLE_CLIENT_ID:
      OAUTH_GOOGLE_CLIENT_SECRET:
      OAUTH_DISCORD_CLIENT_ID:
      OAUTH_DISCORD_CLIENT_SECRET:
      TURNSTILE_SITE_KEY:
      TURNSTILE_SECRET_KEY:
      HCAPTCHA_SITE_KEY:
      HCAPTCHA_SECRET_KEY:
      RECAPTCHA_V2_SITE_KEY:
      RECAPTCHA_V2_SECRET_KEY:
      RECAPTCHA_V3_SITE_KEY:
      RECAPTCHA_V3_SECRET_KEY:
      ALIYUN_CAPTCHA_SCENE_ID:
      ALIYUN_CAPTCHA_IDENTITY:
      ALIYUN_CAPTCHA_SECRET:
      AUTHY_API_KEY:
      # Pricing / pay
      DEFAULT_CURRENCY: CNY
      STRIPE_SECRET_KEY:
      STRIPE_PUBLISHABLE_KEY:
      STRIPE_WEBHOOK_SECRET:
      ALIPAY_APP_ID:
      ALIPAY_PRIVATE_KEY:
      ALIPAY_PUBLIC_KEY:
      ALIPAY_NOTIFY_URL:
      ALIPAY_RETURN_URL:
      ALIPAY_APP_ID_MOBILE:
      ALIPAY_PRIVATE_KEY_MOBILE:
      ALIPAY_PUBLIC_KEY_MOBILE:
      ALIPAY_NOTIFY_URL_MOBILE:
      WXPAY_APP_ID:
      WXPAY_MCH_ID:
      WXPAY_API_V3_KEY:
      WXPAY_API_CERT_SERIAL:
      WXPAY_API_CERT_PATH:
      WXPAY_NOTIFY_URL:
      CUSTOM_THEME_PRIMARY_COLOR:
      CUSTOM_THEME_ACCENT_COLOR:
      CUSTOM_BRAND_NAME: Sub2API
      CUSTOM_BRAND_FAVICON_URL:
      CUSTOM_BRAND_LOGO_URL:
      CUSTOM_BRAND_HOME_URL:
      ENABLE_LEGAL_DOCS: "true"
      CUSTOM_FOOTER_HTML:
      CUSTOM_LOGIN_SIDEBAR_IMAGE_URL:
      CUSTOM_LOGIN_TITLE:
      CUSTOM_LOGIN_SUBTITLE:
      CUSTOM_LOGIN_BRAND_DISCLAIMER:
      CUSTOM_SIGNUP_BONUS_TOKENS: 0
      FEATURE_FLAG_DISABLE_FRONTEND_BILLING: "false"
      FEATURE_FLAG_DISABLE_FRONTEND_SUPPORT_TICKETS: "false"
      FEATURE_FLAG_DISABLE_FRONTEND_DOCS: "false"
      FEATURE_FLAG_DISABLE_FRONTEND_BLOG: "false"
      FEATURE_FLAG_DISABLE_FRONTEND_STATUS: "false"
      FEATURE_FLAG_DISABLE_USER_API_KEYS: "false"
      FEATURE_FLAG_DISABLE_USER_TEAM_MANAGEMENT: "false"
      FEATURE_FLAG_DISABLE_USER_BILLING_HISTORY: "false"
      FEATURE_FLAG_DISABLE_USER_INVITE_MANAGEMENT: "false"
      FEATURE_FLAG_DISABLE_USER_SECURITY_TOTP: "false"
      FEATURE_FLAG_DISABLE_USER_SECURITY_PASSKEY: "false"
      FEATURE_FLAG_DISABLE_USER_SECURITY_DEVICE: "false"
      # N8N & misc
      N8N_WEBHOOK_URL:
      AUTO_ACCOUNT_POOL_HEALTH_CHECK_INTERVAL: 30s
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

YAML_EOF

# 写 .env
cat > .env << ENV_EOF
# ============================================================
# Sub2API 环境配置
# 生成时间: $(date)
# ============================================================

# ---------- 服务器 ----------
BIND_HOST=0.0.0.0
SERVER_PORT=${SERVER_PORT}
SERVER_MODE=release

# ---------- 密钥 ----------
JWT_SECRET=${JWT_SECRET}
TOTP_ENCRYPTION_KEY=${TOTP_KEY}

# ---------- 数据库 ----------
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${PG_PASSWORD}

# ---------- 管理 ----------
# 留空则首次启动自动生成初始密码（日志中查看）
ADMIN_INITIAL_PASSWORD=

# ---------- 功能开关 ----------
# 禁用注册（推荐只管理员手动创建用户）
FEATURE_FLAG_DISABLE_SIGNUP=false

ENV_EOF

chmod 600 .env
echo "  -> OK (配置已生成)"

# ============================================================
# 第 4 步：拉取镜像并启动
# ============================================================
echo ""
echo "[步骤 4/5] 拉取镜像并启动..."
if [ "$(docker ps -aq -f name=sub2api-app 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "  -> 停止旧容器..."
    docker compose down 2>/dev/null || true
fi

echo "  -> 拉取 weishaw/sub2api:latest ..."
docker compose pull

echo "  -> 启动服务..."
docker compose up -d

# ============================================================
# 第 5 步：验证启动
# ============================================================
echo ""
echo "[步骤 5/5] 等待服务启动并验证..."
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    STATUS=$(docker inspect -f '{{.State.Health.Status}}' sub2api-postgres 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "healthy" ]; then
        break
    fi
    sleep 3
    WAITED=$((WAITED + 3))
    echo "  -> 等待 PG 健康... ${WAITED}s"
done

sleep 8

echo ""
echo "========================================"
echo "  🎉 部署完成！"
echo "========================================"
echo ""
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")
echo "  访问地址:   http://${SERVER_IP}:${SERVER_PORT}"
echo ""
echo "  容器状态:"
docker compose ps 2>/dev/null
echo ""
echo "  ---- 重要：首次登录密码 ----"
echo "  因为 ADMIN_INITIAL_PASSWORD 留空，首次启动会自动生成管理员密码。"
echo "  请查看日志获取："
echo "    cd ${DEPLOY_DIR} && docker compose logs sub2api 2>&1 | grep -i 'password\\|初始\\|admin'"
echo ""
echo "  常用命令:"
echo "    查看日志:  cd ${DEPLOY_DIR} && docker compose logs -f sub2api"
echo "    重启服务:  cd ${DEPLOY_DIR} && docker compose restart"
echo "    停止服务:  cd ${DEPLOY_DIR} && docker compose down"
echo "    更新版本:  cd ${DEPLOY_DIR} && docker compose pull && docker compose up -d"
echo "    重置密码:  cd ${DEPLOY_DIR} && docker compose exec sub2api /app/sub2api reset-admin-password"
echo ""
echo "  部署目录: ${DEPLOY_DIR}"
echo "  环境配置: ${DEPLOY_DIR}/.env（已 chmod 600）"
echo "  数据目录: ${DEPLOY_DIR}/postgres_data ${DEPLOY_DIR}/redis_data ${DEPLOY_DIR}/data"
echo ""
echo "========================================"
