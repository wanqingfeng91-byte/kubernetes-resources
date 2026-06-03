#!/usr/bin/env bash
# ============================================================
# verify-k8s.sh — 验证 K8s 资源状态（不部署，仅检查）
#
# 用途：对 k8s/ 目录下的 YAML 做 dry-run 校验、kustomize build 校验
#       并查询集群中已部署资源的实际状态
#
# 前置条件：kubectl 已配置并可访问目标集群
#
# 用法：
#   bash scripts/verify-k8s.sh
# ============================================================
set -euo pipefail

NAMESPACE="ticket-sre"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "══════════════════════════════════════════════"
echo "🔍 Verifying Kubernetes Resources"
echo "   Namespace: ${NAMESPACE}"
echo "══════════════════════════════════════════════"

echo ""
echo "── YAML Validation (kubectl --dry-run) ──"
for f in "${ROOT_DIR}/k8s"/*.yaml; do
    name=$(basename "$f")
    if [[ "$name" == "kustomization.yaml" ]]; then continue; fi
    if kubectl apply -f "$f" --dry-run=client -n "$NAMESPACE" &>/dev/null; then
        echo "  ✅ ${name}"
    else
        echo "  ❌ ${name}"
    fi
done

echo ""
echo "── Kustomize Build ──"
if kubectl kustomize "${ROOT_DIR}/k8s" &>/dev/null; then
    echo "  ✅ kustomization.yaml is valid"
else
    echo "  ❌ kustomization.yaml has errors"
fi

echo ""
echo "── Cluster Resources ──"
echo "Deployments:"
kubectl get deploy -n "$NAMESPACE" 2>/dev/null || echo "  (namespace not found)"
echo ""
echo "StatefulSets:"
kubectl get sts -n "$NAMESPACE" 2>/dev/null || echo "  (none)"
echo ""
echo "Jobs:"
kubectl get job -n "$NAMESPACE" 2>/dev/null || echo "  (none)"
echo ""
echo "CronJobs:"
kubectl get cronjob -n "$NAMESPACE" 2>/dev/null || echo "  (none)"
echo ""
echo "PVCs:"
kubectl get pvc -n "$NAMESPACE" 2>/dev/null || echo "  (none)"
echo ""
echo "Pods:"
kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "  (none)"
echo ""
echo "Services:"
kubectl get svc -n "$NAMESPACE" 2>/dev/null || echo "  (none)"
echo ""
echo "══════════════════════════════════════════════"
echo "✅ Verification complete"
echo "══════════════════════════════════════════════"
