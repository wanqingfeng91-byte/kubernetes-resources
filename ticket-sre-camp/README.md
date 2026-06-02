# 🎫 抢票系统 — K8s Workload 项目驱动式学习

## 项目简介

本项目通过一个**真实的抢票业务场景**，逐一掌​​握 Kubernetes 最核心的四种 Workload 资源：

| K8s 资源 | 业务场景 | 核心痛点 |
|----------|----------|----------|
| **Deployment** | 抢票 API — 高并发、无状态、频繁发版 | 慢启动被误杀、死锁不自愈、下线丢订单 |
| **StatefulSet** | 订单主库 — 有状态、数据不能丢、主从读写分离 | Pod 身份随机化、PVC 绑定错乱 |
| **Job** | 赛前初始化 — 一次性注入 37 万张票 | 常驻 Pod 浪费资源、失败无重试 |
| **CronJob** | 每日财务对账 — 凌晨 2:00 自动导出报表 | 定时执行、并发重叠、补跑机制 |

所有服务均提供 **Go 和 Java** 双语言实现，配有完整的 Dockerfile、K8s 清单和自动化测试脚本。

---

## 项目结构

```
ticket-sre-camp/
├── cmd/                              # Go 微服务
│   ├── ticket-api/                   # 抢票 API → Deployment
│   ├── ticket-db/                    # 订单数据库 → StatefulSet
│   ├── ticket-init/                  # 库存初始化 → Job
│   └── ticket-settle/                # 财务对账 → CronJob
│
├── java/                             # Java 微服务 (Spring Boot 3.4 / Java 25)
│   ├── ticket-api/                   # Spring Boot + Actuator
│   ├── ticket-db/                    # Spring Boot + PVC I/O
│   ├── ticket-init/                  # CommandLineRunner
│   └── ticket-settle/                # CommandLineRunner
│
├── k8s/                              # Kubernetes 清单
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-ticket-api-deployment.yaml # ⭐ Deployment + 3探针 + preStop
│   ├── 03-ticket-api-svc.yaml
│   ├── 04-ticket-db-statefulset.yaml # ⭐ StatefulSet + PVC + Headless Svc
│   ├── 05-ticket-db-svc.yaml
│   ├── 06-ticket-init-job.yaml       # ⭐ Job + backoffLimit + TTL
│   ├── 07-ticket-settle-cronjob.yaml # ⭐ CronJob + Forbid 并发
│   └── kustomization.yaml
│
├── scripts/                          # 构建 / 部署 / 测试
│   ├── build-go.sh                   # 编译 Go 服务
│   ├── build-java.sh                 # 编译 Java 服务
│   ├── build-images.sh               # 构建 Docker 镜像
│   ├── deploy.sh                     # 一键部署到 K8s
│   ├── test.sh                       # 端到端集成测试
│   └── verify-k8s.sh                # 资源状态检查
│
└── README.md
```

---

## 学习路径

### 步骤一：Deployment — 抢票 API

**文件**: `k8s/02-ticket-api-deployment.yaml`  
**源码**: `cmd/ticket-api/main.go` / `java/ticket-api/`

#### 业务痛点 → K8s 解决方案

```
痛点 A：启动加载 1GB 场馆数据需要 30 秒
      如果刚启动 K8s 就把流量接进来 → 用户抢票报 500
      ↓
解决方案：Startup Probe（启动探针）
      在 startupProbe 成功之前，livenessProbe 和 readinessProbe 不会被调用
      给应用足够的预热时间，避免"还没准备好就被打流量"
```

```
痛点 B：高并发下死锁，进程还在，但无法响应任何请求
      传统运维需要人工登录机器 kill 进程
      ↓
解决方案：Liveness Probe（存活探针）
      应用内置死锁检测，/healthz 返回 503
      K8s 连续 3 次探测失败 → 自动杀掉 Pod → 重建新 Pod
      自愈过程无需人工介入
```

