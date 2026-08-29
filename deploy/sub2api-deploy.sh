#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Sub2API 一键部署脚本
# 端口: 3002 (8080 被占用)
# 部署方式: Docker Compose (自带 PostgreSQL + Redis)
# ============================================================

DEPLOY_DIR="$HOME/sub2api-deploy"
SERVER_PORT=3002

echo "========================================"
echo "  Sub2API Docker 部署脚本"
echo "  端口: ${SERVER_PORT}"
echo "  目录: ${DEPLOY_DIR}"
echo "========================================"

# 1. 检查 Docker
if ! command -v docker &>/dev/null; then
    echo "[错误] 未安装 Docker，正在安装..."
    curl -fsSL https://get.docker.com | sudo bash
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "[提示] Docker 已安装，需要重新登录后 docker 组才会生效"
    echo "       如果提示权限不足，请执行: newgrp docker 或重新登录"
fi

# 2. 检查 Docker Compose
if ! docker compose version &>/dev/null; then
    echo "[错误] Docker Compose 不可用，请确保 Docker 版本 >= 20.10 且包含 compose 插件"
    exit 1
fi

echo "[OK] Docker 环境检查通过"

# 3. 创建部署目录
mkdir -p "${DEPLOY_DIR}"
cd "${DEPLOY_DIR}"
echo "[OK] 部署目录: $(pwd)"

# 4. 生成安全密钥
JWT_SECRET=$(openssl rand -hex 32)
TOTP_KEY=$(openssl rand -hex 32)
PG_PASSWORD=$(openssl rand -hex 16)

echo "[OK] 已生成安全密钥"

# 5. 生成 docker-compose.yml
cat > docker-compose.yml << 'COMPOSE_EOF'
version: "3.8"

services:
  postgres:
    image: postgres:15-alpine
    container_name: sub2api-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: sub2api
      POSTGRES_USER: sub2api
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sub2api"]
      interval: 10s
      timeout: 5s
      retries: 5

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
      retries: 5

  sub2api:
    image: ghcr.io/wei-shaw/sub2api:latest
    container_name: sub2api-app
    restart: unless-stopped
    ports:
      - "${SERVER_PORT}:8080"
    environment:
      DATABASE_HOST: postgres
      DATABASE_PORT: 5432
      DATABASE_USER: sub2api
      DATABASE_PASSWORD: ${POSTGRES_PASSWORD}
      DATABASE_NAME: sub2api
      REDIS_HOST: redis
      REDIS_PORT: 6379
      JWT_SECRET: ${JWT_SECRET}
      TOTP_ENCRYPTION_KEY: ${TOTP_KEY}
      SERVER_PORT: 8080
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - ./data:/app/data

COMPOSE_EOF

echo "[OK] docker-compose.yml 已生成"

# 6. 生成 .env
cat > .env << ENV_EOF
POSTGRES_PASSWORD=${PG_PASSWORD}
JWT_SECRET=${JWT_SECRET}
TOTP_ENCRYPTION_KEY=${TOTP_KEY}
SERVER_PORT=${SERVER_PORT}
ENV_EOF

echo "[OK] .env 已生成"

# 7. 创建数据目录
mkdir -p data postgres_data redis_data

# 8. 停止旧容器（如果有）
echo "[步骤] 停止旧容器..."
docker compose down 2>/dev/null || true

# 9. 拉取镜像并启动
echo "[步骤] 拉取镜像..."
docker compose pull

echo "[步骤] 启动服务..."
docker compose up -d

# 10. 等待启动
echo "[步骤] 等待服务启动..."
sleep 8

# 11. 检查状态
echo ""
echo "========================================"
echo "  部署完成！"
echo "========================================"
echo ""
echo "  访问地址:  http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):${SERVER_PORT}"
echo "  首次访问会引导创建管理员账号"
echo ""
echo "  容器状态:"
docker compose ps
echo ""
echo "  安全凭证已保存在 ${DEPLOY_DIR}/.env"
echo "  请妥善保管，包含数据库密码和 JWT 密钥"
echo ""
echo "  常用命令:"
echo "    查看日志:   cd ${DEPLOY_DIR} && docker compose logs -f sub2api"
echo "    重启服务:   cd ${DEPLOY_DIR} && docker compose restart"
echo "    停止服务:   cd ${DEPLOY_DIR} && docker compose down"
echo "    更新版本:   cd ${DEPLOY_DIR} && docker compose pull && docker compose up -d"
echo ""
