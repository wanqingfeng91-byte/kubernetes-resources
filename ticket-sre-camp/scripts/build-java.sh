#!/usr/bin/env bash
# ============================================================
# build-java.sh — 编译所有 Java 微服务 (Maven)
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICES=("ticket-api" "ticket-db" "ticket-init" "ticket-settle")

echo "══════════════════════════════════════════════"
echo "🔨 Building Java services (Maven)..."
echo "══════════════════════════════════════════════"

for svc in "${SERVICES[@]}"; do
    echo ""
    echo "── Building java/${svc} ──"
    cd "${ROOT_DIR}/java/${svc}"
    mvn clean package -DskipTests -q
    echo "  ✅ java/${svc}/target/${svc}-1.0.0.jar"
done

echo ""
echo "══════════════════════════════════════════════"
echo "✅ All Java services built successfully!"
echo "══════════════════════════════════════════════"
