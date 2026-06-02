#!/usr/bin/env bash
# ============================================================
# install-k8s-tools.sh — 在 Ubuntu 上安装 Docker + kubectl + 辅助工具
# 适用：Ubuntu 20.04 / 22.04 / 24.04
# 网络：海外直连，无需代理
# ============================================================
set -euo pipefail

KUBECTL_VERSION="${KUBECTL_VERSION:-stable}"
HELM_VERSION="${HELM_VERSION:-3.17.0}"
KIND_VERSION="${KIND_VERSION:-0.27.0}"

echo "══════════════════════════════════════════════"
echo "🔧 Installing Kubernetes toolchain on Ubuntu..."
echo "══════════════════════════════════════════════"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  DOCKER_ARCH="amd64"; K8S_ARCH="amd64" ;;
    aarch64) DOCKER_ARCH="arm64"; K8S_ARCH="arm64" ;;
    *)       echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ═══════════════════════════════════════════════
# 1. Docker
# ═══════════════════════════════════════════════

install_docker() {
    echo ""
    echo "── [1/4] Installing Docker ──"

    if command -v docker &>/dev/null; then
        echo "✅ Docker already installed:"
        docker --version
        return
    fi

    echo "[1/3] 📥 Adding Docker APT repository..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl 2>/dev/null

    # Docker GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Docker APT 源
    echo "deb [arch=${DOCKER_ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "[2/3] 📦 Installing Docker Engine + Docker Compose..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin 2>/dev/null

    echo "[3/3] ⚙️  Adding current user to docker group..."
    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"

    echo ""
    echo "✅ Docker installed:"
    docker --version
    docker compose version 2>/dev/null || true
    echo ""
    echo "   ⚠️  Log out and back in for docker group to take effect"
}

# ═══════════════════════════════════════════════
# 2. kubectl
# ═══════════════════════════════════════════════

install_kubectl() {
    echo ""
    echo "── [2/4] Installing kubectl ──"

    if command -v kubectl &>/dev/null; then
        echo "✅ kubectl already installed:"
        kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1
        return
    fi

    echo "[1/2] 📥 Downloading kubectl (${KUBECTL_VERSION})..."
    # 使用 Google 官方源（海外直连）
    if [[ "$KUBECTL_VERSION" == "stable" ]]; then
        curl -fsSLO "https://dl.k8s.io/release/stable/bin/linux/${K8S_ARCH}/kubectl"
    else
        curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K8S_ARCH}/kubectl"
    fi

    # 校验
    curl -fsSLO "https://dl.k8s.io/release/stable/bin/linux/${K8S_ARCH}/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    rm -f kubectl.sha256

    echo "[2/2] 📦 Installing kubectl..."
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl

    # 启用 bash 补全
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q 'kubectl completion bash' "$HOME/.bashrc" 2>/dev/null; then
            echo 'source <(kubectl completion bash)' >> "$HOME/.bashrc"
        fi
    fi

    echo ""
    echo "✅ kubectl installed:"
    kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1
}

# ═══════════════════════════════════════════════
# 3. Helm (可选)
# ═══════════════════════════════════════════════

install_helm() {
    echo ""
    echo "── [3/4] Installing Helm ──"

    if command -v helm &>/dev/null; then
        echo "✅ Helm already installed: $(helm version --short 2>/dev/null | head -1)"
        return
    fi

    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    echo ""
    echo "✅ Helm installed:"
    helm version --short
}

# ═══════════════════════════════════════════════
# 4. KinD (可选，本地 K8s 集群)
# ═══════════════════════════════════════════════

install_kind() {
    echo ""
    echo "── [4/4] Installing KinD (Kubernetes in Docker) ──"

    if command -v kind &>/dev/null; then
        echo "✅ KinD already installed: $(kind version 2>/dev/null | head -1)"
        return
    fi

    curl -fsSLo ./kind "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-${K8S_ARCH}"
    sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
    rm -f kind

    echo ""
    echo "✅ KinD installed:"
    kind version
}

# ═══════════════════════════════════════════════
# 5. k9s (可选，终端 K8s UI)
# ═══════════════════════════════════════════════

install_k9s() {
    echo ""
    read -rp "── Install k9s (terminal K8s dashboard)? (y/N): " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        echo "   Skipping k9s"
        return
    fi

    local k9s_url="https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${DOCKER_ARCH}.deb"
    local k9s_deb="/tmp/k9s.deb"
    curl -fsSLo "$k9s_deb" "$k9s_url"
    sudo dpkg -i "$k9s_deb"
    rm -f "$k9s_deb"
    echo "   ✅ k9s installed"
}

# ═══════════════════════════════════════════════
# 执行安装
# ═══════════════════════════════════════════════

install_docker
install_kubectl
install_helm
install_kind

echo ""
echo "══════════════════════════════════════════════"
echo "✅ K8s toolchain installation complete!"
echo ""
echo "   Installed versions:"
docker --version     || echo "   ⚠️  docker: not found"
kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1
helm version --short 2>/dev/null || echo "   ⚠️  helm: not found"
kind version 2>/dev/null | head -1 || echo "   ⚠️  kind: not found"
echo ""
echo "   ⚠️  Log out and log back in (or: newgrp docker)"
echo "      for docker group membership to take effect"
echo ""
echo "   ── Quick start a local K8s cluster ──"
echo "   kind create cluster --name ticket-sre"
echo ""
echo "   ── Verify cluster ──"
echo "   kubectl cluster-info"
echo "   kubectl get nodes"
echo "══════════════════════════════════════════════"
