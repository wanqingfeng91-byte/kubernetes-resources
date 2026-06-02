# 🔌 抢票系统接口文档 — K8s Workload 学习视角

本文档按 K8s Workload 分组，说明每个接口的**业务作用**、**K8s 如何用它**、以及**它体现了哪个 Workload 核心概念**。

---

## 目录

- [一、抢票 API — Deployment](#一抢票-api--deployment)
  - [接口全景图](#ticket-api-接口全景图)
  - [1. GET /startup — 启动探针](#1-get-startup--启动探针)
  - [2. GET /healthz — 存活探针（死锁检测）](#2-get-healthz--存活探针死锁检测)
  - [3. GET /ready — 就绪探针](#3-get-ready--就绪探针)
  - [4. POST /buy — 核心业务：抢票](#4-post-buy--核心业务抢票)
  - [5. POST /simulate-deadlock — 模拟死锁](#5-post-simulatedeadlock--模拟死锁)
  - [6. POST /simulate-notready — 模拟未就绪](#6-post-simulatenotready--模拟未就绪)
  - [7. POST /recover — 故障恢复](#7-post-recover--故障恢复)
- [二、订单主库 — StatefulSet](#二订单主库--statefulset)
  - [接口全景图](#ticket-db-接口全景图)
  - [1. GET /healthz](#1-get-healthz)
  - [2. GET /ready](#2-get-ready)
  - [3. GET /node-info — 稳定身份标识](#3-get-node-info--稳定身份标识)
  - [4. POST /order/write — 主库写入](#4-post-orderwrite--主库写入)
  - [5. GET /order/read — 主从读取](#5-get-orderread--主从读取)
  - [6. GET /storage/identity — PVC 持久化证明](#6-get-storageidentity--pvc-持久化证明)
- [三、库存初始化 — Job](#三库存初始化--job)
- [四、财务对账 — CronJob](#四财务对账--cronjob)
- [五、K8s 探针与 Workload 决策矩阵](#五k8s-探针与-workload-决策矩阵)

---

## 一、抢票 API — Deployment

**K8s 资源**：Deployment（无状态，3副本，滚动更新）  
**源码位置**：`cmd/ticket-api/main.go` / `java/ticket-api/`  
**容器端口**：`8080`  
**Service**：`ticket-api-svc:80 → targetPort:8080`  
**K8s 清单**：`k8s/02-ticket-api-deployment.yaml`

### 业务背景

这是抢票系统的**唯一入口**。用户打开 App 点击"抢票"，请求到达此服务。它必须：
- 扛住 10 万 QPS 的高并发流量
- 频繁发版（每周两次），更新时不丢在线订单
- 死锁时自动恢复，不需要人工重启

### Ticket-API 接口全景图

```
                    ┌─────────────────────────────┐
                    │     K8s 控制平面              │
                    │                             │
                    │  startupProbe ─── GET /startup │
                    │  livenessProbe ── GET /healthz │
                    │  readinessProbe ─ GET /ready   │
                    │                             │
                    └──────────┬──────────────────┘
                               │
              ┌────────────────┴────────────────┐
              │         ticket-api Pod           │
              │         (Deployment)             │
              │                                  │
              │  GET  /startup         启动探针    │
              │  GET  /healthz         存活探针    │
              │  GET  /ready           就绪探针    │
              │  POST /buy             抢票业务    │
              │  POST /simulate-deadlock  故障模拟  │
              │  POST /simulate-notready  故障模拟  │
              │  POST /recover             故障恢复  │
              └─────────────────────────────────┘
                               │
                               ▼
                    用户请求 → POST /buy
```

---

### 1. GET /startup — 启动探针

```
GET /startup
```

| 属性 | 值 |
|------|-----|
| **谁在调用** | K8s startupProbe（每 5 秒探测一次） |
| **K8s 配置** | `failureThreshold: 12` × `periodSeconds: 5` = 最多等待 60 秒 |
| **Go 实现** | `cmd/ticket-api/main.go:34` |
| **Java 实现** | `java/ticket-api/.../TicketApiApplication.java:51` |

#### 业务含义

抢票服务启动时需要从配置中心加载 **1GB 全国场馆座位数据**（座位图、分区、票价矩阵），需要约 30 秒。

在数据加载完毕前，服务不能处理抢票请求——连场馆信息都没有，怎么卖票？

#### 接口行为

| 时间 | 返回状态码 | 返回内容 | 含义 |
|------|-----------|----------|------|
| 启动后 0-30 秒 | `503 Service Unavailable` | `loading venue data...` | 还在加载数据 |
| 启动后 >30 秒 | `200 OK` | `startup complete` | 数据加载完毕 |

#### K8s 如何利用这个接口

```
Pod 启动
  │
  ├─ 0s   容器进程启动
  ├─ 0s   startupProbe 开始探测 GET /startup
  │       ├─ 第 1 次 → 503 "loading..." → 继续等待
  │       ├─ 第 2 次 → 503 → 继续
  │       ├─    ...
  │       ├─ 第 6 次 (30s) → 200 "startup complete" ✅
  │       │
  │       └─ startupProbe 成功！
  │          ├─ livenessProbe 开始工作
  │          └─ readinessProbe 开始工作
  │
  └─ 如果 60 秒内没成功（12 次全失败）
       └─ K8s 判定启动失败 → 重启 Pod
```

> **核心知识点**：如果没有 startupProbe，只配 livenessProbe，那么前 30 秒 /healthz 也会返回 503，livenessProbe 就会在 30 秒后把还在正常启动中的 Pod 杀掉。**StartupProbe 就是给慢启动应用的"保护罩"**。

#### 测试命令

```bash
# 查看 Pod 启动事件（关注 startupProbe 阶段）
kubectl describe pod -n ticket-sre -l app=ticket-api | grep -A5 "startup"

# 直接访问 Pod 测试
kubectl exec deploy/ticket-api -n ticket-sre -- curl -s http://localhost:8080/startup
# → startup complete
```

---

### 2. GET /healthz — 存活探针（死锁检测）

```
GET /healthz
```

| 属性 | 值 |
|------|-----|
| **谁在调用** | K8s livenessProbe（每 10 秒探测一次） |
| **K8s 配置** | `failureThreshold: 3` × `periodSeconds: 10` = 30 秒后杀 Pod |
| **Go 实现** | `cmd/ticket-api/main.go:48` |
| **Java 实现** | `java/ticket-api/.../TicketApiApplication.java:63` |

#### 业务含义

高并发抢票意味着大量 goroutine / thread 同时竞争锁资源（库存扣减、座位锁定、订单生成）。一旦出现死锁，**所有请求线程卡死**，进程虽然还活着，但已经无法处理任何抢票请求。

传统做法：运维收到报警 → SSH 登录 → `kill -9` → 手动重启。  
K8s 做法：livenessProbe 检测到 /healthz 返回 503 → 自动杀 Pod → 重建。

#### 接口行为

| 服务状态 | 返回状态码 | 返回内容 | K8s 行为 |
|----------|-----------|----------|----------|
| 正常运行 | `200 OK` | `OK` | 无事发生 |
| 初始化中（<30s） | `503 Service Unavailable` | `initializing` | startupProbe 还在保护期，不会杀 |
| **死锁** | `503 Service Unavailable` | `DEADLOCK DETECTED` | 连续 3 次 → 杀 Pod 重建 |
| 健康标志位未就绪 | `503 Service Unavailable` | `initializing` | 等待中 |

#### 死锁检测原理

Go 实现中使用了 `atomic` 包维护 `isDeadlock` 标志位：

```go
var isDeadlock int32  // 0 = 正常, 1 = 死锁

// /healthz 处理逻辑
if atomic.LoadInt32(&isDeadlock) == 1 {
    w.WriteHeader(503)  // ← K8s 看到这个，30 秒后杀 Pod
}
```

正常业务代码中可以定期更新一个心跳变量，/healthz 检查心跳是否超时：

```go
// 每个请求处理完更新心跳
var lastHeartbeat int64
atomic.StoreInt64(&lastHeartbeat, time.Now().Unix())

// /healthz 检查
if time.Now().Unix() - atomic.LoadInt64(&lastHeartbeat) > 30 {
    return 503  // 30 秒没处理完任何请求 → 判定死锁
}
```

> **核心知识点**：livenessProbe 是**最后的手段**——K8s 不会试图修复你的应用，它直接杀掉重建。探针逻辑必须**轻量且精准**，不要做外部依赖检查（比如查数据库），否则数据库挂了会导致所有 Pod 被连环重启。

#### 测试命令

```bash
# 正常状态
kubectl exec deploy/ticket-api -n ticket-sre -- curl -s http://localhost:8080/healthz
# → OK

# 模拟死锁后再次探测
kubectl exec deploy/ticket-api -n ticket-sre -- curl -s -X POST http://localhost:8080/simulate-deadlock
kubectl exec deploy/ticket-api -n ticket-sre -- curl -s http://localhost:8080/healthz
# → DEADLOCK DETECTED

# 观察 K8s 自动重启 Pod
kubectl get pods -n ticket-sre -w -l app=ticket-api
# 30 秒后 Pod 自动重启
```

---

### 3. GET /ready — 就绪探针

```
GET /ready
```

| 属性 | 值 |
|------|-----|
| **谁在调用** | K8s readinessProbe（每 5 秒探测一次） |
| **K8s 配置** | `failureThreshold: 3` × `periodSeconds: 5` = 15 秒后摘除流量 |
| **Go 实现** | `cmd/ticket-api/main.go:66` |
| **Java 实现** | `java/ticket-api/.../TicketApiApplication.java:78` |

#### 业务含义

有些情况下服务进程还活着（/healthz = 200），但**暂时不能处理请求**。比如：
- 数据库连接池满了，暂时拿不到连接
- 依赖的 Redis 挂了，缓存全部穿透
- 正在做 Full GC，暂停了所有业务线程

这时候不应该杀 Pod（重启也没用，问题在外部依赖），但也不应该把流量发给它（它会给你报错）。

#### 接口行为

| 服务状态 | 返回状态码 | 返回内容 | K8s 行为 |
|----------|-----------|----------|----------|
| Ready | `200 OK` | `ready` | Pod IP 在 Service Endpoints 中，接收流量 |
| NotReady | `503 Service Unavailable` | `not ready` | Pod IP 从 Service Endpoints 中移除，**不给流量** |

#### K8s 如何利用这个接口

```
正常状态：
  Service Endpoints: [10.244.1.5, 10.244.1.6, 10.244.1.7]  ← 3 个 Pod 都在

Pod-1 的 /ready 开始返回 503：
  第 1 次失败 → 等 5 秒
  第 2 次失败 → 等 5 秒
  第 3 次失败 → 从 Endpoints 移除 10.244.1.6
  Service Endpoints: [10.244.1.5, 10.244.1.7]  ← 只剩 2 个

Pod-1 恢复，/ready 返回 200：
  Service Endpoints: [10.244.1.5, 10.244.1.6, 10.244.1.7]  ← 自动加回
```

> **核心知识点**：readinessProbe 控制的是**流量开关**，不是 Pod 生命周期。NotReady 的 Pod 不会被杀掉，只是暂时不被访问。

#### 与 preStop 的配合（优雅下线）

```bash
# preStop Hook 中的操作：
curl -X POST http://localhost:8080/simulate-notready  # 触发 /ready → 503
sleep 15  # 等待 Endpoints 更新 + 在途请求处理完
# → 然后 K8s 才发 SIGTERM
```

#### 测试命令

```bash
# 模拟 NotReady
kubectl exec deploy/ticket-api -n ticket-sre -- curl -s -X POST http://localhost:8080/simulate-notready

# 查看 Service Endpoints 变化
kubectl get endpoints ticket-api-svc -n ticket-sre -o yaml
# 被标记 NotReady 的 Pod IP 已从 addresses 列表中消失

# 恢复
kubectl exec deploy/ticket-api -n ticket-sre -- curl -s -X POST http://localhost:8080/recover
```

---

### 4. POST /buy — 核心业务：抢票

```
POST /buy
```

| 属性 | 值 |
|------|-----|
| **谁在调用** | 用户 / 前端 App / 压力测试工具 |
| **端口** | 通过 Service `ticket-api-svc:80` 负载均衡 |
| **Go 实现** | `cmd/ticket-api/main.go:78` |
| **Java 实现** | `java/ticket-api/.../TicketApiApplication.java:89` |

#### 业务含义

演唱会门票抢购的核心接口。模拟了真实的抢票流程：
扣减库存 → 锁定座位 → 生成订单，耗时约 2 秒。

#### 请求

```bash
POST /buy
Content-Type: application/json
# 无请求体（演示简化）
```

#### 响应

**正常响应** `200 OK`：

```json
{
    "status": "success",
    "msg": "🎉 恭喜！天王演唱会门票抢购成功！",
    "orderId": "ORD20260602001"
}
```

**死锁时响应** `500 Internal Server Error`：

```json
{
    "status": "error",
    "msg": "系统繁忙"
}
```

#### 教学要点

这个接口本身是普通的业务逻辑，但在 K8s 上下文中它展示了：

1. **为什么用 Deployment**：无状态——任何 Pod 都能处理任何请求，订单数据存在外部数据库
2. **为什么需要多副本**：高并发，3 个 Pod 用 Service 负载均衡分担流量
3. **为什么死锁时返回 500**：如果直接阻塞不返回，K8s Service 的负载均衡会一直等待超时，影响所有用户
4. **为什么需要 readinessProbe**：某个 Pod 的 /buy 因为依赖故障一直失败，readinessProbe 会把它摘掉，确保用户请求只打到健康的 Pod

#### 测试命令

```bash
# 通过 Service 访问
kubectl run test-buy -n ticket-sre --rm -i --restart=Never --image=alpine/curl -- \
    curl -s -X POST http://ticket-api-svc/buy

# 高并发压测（需要 ab 或 hey 工具）
kubectl port-forward svc/ticket-api-svc 8080:80 -n ticket-sre &
hey -n 1000 -c 50 -m POST http://localhost:8080/buy
```

---

### 5. POST /simulate-deadlock — 模拟死锁

```
POST /simulate-deadlock
```

| Go 实现 | `cmd/ticket-api/main.go:92` |
| Java 实现 | `java/ticket-api/.../TicketApiApplication.java:106` |

#### 作用

将内部 `isDeadlock` 标志置为 `1`。此后：
- `GET /healthz` → `503 DEADLOCK DETECTED`
- `POST /buy` → `500 系统繁忙`
- livenessProbe 连续 3 次失败 → K8s 30 秒后自动杀 Pod → 重建

#### 请求

```bash
POST /simulate-deadlock
```

#### 响应

```json
{
    "status": "ok",
    "msg": "deadlock simulated, livenessProbe will restart pod in ~30s"
}
```

> **教学用途**：这是唯一能让你**亲眼看到 K8s 自愈能力**的接口。调用后观察 Pod 如何在 30 秒内自动重启——全程零人工干预。

---

### 6. POST /simulate-notready — 模拟未就绪

```
POST /simulate-notready
```

| Go 实现 | `cmd/ticket-api/main.go:98` |
| Java 实现 | `java/ticket-api/.../TicketApiApplication.java:113` |

#### 作用

将 `isReady` 标志置为 `0`。此后：
- `GET /ready` → `503 not ready`
- readinessProbe 连续 3 次失败 → 15 秒后从 Service Endpoints 摘除
- Pod 不会被杀，进程继续运行

#### 请求

```bash
POST /simulate-notready
```

#### 响应

```json
{
    "status": "ok",
    "msg": "marked not ready, traffic will be drained"
}
```

> **教学用途**：演示 readinessProbe 的流量控制能力。与 livenessProbe 的关键区别——不杀 Pod，只摘流量。

---

### 7. POST /recover — 故障恢复

```
POST /recover
```

| Go 实现 | `cmd/ticket-api/main.go:104` |
| Java 实现 | `java/ticket-api/.../TicketApiApplication.java:120` |

#### 作用

将 `isDeadlock` 和 `isReady` 重置为正常值：
- `isDeadlock: 1 → 0`
- `isReady: 0 → 1`

#### 请求

```bash
POST /recover
```

#### 响应

```json
{
    "status": "ok",
    "msg": "recovered"
}
```

> **教学用途**：在模拟 NotReady 之后手动恢复，验证 readinessProbe 重新将 Pod 加入 Endpoints。

---

## 二、订单主库 — StatefulSet

**K8s 资源**：StatefulSet（2副本：ticket-db-0 主库 + ticket-db-1 从库）  
**源码位置**：`cmd/ticket-db/main.go` / `java/ticket-db/`  
**容器端口**：`8081`  
**Headless Service**：`ticket-db-svc`（clusterIP: None） —— 为每个 Pod 创建独立 DNS 记录  
**ClusterIP Service**：`ticket-db-master:8081` —— 常规负载均衡服务  
**K8s 清单**：`k8s/04-ticket-db-statefulset.yaml` + `k8s/05-ticket-db-svc.yaml`

### 业务背景

抢票的所有订单数据必须持久化到数据库，采用**主从架构**：
- **主库（ticket-db-0）**：处理所有写操作（INSERT / UPDATE / DELETE）
- **从库（ticket-db-1）**：处理读操作（SELECT），分担主库压力

数据库的特殊要求：
- Pod 名称绝对不能变（客户端通过 DNS 找主库）
- 每个 Pod 的数据必须存在自己专属的硬盘上
- Pod 挂了在别的机器重启，必须挂回同一块盘

### Ticket-DB 接口全景图

```
      ┌──────────────────────────────────────────────────────┐
      │                 StatefulSet: ticket-db               │
      │                                                     │
      │  ┌──────────────────┐   ┌──────────────────┐       │
      │  │   ticket-db-0    │   │   ticket-db-1    │       │
      │  │   (master)       │   │   (slave)        │       │
      │  │   端口: 8081      │   │   端口: 8081      │       │
      │  │                  │   │                  │       │
      │  │ GET /healthz     │   │ GET /healthz     │       │
      │  │ GET /ready       │   │ GET /ready       │       │
      │  │ GET /node-info   │   │ GET /node-info   │       │
      │  │ POST /order/write│   │ GET /order/read  │       │
      │  │ GET /order/read  │   │ GET /storage/    │       │
      │  │ GET /storage/    │   │   identity       │       │
      │  │   identity       │   │                  │       │
      │  │                  │   │                  │       │
      │  │ PVC: data-ticket-│   │ PVC: data-ticket-│       │
      │  │   db-0 (1Gi)     │   │   db-1 (1Gi)     │       │
      │  └──────────────────┘   └──────────────────┘       │
      │                                                     │
      │  DNS:                                                │
      │  ticket-db-0.ticket-db-svc.ticket-sre.svc... → 10.244.1.5 │
      │  ticket-db-1.ticket-db-svc.ticket-sre.svc... → 10.244.2.3 │
      └──────────────────────────────────────────────────────┘
```

---

### 1. GET /healthz

```
GET /healthz
```

同 ticket-api，用于 K8s livenessProbe。`initialDelaySeconds` 更长（数据库启动慢）。

---

### 2. GET /ready

```
GET /ready
```

用于 readinessProbe。数据库完全启动后才标记 Ready。

---

### 3. GET /node-info — 稳定身份标识

```
GET /node-info
```

| Go 实现 | `cmd/ticket-db/main.go:111` |
| Java 实现 | `java/ticket-db/.../TicketDbApplication.java:97` |

#### 业务含义

这是 StatefulSet **最核心的概念** 的展示接口：**稳定身份**。

在 Deployment 中，Pod 名称是随机哈希（如 `api-7f8c9d-abc12`），每次重启都变。  
在 StatefulSet 中，Pod 名称永远固定（`ticket-db-0`），不管重启多少次、迁移到哪个节点，名称不变。

客户端通过 DNS 名称 `ticket-db-0.ticket-db-svc.ticket-sre.svc.cluster.local` 找到主库——如果 Pod 名会变，这个 DNS 就没意义了。

#### 响应

```json
{
    "hostname": "ticket-db-0",
    "role": "master",
    "ordinal": 0,
    "dataDir": "/data/ticket-db",
    "uptime": "1h23m45s"
}
```

| 字段 | 含义 | 由谁决定 |
|------|------|----------|
| `hostname` | Pod 名称，**永远不变** | StatefulSet 自动分配：`{sts-name}-{序号}` |
| `role` | 主从角色 | 应用从 ordinal 推导：`0→master`, `≥1→slave` |
| `ordinal` | Pod 序号，从 0 开始递增 | StatefulSet 分配，删除 Pod 后序号不变 |
| `dataDir` | 数据存储路径 | PVC 挂载点，存储到独立硬盘 |

> **核心知识点**：Ordinal 是 StatefulSet 给每个 Pod 的**永久编号**。不管 Pod 被删多少次，重建后 ordinal 不变。应用利用这个值来决定自己的角色——这是 StatefulSet 区别于 Deployment 的根本特征。

#### 测试命令

```bash
# 查看主库身份
kubectl exec ticket-db-0 -n ticket-sre -- curl -s http://localhost:8081/node-info | jq

# 查看从库身份
kubectl exec ticket-db-1 -n ticket-sre -- curl -s http://localhost:8081/node-info | jq

# 注意 hostname 和 role 的区别
# ticket-db-0 → role: "master"
# ticket-db-1 → role: "slave"

# 删除主库 Pod 后验证身份不变
kubectl delete pod ticket-db-0 -n ticket-sre
kubectl wait --for=condition=ready pod/ticket-db-0 -n ticket-sre --timeout=60s
kubectl exec ticket-db-0 -n ticket-sre -- curl -s http://localhost:8081/node-info | jq
# hostname 仍然是 ticket-db-0，role 仍是 master ✅
```

---

### 4. POST /order/write — 主库写入

```
POST /order/write
```

| Go 实现 | `cmd/ticket-db/main.go:118` |
| Java 实现 | `java/ticket-db/.../TicketDbApplication.java:110` |

#### 业务含义

模拟订单写入数据库。**只有主库（ordinal=0）允许写操作**——这是数据库主从架构的经典约束。

从库（ordinal≥1）收到写请求会返回 403，并明确告诉客户端"请找主库 ticket-db-0"。

#### 请求

```bash
POST /order/write
```

#### 响应

**主库写入成功** `200 OK`：

```json
{
    "status": "success",
    "msg": "订单已写入主库",
    "node": "ticket-db-0",
    "written": "order_id=ORD1717339200123456789 timestamp=2026-06-02T14:30:00+08:00"
}
```

**从库写入拒绝** `403 Forbidden`：

```json
{
    "status": "error",
    "msg": "当前节点 [ticket-db-1] 是 slave，请将写请求发送到主库 ticket-db-0"
}
```

#### 数据存储

写入的内容追加到 PVC 上的 `orders.dat` 文件中：

```
# /data/ticket-db/orders.dat
# 抢票订单数据
order_id=ORD1717339200123456789 timestamp=2026-06-02T14:30:00+08:00
order_id=ORD1717339200987654321 timestamp=2026-06-02T14:30:05+08:00
```

> **核心知识点**：写文件操作证实了 StatefulSet 的 PVC 持久化。Pod 重启后，这些数据**仍然存在**。

#### 测试命令

```bash
# 写主库 → 成功
kubectl exec ticket-db-0 -n ticket-sre -- curl -s -X POST http://localhost:8081/order/write | jq

# 写从库 → 403
kubectl exec ticket-db-1 -n ticket-sre -- curl -s -X POST http://localhost:8081/order/write | jq
# → "请将写请求发送到主库 ticket-db-0"
```

---

### 5. GET /order/read — 主从读取

```
GET /order/read
```

| Go 实现 | `cmd/ticket-db/main.go:143` |
| Java 实现 | `java/ticket-db/.../TicketDbApplication.java:132` |

#### 业务含义

模拟订单查询。**主库和从库都可以读**——这是读写分离的体现。

#### 响应

```json
{
    "status": "success",
    "node": "ticket-db-1",
    "role": "slave",
    "data": "# 抢票订单数据\norder_id=ORD1717339200123456789 timestamp=2026-06-02T14:30:00+08:00\n",
    "size": "120 bytes"
}
```

注意 `node` 字段，它表明数据是从哪个 Pod 返回的。从库读到的是主库写入的同一份数据（这里简化模拟，实际生产中通过 binlog 复制）。

#### 测试命令

```bash
# 从主库读
kubectl exec ticket-db-0 -n ticket-sre -- curl -s http://localhost:8081/order/read | jq

# 从从库读（也能读到数据）
kubectl exec ticket-db-1 -n ticket-sre -- curl -s http://localhost:8081/order/read | jq
```

---

### 6. GET /storage/identity — PVC 持久化证明

```
GET /storage/identity
```

| Go 实现 | `cmd/ticket-db/main.go:156` |
| Java 实现 | `java/ticket-db/.../TicketDbApplication.java:148` |

#### 业务含义

这是 StatefulSet **第二大核心概念** 的验证接口：**PVC 持久化绑定**。

Pod 首次启动时，会在 PVC 上写入一个身份文件 `node-identity.txt`。  
Pod 被删除后在别的节点重建，**同一个 PVC 会重新挂载**，身份文件内容不变。  
**这就证明了"硬盘跟着 Pod 走"**。

#### 响应

```text
hostname=ticket-db-0 role=master ordinal=0 created=2026-06-01T10:15:30
```

#### K8s 如何保证 PVC 不绑定错

```
StatefulSet 创建 ticket-db-0：
  → StatefulSet 为 Pod-0 创建 PVC: data-ticket-db-0
  → PV 绑定到 PVC: data-ticket-db-0 → pv-abc123 (Node A 的硬盘)
  → ticket-db-0 在 Node A 启动，挂载 pv-abc123

ticket-db-0 被删除（Node A 宕机）：
  → PVC data-ticket-db-0 仍然存在（不随 Pod 删除）
  → StatefulSet 重建 ticket-db-0
  → 新 Pod 调度到 Node B
  → K8s 发现 PVC data-ticket-db-0 绑定到 pv-abc123
  → pv-abc123 可能是网络存储（Ceph/NFS），不受 Node 限制
  → ticket-db-0 在 Node B 启动，**挂载的还是同一块盘**
```

> **核心知识点**：`volumeClaimTemplates` 创建的 PVC 不会随 Pod 删除而删除。这是 StatefulSet 与 Deployment 的本质区别之一。Deployment 如果用了 PVC，所有 Pod 共享一块盘；StatefulSet 每个 Pod 独享一块。

#### 测试命令

```bash
# 查看当前身份文件
kubectl exec ticket-db-0 -n ticket-sre -- curl -s http://localhost:8081/storage/identity
# → hostname=ticket-db-0 role=master ordinal=0 created=2026-06-01T10:15:30

# 删除 Pod
kubectl delete pod ticket-db-0 -n ticket-sre

# 等待重建后再次查看
kubectl exec ticket-db-0 -n ticket-sre -- curl -s http://localhost:8081/storage/identity
# → hostname=ticket-db-0 role=master ordinal=0 created=2026-06-01T10:15:30
# ✅ 内容完全一样！证明数据没有丢失

# 查看 PVC 列表
kubectl get pvc -n ticket-sre
# data-ticket-db-0   Bound   pvc-abc123   1Gi   RWO   standard
# data-ticket-db-1   Bound   pvc-def456   1Gi   RWO   standard
```

---

## 三、库存初始化 — Job

**K8s 资源**：Job（一次性任务，跑完即 Completed）  
**源码位置**：`cmd/ticket-init/main.go` / `java/ticket-init/`  
**HTTP 端点**：无（Job 是 CLI 程序，非 HTTP 服务）  
**K8s 清单**：`k8s/06-ticket-init-job.yaml`

### 业务背景

每个演唱会开售前，需要把 37 万张门票**一次性注入**到数据库和 Redis 缓存。  
这个任务跑完就结束，不需要 7×24 运行。如果用 Deployment 跑，跑完后 Pod 闲置在那浪费资源。

### 执行流程

```
Job 创建 Pod
  │
  ├─ 阶段 1/3：连接主库
  │   → ticket-db-0.ticket-db-svc.ticket-sre.svc.cluster.local:8081
  │
  ├─ 阶段 2/3：注入 6 个城市场馆的门票库存
  │   → 北京鸟巢 91,000 张 ✓
  │   → 上海虹口 35,000 张 ✓
  │   → 广州天河 60,000 张 ✓
  │   → 深圳大运 58,000 张 ✓
  │   → 成都凤凰 50,000 张 ✓
  │   → 杭州奥体 80,000 张 ✓
  │   → 总计: 374,000 张
  │
  └─ 阶段 3/3：Redis 缓存预热
      → exit 0  → Pod 进入 Completed 状态
```

### 关键 K8s 参数

| 参数 | 值 | 含义 |
|------|-----|------|
| `restartPolicy: Never` | — | 失败后不重启容器，由 Job 控制器新建 Pod 重试 |
| `backoffLimit: 3` | — | 最多重试 3 次 |
| `ttlSecondsAfterFinished: 300` | — | 完成后 5 分钟自动删除 Pod |
| `completions: 1` | — | 需要 1 个 Pod 成功完成 |
| `parallelism: 1` | — | 同时只有 1 个 Pod 运行 |

### 测试命令

```bash
# 部署 Job
kubectl apply -f k8s/06-ticket-init-job.yaml

# 查看 Job 状态
kubectl get job ticket-init -n ticket-sre
# COMPLETIONS: 1/1

# 查看 Pod 日志
kubectl logs job/ticket-init -n ticket-sre

# 查看 Pod 最终状态
kubectl get pods -n ticket-sre -l app=ticket-init
# STATUS: Completed ← Job 特有的终态

# 模拟失败重试（修改脚本故意 exit 1）
# 观察 backoffLimit 和重试行为
```

---

## 四、财务对账 — CronJob

**K8s 资源**：CronJob（每天凌晨 2:00 自动执行）  
**源码位置**：`cmd/ticket-settle/main.go` / `java/ticket-settle/`  
**HTTP 端点**：无（CLI 程序）  
**K8s 清单**：`k8s/07-ticket-settle-cronjob.yaml`

### 业务背景

财务部门要求：**每天凌晨 2:00**，系统自动执行以下操作：
1. 拉取微信/支付宝的前一天账单
2. 与数据库订单逐笔对账
3. 生成财务报表并发送邮件到 `finance@ticket-sre.com`

### 执行流程

```
CronJob 在凌晨 2:00 自动创建 Job
  │
  ├─ 阶段 1/3：拉取第三方支付账单
  │   ├─ 微信支付 API → 1,250 条交易
  │   └─ 支付宝 API   →   980 条交易
  │
  ├─ 阶段 2/3：对账比对
  │   ├─ ✅ 匹配成功:   2,180 笔
  │   ├─ ⚠️  金额不匹配:    15 笔 → 标记人工审核
  │   ├─ ↩️  已退款:       35 笔
  │   └─ 🚫 疑似刷票:      5 笔 → 自动冻结
  │
  └─ 阶段 3/3：生成报表 + 发送邮件
      → exit 0 → Job 完成
```

### 关键 K8s 参数

| 参数 | 值 | 含义 |
|------|-----|------|
| `schedule: "0 2 * * *"` | — | 每天凌晨 2:00 |
| `timeZone: Asia/Shanghai` | — | 以上海时区为准 |
| `concurrencyPolicy: Forbid` | — | 上次没跑完就跳过本次（防止对账数据重叠） |
| `startingDeadlineSeconds: 300` | — | 错过调度后 5 分钟内允许补跑 |
| `suspend: false` | — | 设为 true 可暂停（紧急情况） |
| `successfulJobsHistoryLimit: 5` | — | 保留最近 5 次成功记录（审计需要） |
| `failedJobsHistoryLimit: 1` | — | 只保留最近 1 次失败记录 |

### 测试命令

```bash
# 查看 CronJob 配置
kubectl describe cronjob ticket-settle -n ticket-sre

# 手动触发一次（不等凌晨 2:00）
kubectl create job --from=cronjob/ticket-settle ticket-settle-manual -n ticket-sre

# 实时查看日志
kubectl logs job/ticket-settle-manual -n ticket-sre -f

# 查看 CronJob 调度历史
kubectl get jobs -n ticket-sre -l app=ticket-settle

# 测试并发保护
# 第一个 Job 跑 90 秒（模拟），在它跑完前再触发
kubectl create job --from=cronjob/ticket-settle test-1 -n ticket-sre
kubectl create job --from=cronjob/ticket-settle test-2 -n ticket-sre
# 自动调度的 CronJob 会跳过（concurrencyPolicy: Forbid）

# 暂停 CronJob
kubectl patch cronjob ticket-settle -n ticket-sre \
    -p '{"spec":{"suspend":true}}'
# 恢复
kubectl patch cronjob ticket-settle -n ticket-sre \
    -p '{"spec":{"suspend":false}}'
```

---

## 五、K8s 探针与 Workload 决策矩阵

### 三类探针对比

```
                          startupProbe 失败？
                               │
                    ┌──────────┴──────────┐
                    │ YES                 │ NO
                    ▼                     ▼
            不给流量，不杀 Pod       livenessProbe 失败？
         （等待初始化完成）              │
                              ┌──────────┴──────────┐
                              │ YES                 │ NO
                              ▼                     ▼
                         杀 Pod，重建         readinessProbe 失败？
                         （自愈）                   │
                                          ┌──────────┴──────────┐
                                          │ YES                 │ NO
                                          ▼                     ▼
                                    摘除流量，不杀 Pod     正常服务
                                    （保护用户）
```

### Deployment vs StatefulSet vs Job 选型

| 你的服务特征 | 选型 |
|-------------|------|
| 无状态，多副本，频繁发版，快速扩缩 | **Deployment** |
| 有状态，固定身份，独立存储，有序部署 | **StatefulSet** |
| 一次性跑完就结束，不占常驻资源 | **Job** |
| 定时执行，周期重复 | **CronJob** |
| 每个节点都跑一个（日志、监控） | **DaemonSet** |

### 本项目中接口的 K8s 角色

| 服务 | 接口 | 被哪个 K8s 机制使用 | 故障时 K8s 做什么 |
|------|------|---------------------|-------------------|
| ticket-api | `/startup` | startupProbe | 不杀 Pod，不给流量 |
| ticket-api | `/healthz` | livenessProbe | **杀 Pod 重建** |
| ticket-api | `/ready` | readinessProbe | **摘除流量**，不杀 Pod |
| ticket-api | `/buy` | Service 负载均衡 | — |
| ticket-api | `/simulate-deadlock` | 手动触发 | 模拟 livenessProbe 发现死锁 |
| ticket-api | `/simulate-notready` | 手动触发 / preStop Hook | 模拟 readinessProbe 摘流量 |
| ticket-db | `/node-info` | 手动验证 | 证明 StatefulSet 的固定身份 |
| ticket-db | `/order/write` | 业务应用 | 证明主库写入、从库拒绝 |
| ticket-db | `/storage/identity` | 手动验证 | 证明 PVC 持久化绑定 |
| ticket-init | (日志输出) | Job 控制器 | 失败重试，成功 Completed |
| ticket-settle | (日志输出) | CronJob 控制器 | 定时调度，并发保护 |