```
痛点 C：版本更新时 K8s 直接杀旧 Pod，正在付款的订单直接断掉
      ↓
解决方案：preStop Hook + Graceful Shutdown
      ① preStop: sleep 15 秒 + 通知 readiness 摘除流量
      ② K8s 从 Service Endpoints 中移除本 Pod IP
      ③ 发送 SIGTERM，应用处理完在途请求后安全退出
      ↓
      零丢单的滚动更新
```

#### 探针配置速查

| 探针 | 路径 | 探测间隔 | 失败阈值 | 作用 |
|------|------|----------|----------|------|
| `startupProbe` | `/startup` | 5s | 12次 (60s窗口) | 保护慢启动 |
| `livenessProbe` | `/healthz` | 10s | 3次 (30s) | 死锁自愈 |
| `readinessProbe` | `/ready` | 5s | 3次 (15s) | 流量摘除 |

#### 动手实验

```bash
# 1. 部署抢票 API
kubectl apply -f k8s/02-ticket-api-deployment.yaml

# 2. 观察 Pod 启动过程（注意 startupProbe 阶段）
kubectl get pods -n ticket-sre -w

# 3. 模拟死锁，观察 livenessProbe 自动重启
kubectl exec -it deploy/ticket-api -n ticket-sre -- \
  curl -X POST http://localhost:8080/simulate-deadlock
# 等待 30 秒，Pod 会被自动重启

# 4. 模拟 NotReady，观察 Service 摘除流量
kubectl exec -it deploy/ticket-api -n ticket-sre -- \
  curl -X POST http://localhost:8080/simulate-notready
# 查看 Endpoints，该 Pod IP 已被移除
kubectl get endpoints ticket-api-svc -n ticket-sre -o yaml

# 5. 滚动更新测试
kubectl set image deploy/ticket-api -n ticket-sre \
  ticket-api=ticket-sre/ticket-api-go:v2
kubectl rollout status deploy/ticket-api -n ticket-sre
# 观察旧 Pod 的 preStop → SIGTERM → 新 Pod 的 startupProbe 全过程

# 6. 查看滚动更新历史
kubectl rollout history deploy/ticket-api -n ticket-sre
```

---

### 步骤二：StatefulSet — 订单主库

**文件**: `k8s/04-ticket-db-statefulset.yaml`  
**源码**: `cmd/ticket-db/main.go` / `java/ticket-db/`

#### 业务痛点 → K8s 解决方案

```
痛点：数据库不能用 Deployment 部署
      Deployment 的 Pod 名称是随机的 (ticket-db-7f8c9d-abc12)
      重启后名称变了、IP 变了、PVC 绑错了

数据库需要：
  ✓ 主库永远叫 ticket-db-0，从库叫 ticket-db-1（固定身份）
  ✓ ticket-db-0 挂了在其他机器重启，必须挂回它原来那块硬盘（PVC 绑定）
  ✓ 主库先启动完成，从库再启动（有序部署）
  ✓ 下线时从库先停，主库最后停（逆序缩容）
      ↓
解决方案：StatefulSet
```

#### StatefulSet vs Deployment 核心区别

| 特性 | Deployment | StatefulSet |
|------|-----------|-------------|
| Pod 名称 | 随机哈希 `api-7f8c9d-abc12` | 固定序号 `ticket-db-0`, `ticket-db-1` |
| 网络标识 | 无独立 DNS | 每个 Pod 有独立 DNS A 记录 |
| 存储 | 共享 PVC 或不用 | 每个 Pod 独立 PVC（volumeClaimTemplates） |
| 启停顺序 | 随机并行 | 0→1→2 依次启动，2→1→0 逆序关闭 |
| 扩缩容 | 随机增删 | 序号最高的 Pod 先删 |
| 典型场景 | 无状态 API、Web 服务 | 数据库、消息队列、分布式存储 |

#### 动手实验

