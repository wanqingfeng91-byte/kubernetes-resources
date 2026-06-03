#!/usr/bin/env bash
# ============================================================
# install-go.sh — 在 Ubuntu 上安装 Go 开发环境
#
# 用途：下载并安装指定版本的 Go 工具链到 /usr/local/go
#       自动配置 GOROOT/GOPATH/PATH 环境变量到 shell rc 文件
#
# 适用：Ubuntu 20.04 / 22.04 / 24.04
# 网络：海外直连，无需代理
#
# 用法：
#   bash scripts/install-go.sh                  # 安装默认版本
#   GO_VERSION=1.22.0 bash scripts/install-go.sh # 安装指定版本
# ============================================================
set -euo pipefail

GO_VERSION="${GO_VERSION:-1.22.0}"
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
    # 兼容 GNU/macOS 的版本提取：优先用 awk，不用 grep -P
    CURRENT=$(go version 2>/dev/null | awk '{match($3, /[0-9.]+/); print substr($3, RSTART, RLENGTH)}' || true)
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

# 选择可用的 SHA256 工具
if command -v sha256sum &>/dev/null; then
    SHA256_CMD="sha256sum"
elif command -v shasum &>/dev/null; then
    SHA256_CMD="shasum -a 256"
else
    SHA256_CMD=""
fi

if [[ -z "$SHA256_CMD" ]]; then
    echo "⚠️  No sha256sum/shasum found, skipping checksum verification"
else
    # 下载官方校验文件（可能包含裸 hash 或 HTML 重定向）
    curl -fsSL "${GO_URL}.sha256" -o "${GO_TAR}.sha256"

    # 从下载的文件中提取 64 位十六进制哈希值
    EXPECTED_HASH=$(grep -oE '[0-9a-fA-F]{64}' "${GO_TAR}.sha256" | head -1 || true)
    rm -f "${GO_TAR}.sha256"

    if [[ -z "$EXPECTED_HASH" ]]; then
        echo "⚠️  Could not extract checksum from remote, skipping verification"
    else
        ACTUAL_HASH=$($SHA256_CMD "$GO_TAR" | awk '{print $1}')
        if [[ "$EXPECTED_HASH" == "$ACTUAL_HASH" ]]; then
            echo "  ✅ Checksum verified"
        else
            echo "  ❌ Checksum mismatch!"
            echo "     Expected: ${EXPECTED_HASH}"
            echo "     Got:      ${ACTUAL_HASH}"
            rm -f "$GO_TAR"
            exit 1
        fi
    fi
fi

# ── 安装 ────────────────────────────────────────
echo ""
echo "[3/3] 📦 Installing to ${INSTALL_DIR}/go..."

if [[ -d "${INSTALL_DIR}/go" ]]; then
    echo "  Removing existing installation..."
    sudo rm -rf "${INSTALL_DIR}/go"
fi

sudo tar -C "${INSTALL_DIR}" -xzf "/tmp/${GO_TAR}"
rm -f "/tmp/${GO_TAR}"

# ── 配置环境变量 ────────────────────────────────

configure_shell() {
    local profile="$1"

    if [[ -f "$profile" ]]; then
        if grep -q '/usr/local/go/bin' "$profile" 2>/dev/null; then
            echo "  Already configured in $profile"
            return
        fi
    fi

    # 如果文件不存在，创建它
    if [[ ! -f "$profile" ]]; then
        return
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

for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]]; then
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
