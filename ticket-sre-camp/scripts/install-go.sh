#!/usr/bin/env bash
# ============================================================
# install-go.sh — 在 Ubuntu 上安装 Go 开发环境
# 适用：Ubuntu 20.04 / 22.04 / 24.04
# 网络：海外直连，无需代理
# ============================================================
set -euo pipefail

GO_VERSION="${GO_VERSION:-1.25.1}"
GO_OS="linux"
GO_ARCH="amd64"
GO_TAR="go${GO_VERSION}.${GO_OS}-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"
INSTALL_DIR="/usr/local"

echo "══════════════════════════════════════════════"
echo "🔧 Installing Go ${GO_VERSION} on Ubuntu..."
echo "══════════════════════════════════════════════"

# ── 检查是否已安装相同版本 ──────────────────────
if command -v go &>/dev/null; then
    CURRENT=$(go version | grep -oP 'go\K[0-9.]+' || true)
    if [[ "$CURRENT" == "$GO_VERSION" ]]; then
        echo "✅ Go ${GO_VERSION} is already installed"
        go version
        exit 0
    fi
    echo "⚠️  Existing Go ${CURRENT} found, will upgrade to ${GO_VERSION}"
fi

# ── 下载 ────────────────────────────────────────
echo ""
echo "[1/3] 📥 Downloading Go ${GO_VERSION}..."
cd /tmp
if [[ -f "$GO_TAR" ]]; then
    echo "  File already exists, skipping download"
else
    curl -fsSLO "$GO_URL"
fi
echo "  ✅ Download complete ($(du -h "$GO_TAR" | cut -f1))"

# ── 校验 SHA256 ────────────────────────────────
echo ""
echo "[2/3] 🔐 Verifying checksum..."
# Go 官方提供 sha256 文件，下载并校验
curl -fsSL "${GO_URL}.sha256" -o "${GO_TAR}.sha256"
cd /tmp
sha256sum -c "${GO_TAR}.sha256"
rm -f "${GO_TAR}.sha256"
echo "  ✅ Checksum verified"

# ── 安装 ────────────────────────────────────────
echo ""
echo "[3/3] 📦 Installing to ${INSTALL_DIR}/go..."

# 如果已存在旧版本，先删除
if [[ -d "${INSTALL_DIR}/go" ]]; then
    echo "  Removing existing installation..."
    sudo rm -rf "${INSTALL_DIR}/go"
fi

sudo tar -C "${INSTALL_DIR}" -xzf "/tmp/${GO_TAR}"
rm -f "/tmp/${GO_TAR}"

# ── 配置环境变量 ────────────────────────────────
configure_shell() {
    local profile="$1"
    local go_path_added=false

    if [[ -f "$profile" ]]; then
        # 检查是否已配置
        if grep -q '/usr/local/go/bin' "$profile" 2>/dev/null; then
            echo "  Already configured in $profile"
            return
        fi
    fi

    echo "" >> "$profile"
    echo "# Go environment (added by install-go.sh)" >> "$profile"
    echo 'export GOROOT=/usr/local/go' >> "$profile"
    echo 'export GOPATH=$HOME/go' >> "$profile"
    echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin' >> "$profile"
    echo "  ✅ Configured in $profile"
}

echo ""
echo "⚙️  Configuring environment variables..."

# 根据常用 shell 配置
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]] || [[ "$rc" == "$HOME/.bashrc" ]]; then
        configure_shell "$rc"
    fi
done

# 创建 GOPATH 目录
mkdir -p "$HOME/go/bin" "$HOME/go/pkg" "$HOME/go/src"

echo ""
echo "══════════════════════════════════════════════"
echo "✅ Go ${GO_VERSION} installation complete!"
echo ""
echo "   Open a new terminal or run:"
echo "     source ~/.bashrc"
echo ""
echo "   Verify:"
echo "     go version"
echo "     go env GOPATH"
echo "══════════════════════════════════════════════"

# 在当前 shell 生效
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
go version
