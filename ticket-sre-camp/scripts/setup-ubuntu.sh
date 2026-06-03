#!/usr/bin/env bash
# ============================================================
# setup-ubuntu.sh — Ubuntu 开发环境一键安装
#
# 用途：串联调用 install-go.sh、install-java.sh、install-k8s-tools.sh
#       一键完成 Go + Java + Maven + Docker + kubectl + Helm + KinD 安装
#
# 适用：Ubuntu 20.04 / 22.04 / 24.04
# 网络：海外直连，无需代理
#
# 用法：
#   bash scripts/setup-ubuntu.sh                # 全部安装
#   bash scripts/setup-ubuntu.sh --skip-docker   # 跳过 Docker / kubectl
#   bash scripts/setup-ubuntu.sh --only-go       # 仅安装 Go
#   bash scripts/setup-ubuntu.sh --only-java     # 仅安装 Java + Maven
#   bash scripts/setup-ubuntu.sh --only-k8s      # 仅安装 Docker / kubectl
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "══════════════════════════════════════════════"
echo "🛠️  ticket-sre Ubuntu 开发环境一键安装"
echo "══════════════════════════════════════════════"
echo ""

# 检测 Ubuntu 版本（兼容无 lsb_release 的最小化安装）
if command -v lsb_release &>/dev/null; then
    echo "   Ubuntu $(lsb_release -rs) ($(uname -m))"
elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "   ${PRETTY_NAME:-$NAME $VERSION_ID} ($(uname -m))"
else
    echo "   Linux ($(uname -m))"
fi
echo ""

# ── 参数解析 ────────────────────────────────────
INSTALL_GO=true
INSTALL_JAVA=true
INSTALL_K8S=true

for arg in "$@"; do
    case "$arg" in
        --skip-go)   INSTALL_GO=false ;;
        --skip-java) INSTALL_JAVA=false ;;
        --skip-docker) INSTALL_K8S=false ;;
        --only-go)   INSTALL_JAVA=false; INSTALL_K8S=false ;;
        --only-java) INSTALL_GO=false; INSTALL_K8S=false ;;
        --only-k8s)  INSTALL_GO=false; INSTALL_JAVA=false ;;
        -h|--help)
            echo "Usage: bash setup-ubuntu.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)        Install everything (Go + Java + Docker + kubectl)"
            echo "  --skip-go     Skip Go installation"
            echo "  --skip-java   Skip Java + Maven installation"
            echo "  --skip-docker Skip Docker + kubectl installation"
            echo "  --only-go     Only install Go"
            echo "  --only-java   Only install Java + Maven"
            echo "  --only-k8s    Only install Docker + kubectl"
            echo "  -h, --help    Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ── 系统更新 ────────────────────────────────────
echo "[0] 📦 Updating system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq curl wget tar gzip 2>/dev/null
echo ""

# ── 安装 Go ─────────────────────────────────────
if $INSTALL_GO; then
    echo "╔════════════════════════════════════════════╗"
    echo "║  1/3: Go                                  ║"
    echo "╚════════════════════════════════════════════╝"
    bash "${SCRIPT_DIR}/install-go.sh"
    # 使当前 shell 可找到 go
    export GOROOT=/usr/local/go
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
fi

# ── 安装 Java + Maven ──────────────────────────
if $INSTALL_JAVA; then
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  2/3: Java + Maven                        ║"
    echo "╚════════════════════════════════════════════╝"
    bash "${SCRIPT_DIR}/install-java.sh"
fi

# ── 安装 Docker + kubectl ──────────────────────
if $INSTALL_K8S; then
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  3/3: Docker + kubectl + Helm + KinD      ║"
    echo "╚════════════════════════════════════════════╝"
    bash "${SCRIPT_DIR}/install-k8s-tools.sh"
fi

# ═══════════════════════════════════════════════
# 汇总
# ═══════════════════════════════════════════════

echo ""
echo "══════════════════════════════════════════════"
echo "🎉 环境安装完成！"
echo "══════════════════════════════════════════════"
echo ""

# 刷新 PATH
export GOROOT=/usr/local/go 2>/dev/null || true
export GOPATH=$HOME/go 2>/dev/null || true
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin 2>/dev/null || true

echo "   ┌─────────────────────────────────────────┐"
echo "   │ Installed Versions                       │"
echo "   ├─────────────────────────────────────────┤"

printf "   │ Go:      %-28s │\n" "$(go version 2>/dev/null || echo 'not found')"
printf "   │ Java:    %-28s │\n" "$(java -version 2>&1 | head -1 || echo 'not found')"
printf "   │ Maven:   %-28s │\n" "$(mvn -version 2>/dev/null | head -1 | awk '{print $3}' || echo 'not found')"
printf "   │ Docker:  %-28s │\n" "$(docker --version 2>/dev/null || echo 'not found')"
printf "   │ kubectl: %-28s │\n" "$(kubectl version --client 2>/dev/null | head -1 || echo 'not found')"
printf "   │ Helm:    %-28s │\n" "$(helm version --short 2>/dev/null | head -1 || echo 'not found')"
printf "   │ KinD:    %-28s │\n" "$(kind version 2>/dev/null | head -1 || echo 'not found')"
echo "   └─────────────────────────────────────────┘"

echo ""
echo "   ── Next steps ──"
echo ""
echo "   1. Reload shell environment:"
echo "      source ~/.bashrc"
echo "      # or open a new terminal"
echo ""
echo "   2. Create a local K8s cluster (optional):"
echo "      kind create cluster --name ticket-sre"
echo ""
echo "   3. Build and deploy:"
echo "      bash scripts/build-go.sh"
echo "      bash scripts/build-java.sh"
echo "      bash scripts/build-images.sh"
echo "      bash scripts/deploy.sh"
echo ""
echo "   4. Run tests:"
echo "      bash scripts/test.sh"
echo ""
echo "══════════════════════════════════════════════"
