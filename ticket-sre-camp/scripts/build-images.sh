#!/usr/bin/env bash
# ============================================================
# build-images.sh — 构建所有微服务 Docker 镜像
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${DOCKER_REGISTRY:-ticket-sre}"
TAG="${IMAGE_TAG:-latest}"

# 服务列表: "服务名:语言:上下文目录"
SERVICES=(
    "ticket-api:go:${ROOT_DIR}/cmd/ticket-api"
    "ticket-db:go:${ROOT_DIR}/cmd/ticket-db"
    "ticket-init:go:${ROOT_DIR}/cmd/ticket-init"
    "ticket-settle:go:${ROOT_DIR}/cmd/ticket-settle"
    "ticket-api:java:${ROOT_DIR}/java/ticket-api"
    "ticket-db:java:${ROOT_DIR}/java/ticket-db"
    "ticket-init:java:${ROOT_DIR}/java/ticket-init"
    "ticket-settle:java:${ROOT_DIR}/java/ticket-settle"
)

echo "══════════════════════════════════════════════"
echo "🐳 Building Docker images..."
echo "   Registry: ${REGISTRY}"
echo "   Tag:      ${TAG}"
echo "══════════════════════════════════════════════"

for entry in "${SERVICES[@]}"; do
    IFS=':' read -r svc lang ctx <<< "$entry"
    img_name="${REGISTRY}/${svc}-${lang}:${TAG}"

    echo ""
    echo "── Building ${img_name} ──"
    docker build -t "$img_name" -f "${ctx}/Dockerfile" "$ctx"
    echo "  ✅ ${img_name}"
done

echo ""
echo "══════════════════════════════════════════════"
echo "✅ All Docker images built successfully!"
echo ""
echo "Images:"
docker images "${REGISTRY}/*:${TAG}" 2>/dev/null
echo "══════════════════════════════════════════════"