```bash
# 1. 部署 StatefulSet
kubectl apply -f k8s/04-ticket-db-statefulset.yaml

# 2. 观察有序启动（ticket-db-0 先 Ready，然后 ticket-db-1）
kubectl get pods -n ticket-sre -w -l app=ticket-db

# 3. 验证固定身份
kubectl exec ticket-db-0 -n ticket-sre -- hostname
# 输出: ticket-db-0 ← 永远不会变
kubectl exec ticket-db-1 -n ticket-sre -- hostname
# 输出: ticket-db-1

# 4. 验证独立 DNS 记录（Headless Service 的威力）
kubectl run dns-test -n ticket-sre --rm -it --image=alpine/curl -- sh
# 在容器内执行:
nslookup ticket-db-0.ticket-db-svc.ticket-sre.svc.cluster.local
# → 返回 ticket-db-0 的 Pod IP（独享 A 记录）
nslookup ticket-db-1.ticket-db-svc.ticket-sre.svc.cluster.local
# → 返回 ticket-db-1 的 Pod IP

# 5. 验证主库写入 / 从库禁止写入
kubectl exec ticket-db-0 -n ticket-sre -- \
  curl -s -X POST http://localhost:8081/order/write
# → {"status":"success","msg":"订单已写入主库",...}

kubectl exec ticket-db-1 -n ticket-sre -- \
  curl -s -X POST http://localhost:8081/order/write
# → {"status":"error","msg":"当前节点是 slave，写请求请发送到主库 ticket-db-0"}

# 6. 验证 PVC 持久化
# 查看每个 Pod 独有的 PVC
kubectl get pvc -n ticket-sre
# 输出:
# data-ticket-db-0   Bound   pvc-abc123   1Gi   RWO   standard
# data-ticket-db-1   Bound   pvc-def456   1Gi   RWO   standard

# 写入测试数据
kubectl exec ticket-db-0 -n ticket-sre -- \
  curl -s http://localhost:8081/storage/identity
# → hostname=ticket-db-0 role=master ordinal=0 created=...

# 删除 Pod 再重启，验证数据还在
kubectl delete pod ticket-db-0 -n ticket-sre
# 等待 Pod 重建完成
kubectl exec ticket-db-0 -n ticket-sre -- \
  curl -s http://localhost:8081/storage/identity
# → ✅ 返回相同数据！证明 PVC 正确重新绑定
```

---

### 步骤三：Job & CronJob — 对账与报表

**文件**: `k8s/06-ticket-init-job.yaml` / `k8s/07-ticket-settle-cronjob.yaml`  
**源码**: `cmd/ticket-init/` + `cmd/ticket-settle/` / `java/ticket-init/` + `java/ticket-settle/`

#### Job — 一次性任务

```
痛点 A：抢票开始前需要一次性注入 37 万张门票库存
      起一个常驻 Pod 跑完就闲置 → 浪费资源
      ↓
解决方案：Job
      执行完自动进入 Completed 状态，不占用 CPU/内存
      失败自动重试 (backoffLimit)
      完成后自动清理 (ttlSecondsAfterFinished)
```

#### CronJob — 定时任务

```
痛点 B：财务要求每天凌晨 2:00 自动对账并导出报表
      人工每天手动跑脚本 → 迟早会忘
      ↓
解决方案：CronJob
      定时自动创建 Job 执行
      concurrencyPolicy: Forbid → 上次没跑完就跳过，防止对账数据重叠
      startingDeadlineSeconds → 集群维护导致错过调度，300秒内可以补跑
```

#### 动手实验

