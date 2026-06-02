#!/usr/bin/env bash
# ============================================================
# verify-k8s.sh — 验证 K8s 资源状态 (不部署，仅检查)
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
