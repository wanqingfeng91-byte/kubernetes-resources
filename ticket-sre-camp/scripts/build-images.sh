#!/usr/bin/env bash
# ============================================================
# build-images.sh — 构建所有微服务 Docker 镜像
#
# 用途：为 Go 和 Java 版本的每个微服务构建 Docker 镜像
#       镜像命名: ${DOCKER_REGISTRY}/${服务名}-${语言}:${IMAGE_TAG}
#
# 前置条件：已安装 Docker（运行 install-k8s-tools.sh 或 setup-ubuntu.sh）
#          已编译 Go/Java 产物（运行 build-go.sh / build-java.sh）
#
# 用法：
#   bash scripts/build-images.sh
#   DOCKER_REGISTRY=myreg IMAGE_TAG=v1.0 bash scripts/build-images.sh
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${DOCKER_REGISTRY:-ticket-sre}"
TAG="${IMAGE_TAG:-latest}"

# 服务列表: "服务名:语言:上下文目录"
SERVICES=(
    "ticket-api:go:${ROOT_DIR}/go/ticket-api"
    "ticket-db:go:${ROOT_DIR}/go/ticket-db"
    "ticket-init:go:${ROOT_DIR}/go/ticket-init"
    "ticket-settle:go:${ROOT_DIR}/go/ticket-settle"
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
