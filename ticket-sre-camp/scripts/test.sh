#!/usr/bin/env bash
# ============================================================
# test.sh — 端到端集成测试脚本
# ============================================================
set -euo pipefail

NAMESPACE="ticket-sre"
PASS=0
FAIL=0

green() { echo -e "\033[32m✅ $1\033[0m"; }
red()   { echo -e "\033[31m❌ $1\033[0m"; ((FAIL++)); }
check() {
    local desc="$1" url="$2" expect="$3"
    printf "  %-50s " "${desc}..."
    local resp
    resp=$(kubectl run "test-$$-${RANDOM}" -n "$NAMESPACE" --rm -i --restart=Never --image=alpine/curl:latest -- \
        curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null) || resp="000"
    if [[ "$resp" == "$expect" ]]; then
        green "HTTP ${resp}"
        ((PASS++))
    else
        red "expected ${expect}, got ${resp}"
    fi
}

echo "══════════════════════════════════════════════"
echo "🧪 ticket-sre Integration Tests"
echo "══════════════════════════════════════════════"

# ── 测试1: 抢票 API ────────────────────────────────
echo ""
echo "── 1. Ticket API (Deployment) ──"

check "Health check" \
    "http://ticket-api-svc/healthz" "200"

check "Buy ticket" \
    "http://ticket-api-svc/buy" "200"

check "Readiness" \
    "http://ticket-api-svc/ready" "200"

# ── 测试2: 数据库 StatefulSet ───────────────────────
echo ""
echo "── 2. Ticket DB (StatefulSet) ──"

check "db-0 health" \
    "http://ticket-db-0.ticket-db-svc:8081/healthz" "200"

check "db-1 health" \
    "http://ticket-db-1.ticket-db-svc:8081/healthz" "200"

check "db-0 node info" \
    "http://ticket-db-0.ticket-db-svc:8081/node-info" "200"

# 测试主库写入
echo "  Testing master write..."
kubectl run "test-write-$$-${RANDOM}" -n "$NAMESPACE" --rm -i --restart=Never \
    --image=alpine/curl:latest -- \
    curl -s -X POST http://ticket-db-0.ticket-db-svc:8081/order/write 2>/dev/null | grep -q '"status":"success"' \
    && green "Master write OK" || red "Master write failed"

# 测试从库只读
echo "  Testing slave read..."
kubectl run "test-read-$$-${RANDOM}" -n "$NAMESPACE" --rm -i --restart=Never \
    --image=alpine/curl:latest -- \
    curl -s http://ticket-db-1.ticket-db-svc:8081/order/read 2>/dev/null | grep -q '"status":"success"' \
    && green "Slave read OK" || red "Slave read failed"

# ── 测试3: Job ──────────────────────────────────────
echo ""
echo "── 3. Init Job (Job) ──"
job_status=$(kubectl get job ticket-init -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
if [[ "$job_status" == "1" ]]; then
    green "Init Job completed successfully"
else
    red "Init Job not completed (status=${job_status})"
fi

# ── 测试4: CronJob ──────────────────────────────────
echo ""
echo "── 4. Settle CronJob (CronJob) ──"
cronjob_exists=$(kubectl get cronjob ticket-settle -n "$NAMESPACE" -o name 2>/dev/null || echo "")
if [[ -n "$cronjob_exists" ]]; then
    green "CronJob ticket-settle exists and configured"

    echo "  Manually triggering CronJob for testing..."
    kubectl create job --from=cronjob/ticket-settle "ticket-settle-test-$$" -n "$NAMESPACE" 2>/dev/null || true
    echo "  (Test job created, check with: kubectl logs job/ticket-settle-test-$$ -n ticket-sre)"
else
    red "CronJob ticket-settle not found"
fi

# ── 测试5: 探针验证 ─────────────────────────────────
echo ""
echo "── 5. Probe Verification ──"

# 验证 startupProbe
echo "  Checking startupProbe endpoint..."
resp=$(kubectl run "test-startup-$$-${RANDOM}" -n "$NAMESPACE" --rm -i --restart=Never \
    --image=alpine/curl:latest -- \
    curl -s http://ticket-api-svc/startup 2>/dev/null || echo "FAIL")
if [[ "$resp" == "startup complete" ]]; then
    green "startupProbe: Pod has completed initialization"
else
    echo "  ℹ️  startupProbe returned: ${resp}"
fi

# ── 测试6: PVC 持久化验证 ───────────────────────────
echo ""
echo "── 6. PVC Persistence Check ──"
pvc_count=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [[ "$pvc_count" -ge 2 ]]; then
    green "PVCs created: ${pvc_count} (expected >= 2 for StatefulSet)"
else
    red "PVC count: ${pvc_count}, expected >= 2"
fi

# ── 测试总结 ────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "📊 Test Results: ${PASS} passed, ${FAIL} failed"
echo "══════════════════════════════════════════════"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
