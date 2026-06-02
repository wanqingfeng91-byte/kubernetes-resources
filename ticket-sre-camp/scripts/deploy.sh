#!/usr/bin/env bash
# ============================================================
# deploy.sh — 部署所有微服务到 Kubernetes
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
K8S_DIR="${ROOT_DIR}/k8s"

echo "══════════════════════════════════════════════"
echo "🚀 Deploying ticket-sre to Kubernetes..."
echo "══════════════════════════════════════════════"

# 切换到 k8s 目录 (kustomize 需要)
cd "$K8S_DIR"

# 步骤1: 创建命名空间 (如果不存在)
echo ""
echo "[1/3] 📦 Creating namespace..."
kubectl apply -f 00-namespace.yaml

# 步骤2: 部署 ConfigMap
echo ""
echo "[2/3] ⚙️  Applying ConfigMap..."
kubectl apply -f 01-configmap.yaml

# 步骤3: 使用 kustomize 部署所有资源
echo ""
echo "[3/3] 🚀 Deploying all resources with Kustomize..."
kubectl apply -k .

echo ""
echo "══════════════════════════════════════════════"
echo "⏳ Waiting for resources to be ready..."
echo "══════════════════════════════════════════════"

# 等待 Deployment 就绪
echo ""
echo "── Waiting for ticket-api Deployment..."
kubectl rollout status deployment/ticket-api -n ticket-sre --timeout=120s || true

# 等待 StatefulSet 就绪
echo ""
echo "── Waiting for ticket-db StatefulSet..."
kubectl rollout status statefulset/ticket-db -n ticket-sre --timeout=120s || true

# 等待 Job 完成
echo ""
echo "── Waiting for ticket-init Job..."
kubectl wait --for=condition=complete job/ticket-init -n ticket-sre --timeout=120s || true

echo ""
echo "══════════════════════════════════════════════"
echo "✅ Deployment complete!"
echo ""
echo "📋 Resource Status:"
echo "══════════════════════════════════════════════"
kubectl get all -n ticket-sre
echo ""
echo "📊 PVC Status:"
kubectl get pvc -n ticket-sre
echo ""
echo "💡 Quick test commands:"
echo "   kubectl port-forward svc/ticket-api-svc 8080:80 -n ticket-sre"
echo "   curl http://localhost:8080/buy -X POST"
echo "   curl http://localhost:8080/healthz"
echo "══════════════════════════════════════════════"
