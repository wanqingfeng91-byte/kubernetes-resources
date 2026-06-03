#!/usr/bin/env bash
# ============================================================
# build-java.sh — 编译所有 Java 微服务 (Maven)
#
# 用途：遍历 Java 微服务目录，执行 mvn clean package 编译打包
#       输出 jar 到各服务的 target/ 目录
#
# 前置条件：已安装 Java JDK 21+ 和 Maven（运行 install-java.sh 或 setup-ubuntu.sh）
#
# 用法：
#   bash scripts/build-java.sh
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