```bash
# ── Job 实验 ──────────────────────────────

# 1. 部署初始化 Job
kubectl apply -f k8s/06-ticket-init-job.yaml

# 2. 观察 Job 执行过程
kubectl get job ticket-init -n ticket-sre -w
kubectl logs job/ticket-init -n ticket-sre

# 3. Job 完成后验证
kubectl get pods -n ticket-sre -l app=ticket-init
# STATUS: Completed ← Job 特有的状态

# 4. 查看 Job 详情
kubectl describe job ticket-init -n ticket-sre
# 关注: Pod Statuses (Active / Succeeded / Failed)

# ── CronJob 实验 ──────────────────────────

# 5. 部署 CronJob
kubectl apply -f k8s/07-ticket-settle-cronjob.yaml

# 6. 查看 CronJob 配置
kubectl get cronjob ticket-settle -n ticket-sre
# SCHEDULE: 0 2 * * * (每天凌晨2:00)

# 7. 手动触发一次（调试用）
kubectl create job --from=cronjob/ticket-settle ticket-settle-manual -n ticket-sre
kubectl logs job/ticket-settle-manual -n ticket-sre -f

# 8. 验证并发保护 (concurrencyPolicy: Forbid)
# 如果上一个 Job 还在跑，再创建一个同源 Job
kubectl create job --from=cronjob/ticket-settle ticket-settle-test2 -n ticket-sre
# CronJob 本身的下次调度会跳过（因为上次还没完成）

# 9. 暂停 / 恢复 CronJob
kubectl patch cronjob ticket-settle -n ticket-sre -p '{"spec":{"suspend":true}}'
kubectl patch cronjob ticket-settle -n ticket-sre -p '{"spec":{"suspend":false}}'
```

---

## Cron 表达式速查

CronJob 使用 5 段式 Cron 表达式：

```
┌────── 分钟 (0-59)
│ ┌────── 小时 (0-23)
│ │ ┌────── 日   (1-31)
│ │ │ ┌────── 月   (1-12)
│ │ │ │ ┌────── 星期 (0-6, 0=周日)
│ │ │ │ │
* * * * *
```

| 表达式 | 含义 |
|--------|------|
| `0 2 * * *` | 每天凌晨 2:00 |
| `*/5 * * * *` | 每 5 分钟 |
| `0 * * * *` | 每小时整点 |
| `0 9 * * 1-5` | 工作日早上 9:00 |
| `0 0 1 * *` | 每月 1 号凌晨 |
| `30 3 15 * *` | 每月 15 号 3:30 |

---

## 构建与部署

### 环境要求

| 工具 | 版本 |
|------|------|
| Go | 1.25+ |
| Java | 25+ |
| Maven | 3.9+ |
| Docker | 24+ |
| kubectl | 1.28+ |

### 一键部署

```bash
# 1. 编译所有 Go 服务
bash scripts/build-go.sh          # → bin/ticket-*-go

# 2. 编译所有 Java 服务
bash scripts/build-java.sh        # → java/*/target/*.jar

# 3. 构建所有 Docker 镜像 (8个)
bash scripts/build-images.sh      # 镜像名: ticket-sre/<服务>-<语言>:latest

# 4. 部署到 Kubernetes
bash scripts/deploy.sh            # kubectl apply -k ./k8s

# 5. 运行集成测试
bash scripts/test.sh              # 端到端功能验证

# 6. 检查资源状态
bash scripts/verify-k8s.sh       # 所有资源的健康检查
```

### 切换 Go / Java 版本

K8s 清单默认使用 Go 镜像。切换到 Java 版本只需修改 Deployment / StatefulSet 中的 `image` 字段：

```yaml
# Go 版本 (默认)
image: ticket-sre/ticket-api-go:latest

# Java 版本
image: ticket-sre/ticket-api-java:latest
```

或通过 `kustomization.yaml` 统一替换（推荐）。

---

## API 速查表

### 抢票 API (ticket-api, 端口 8080)

