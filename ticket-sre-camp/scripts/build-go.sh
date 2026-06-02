#!/usr/bin/env bash
# ============================================================
# build-go.sh — 编译所有 Go 微服务
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICES=("ticket-api" "ticket-db" "ticket-init" "ticket-settle")

echo "══════════════════════════════════════════════"
echo "🔨 Building Go services..."
echo "══════════════════════════════════════════════"

for svc in "${SERVICES[@]}"; do
    echo ""
    echo "── Building cmd/${svc} ──"
    cd "${ROOT_DIR}/cmd/${svc}"
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
