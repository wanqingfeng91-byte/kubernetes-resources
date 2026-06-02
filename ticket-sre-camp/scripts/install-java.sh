#!/usr/bin/env bash
# ============================================================
# install-java.sh — 在 Ubuntu 上安装 Java 25 + Maven
# 适用：Ubuntu 20.04 / 22.04 / 24.04
# 网络：海外直连，无需代理
# JDK：Eclipse Temurin (Adoptium) — 最广泛使用的 OpenJDK 发行版
# ============================================================
set -euo pipefail

JAVA_VERSION="${JAVA_VERSION:-25}"
MAVEN_VERSION="${MAVEN_VERSION:-3.9.9}"

echo "══════════════════════════════════════════════"
echo "🔧 Installing Java ${JAVA_VERSION} + Maven ${MAVEN_VERSION}"
echo "   JDK: Eclipse Temurin (Adoptium)"
echo "══════════════════════════════════════════════"

# ── 检测系统架构 ────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ADOPTIUM_ARCH="x64" ;;
    aarch64) ADOPTIUM_ARCH="aarch64" ;;
    *)       echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "   Architecture: ${ARCH} → ${ADOPTIUM_ARCH}"
echo ""

# ═══════════════════════════════════════════════
# 安装 Java (Eclipse Temurin)
# ═══════════════════════════════════════════════

install_java() {
    echo "── Installing JDK ${JAVA_VERSION} ──"

    # 检查是否已安装
    if command -v java &>/dev/null; then
        CURRENT=$(java -version 2>&1 | head -1 | grep -oP '\d+' | head -1 || true)
        if [[ "$CURRENT" == "$JAVA_VERSION" ]]; then
            echo "✅ Java ${JAVA_VERSION} is already installed"
            java -version 2>&1 | head -3
            return
        fi
    fi

    # 方法 1: 通过 Adoptium APT 仓库 (推荐，可自动更新)
    echo "[1/2] 📥 Adding Adoptium APT repository..."

    # 安装依赖
    sudo apt-get update -qq
    sudo apt-get install -y -qq wget apt-transport-https gpg 2>/dev/null

    # 添加 Eclipse Adoptium GPG key
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public |
        sudo gpg --dearmor -o /usr/share/keyrings/adoptium.gpg

    # 添加 APT 源
    echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" |
        sudo tee /etc/apt/sources.list.d/adoptium.list > /dev/null

    echo "[2/2] 📦 Installing Temurin JDK ${JAVA_VERSION}..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq "temurin-${JAVA_VERSION}-jdk"

    echo ""
    echo "✅ JDK installed:"
    java -version 2>&1 | head -3
}

# ═══════════════════════════════════════════════
# 安装 Maven
# ═══════════════════════════════════════════════

install_maven() {
    echo ""
    echo "── Installing Maven ${MAVEN_VERSION} ──"

    # 检查是否已安装
    if command -v mvn &>/dev/null; then
        CURRENT=$(mvn -version 2>&1 | head -1 | awk '{print $3}' || true)
        if [[ "$CURRENT" == "$MAVEN_VERSION" ]]; then
            echo "✅ Maven ${MAVEN_VERSION} is already installed"
            mvn -version | head -1
            return
        fi
    fi

    MAVEN_URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    MAVEN_TAR="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    MAVEN_INSTALL_DIR="/opt"

    echo "[1/3] 📥 Downloading Maven ${MAVEN_VERSION}..."
    cd /tmp
    if [[ ! -f "$MAVEN_TAR" ]]; then
        wget -q --show-progress "$MAVEN_URL" || curl -fsSLO "$MAVEN_URL"
    fi

    echo "[2/3] 📦 Extracting to ${MAVEN_INSTALL_DIR}..."
    if [[ -d "${MAVEN_INSTALL_DIR}/apache-maven-${MAVEN_VERSION}" ]]; then
        sudo rm -rf "${MAVEN_INSTALL_DIR}/apache-maven-${MAVEN_VERSION}"
    fi
    sudo tar -C "$MAVEN_INSTALL_DIR" -xzf "/tmp/$MAVEN_TAR"
    rm -f "/tmp/$MAVEN_TAR"

    # 创建软链接
    sudo ln -sf "${MAVEN_INSTALL_DIR}/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn

    echo "[3/3] ⚙️  Configuring Maven environment..."
    # 在 profile 中添加 MAVEN_HOME
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]]; then
            if ! grep -q 'MAVEN_HOME' "$rc" 2>/dev/null; then
                echo "" >> "$rc"
                echo "# Maven (added by install-java.sh)" >> "$rc"
                echo "export MAVEN_HOME=${MAVEN_INSTALL_DIR}/apache-maven-${MAVEN_VERSION}" >> "$rc"
                echo 'export PATH=$PATH:$MAVEN_HOME/bin' >> "$rc"
            fi
        fi
    done

    echo ""
    echo "✅ Maven installed:"
    /usr/local/bin/mvn -version | head -2
    export MAVEN_HOME="${MAVEN_INSTALL_DIR}/apache-maven-${MAVEN_VERSION}"
    export PATH="$PATH:$MAVEN_HOME/bin"
}

# ═══════════════════════════════════════════════
# 安装 Gradle (可选)
# ═══════════════════════════════════════════════

install_gradle() {
    echo ""
    read -rp "── Install Gradle as well? (y/N): " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        echo "   Skipping Gradle"
        return
    fi
    echo "   Installing Gradle via SDKMAN..."
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk install gradle
    echo "   ✅ Gradle installed"
}

# ═══════════════════════════════════════════════
# 执行安装
# ═══════════════════════════════════════════════

install_java
install_maven

# 环境已配好，直接验证
echo ""
echo "══════════════════════════════════════════════"
echo "✅ Java ${JAVA_VERSION} + Maven ${MAVEN_VERSION} installation complete!"
echo ""
echo "   Open a new terminal or run:"
echo "     source ~/.bashrc"
echo ""
echo "   Verify:"
echo "     java -version"
echo "     javac -version"
echo "     mvn -version"
echo "══════════════════════════════════════════════"