| 方法 | 路径 | 用途 | K8s 探针 |
|------|------|------|----------|
| GET | `/startup` | 启动完成检查 | startupProbe |
| GET | `/healthz` | 存活检查（死锁时返回 503） | livenessProbe |
| GET | `/ready` | 就绪检查 | readinessProbe |
| POST | `/buy` | 核心业务：抢票 | - |
| POST | `/simulate-deadlock` | 触发模拟死锁 | 测试用 |
| POST | `/simulate-notready` | 标记为 NotReady | 测试用 |
| POST | `/recover` | 恢复正常状态 | 测试用 |

### 订单数据库 (ticket-db, 端口 8081)

| 方法 | 路径 | 用途 |
|------|------|------|
| GET | `/healthz` | 健康检查 |
| GET | `/ready` | 就绪检查 |
| GET | `/node-info` | 查看节点身份 (hostname, role, ordinal) |
| GET | `/storage/identity` | 查看 PVC 中的身份文件（验证持久化） |
| POST | `/order/write` | 写订单（仅主库允许） |
| GET | `/order/read` | 读订单（主从均可） |

---

## K8s 核心概念速记

### 三种探针决策树

```
Pod 启动了，要不要给它发流量？

  ├─ 还没初始化完？ → startupProbe 失败 → 不给流量，也不杀 Pod
  │
  ├─ 初始化完了，进程还活着吗？ → livenessProbe 失败 → 杀 Pod，重建
  │
  └─ 活着，能正常处理请求吗？ → readinessProbe 失败 → 不给流量（摘除），但不杀 Pod
```

### Workload 选型决策树

```
这个服务有没有状态？

  ├─ 无状态 (重启后数据无所谓)
  │   ├─ 需要一直跑？ → Deployment
  │   ├─ 跑一次就结束？ → Job
  │   └─ 定时跑？ → CronJob
  │
  ├─ 有状态 (重启后必须用原来的数据)
  │   ├─ 需要固定身份 + 独立存储？ → StatefulSet
  │   └─ 单机，不需要集群管理？ → 也可以用 Deployment + 单 PVC
  │
  └─ 每台机器都要跑一个 (如日志采集)？ → DaemonSet
```

### 优雅下线时间线

```
kubectl delete pod (或滚动更新)
  │
  ├─ 0s   K8s 将 Pod 状态改为 Terminating
  │       ↓
  ├─ 0s   执行 preStop Hook:
  │        ① curl /simulate-notready → readinessProbe 立即失败
  │        ② sleep 15 秒（排水窗口）
  │       ↓
  ├─ ~5s  K8s 从 Service Endpoints 摘除此 Pod IP
  │       新请求不再路由过来
  │       ↓
  ├─ ~15s 在途请求处理完毕
  │       ↓
  ├─ 15s  preStop 结束，K8s 发送 SIGTERM 给容器主进程
  │       ↓
  ├─ 15-30s  应用执行 Graceful Shutdown
  │       ↓
  └─ 30s  terminationGracePeriodSeconds 到期
          如果还没退出，K8s 发送 SIGKILL 强制杀死
```

---

## 维护与清理

```bash
# 删除所有资源
kubectl delete namespace ticket-sre

# 仅删除 Job（保留 CronJob 下次调度）
kubectl delete job ticket-init -n ticket-sre

# 仅删除 CronJob 生成的旧 Job
kubectl delete jobs -n ticket-sre -l app=ticket-settle

# 清理 Docker 镜像
docker images "ticket-sre/*" -q | xargs docker rmi
```

---

## 延伸学习

掌握本项目后，可以继续深入：

- **HPA** — 抢票 API 根据 CPU/内存自动扩缩容（基于 Deployment）
- **PDB** — 保证最少可用 Pod 数量，防止批量误删除
- **NetworkPolicy** — 限制数据库只允许 API 访问
- **Secret** — 数据库密码、支付 API Key 的安全存储
- **ServiceAccount + RBAC** — 为 Job/CronJob 分配最小 API 权限
- **InitContainer** — 在数据库容器启动前，检查 PVC 是否就绪
- **DaemonSet** — 在每个 Node 上部署日志采集 Agent
