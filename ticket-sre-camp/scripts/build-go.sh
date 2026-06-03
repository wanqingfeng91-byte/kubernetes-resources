#!/usr/bin/env bash
# ============================================================
# build-go.sh — 编译所有 Go 微服务
#
# 用途：遍历 Go 微服务目录，交叉编译为 Linux amd64 二进制文件
#       输出到 ticket-sre-camp/bin/ 目录
#
# 前置条件：已安装 Go 工具链（运行 install-go.sh 或 setup-ubuntu.sh）
#
# 用法：
#   bash scripts/build-go.sh
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICES=("ticket-api" "ticket-db" "ticket-init" "ticket-settle")

echo "══════════════════════════════════════════════"
echo "🔨 Building Go services..."
echo "══════════════════════════════════════════════"

for svc in "${SERVICES[@]}"; do
    echo ""
    echo "── Building go/${svc} ──"
    cd "${ROOT_DIR}/go/${svc}"
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -ldflags="-s -w" -o "../../bin/${svc}-go" .
    echo "  ✅ bin/${svc}-go"
done

echo ""
echo "══════════════════════════════════════════════"
echo "✅ All Go services built successfully!"
echo "   Output: ${ROOT_DIR}/bin/"
echo "══════════════════════════════════════════════"
ls -lh "${ROOT_DIR}/bin/" 2>/dev/null || echo "(bin directory empty)"
