package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

var (
	isReady   int32
	isHealthy int32
)

// DBNode 表示数据库节点信息
type DBNode struct {
	Hostname string `json:"hostname"`
	Role     string `json:"role"`     // master / slave
	Ordinal  int    `json:"ordinal"`  // Pod 序号，固定不变
	DataDir  string `json:"dataDir"`  // PVC 挂载路径
	Uptime   string `json:"uptime"`
}

var node DBNode
var startTime time.Time

func main() {
	startTime = time.Now()

	// ── 1. 从 StatefulSet 环境获取固定身份 ──────────────────
	// StatefulSet Pod 的主机名格式：{serviceName}-{ordinal}
	hostname, _ := os.Hostname()
	node.Hostname = hostname
	node.DataDir = "/data/ticket-db"

	// 解析 Pod 序号 (StatefulSet 保证序号从 0 开始且稳定不变)
	node.Ordinal = parseOrdinal(hostname)

	// 主从角色：序号 0 为主库，其余为从库
	if node.Ordinal == 0 {
		node.Role = "master"
	} else {
		node.Role = "slave"
	}

	log.Println("══════════════════════════════════════════════")
	log.Printf("[Identity] 🏷️  主机名: %s", node.Hostname)
	log.Printf("[Identity] 📊 Pod 序号: %d (StatefulSet 固定标识)", node.Ordinal)
	log.Printf("[Identity] 👑 角色: %s", node.Role)
	log.Printf("[Identity] 💾 数据目录: %s (PVC)", node.DataDir)
	log.Println("══════════════════════════════════════════════")

	// ── 2. 初始化 PVC 存储 ────────────────────────────────
	if err := os.MkdirAll(node.DataDir, 0755); err != nil {
		log.Fatalf("[Storage] ❌ 无法创建数据目录: %v", err)
	}

	// 写入节点身份文件（重启后仍存在，证明 PVC 持久化）
	identityFile := node.DataDir + "/node-identity.txt"
	existingIdentity := ""
	if data, err := os.ReadFile(identityFile); err == nil {
		existingIdentity = strings.TrimSpace(string(data))
		log.Printf("[Storage] 📄 发现已有身份文件: %s", existingIdentity)
		log.Printf("[Storage] ✅ 证明：Pod 重启后仍绑定同一块 PVC 硬盘！")
	} else {
		content := fmt.Sprintf("hostname=%s role=%s ordinal=%d created=%s",
			node.Hostname, node.Role, node.Ordinal, time.Now().Format(time.RFC3339))
		os.WriteFile(identityFile, []byte(content), 0644)
		log.Printf("[Storage] 📝 首次写入身份文件: %s", identityFile)
	}

	// 写入订单数据文件（模拟数据库持久化）
	ordersFile := node.DataDir + "/orders.dat"
	if _, err := os.Stat(ordersFile); os.IsNotExist(err) {
		os.WriteFile(ordersFile, []byte("# 抢票订单数据\n"), 0644)
		log.Printf("[Storage] 📝 初始化订单文件: %s", ordersFile)
	}

	// ── 3. 启动 HTTP 服务 ──────────────────────────────────
	mux := http.NewServeMux()

	// K8s Liveness Probe
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&isHealthy) == 0 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// K8s Readiness Probe
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&isReady) == 0 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	})

	// 节点信息接口 ─ 展示 StatefulSet 的固定身份
	// 即使 Pod 被删除重建，hostname 和 ordinal 始终不变
	mux.HandleFunc("/node-info", func(w http.ResponseWriter, r *http.Request) {
		node.Uptime = time.Since(startTime).Round(time.Second).String()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(node)
	})

	// 写入订单接口 ─ 模拟数据库写入
	mux.HandleFunc("/order/write", func(w http.ResponseWriter, r *http.Request) {
		if node.Role != "master" {
			w.WriteHeader(http.StatusForbidden)
			json.NewEncoder(w).Encode(map[string]string{
				"status": "error",
				"msg":    fmt.Sprintf("当前节点 [%s] 是 %s，请将写请求发送到主库 ticket-db-0", node.Hostname, node.Role),
			})
			return
		}
		orderData := fmt.Sprintf("order_id=ORD%d timestamp=%s\n",
			time.Now().UnixNano(), time.Now().Format(time.RFC3339))
		f, _ := os.OpenFile(ordersFile, os.O_APPEND|os.O_WRONLY, 0644)
		f.WriteString(orderData)
		f.Close()

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "success",
			"msg":     "订单已写入主库",
			"node":    node.Hostname,
			"written": strings.TrimSpace(orderData),
		})
	})

	// 读取订单接口 ─ 模拟数据库读取（可从主库或从库读）
	mux.HandleFunc("/order/read", func(w http.ResponseWriter, r *http.Request) {
		data, _ := os.ReadFile(ordersFile)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "success",
			"node":    node.Hostname,
			"role":    node.Role,
			"data":    string(data),
			"size":    fmt.Sprintf("%d bytes", len(data)),
		})
	})

	// 读取 PVC 身份文件（证明持久化绑定）
	mux.HandleFunc("/storage/identity", func(w http.ResponseWriter, r *http.Request) {
		data, err := os.ReadFile(identityFile)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(err.Error()))
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		w.Write(data)
	})

	server := &http.Server{Addr: ":8081", Handler: mux}

	go func() {
		time.Sleep(3 * time.Second)
		atomic.StoreInt32(&isHealthy, 1)
		atomic.StoreInt32(&isReady, 1)
		log.Printf("[Init] ✅ %s (%s) 已就绪，开始对外提供服务", node.Hostname, node.Role)
	}()

	go func() {
		log.Printf("[Server] 🎧 数据库服务已监听 :8081")
		if err := server.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("[Server] ❌ 服务异常: %v", err)
		}
	}()

	// ── 优雅下线 ──────────────────────────────────────────
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)
	<-stopChan

	log.Println("[Shutdown] ⚠️  收到 SIGTERM，开始安全关闭数据库连接...")
	atomic.StoreInt32(&isReady, 0)
	// 模拟 fsync 刷盘
	time.Sleep(3 * time.Second)
	log.Println("[Shutdown] ✅ 数据已刷盘，数据库安全退出")
}

// parseOrdinal 从 StatefulSet Pod 的主机名中提取序号
// 例如 ticket-db-0 → 0, ticket-db-1 → 1
func parseOrdinal(hostname string) int {
	parts := strings.Split(hostname, "-")
	if len(parts) > 0 {
		last := parts[len(parts)-1]
		if n, err := strconv.Atoi(last); err == nil {
			return n
		}
	}
	return -1
}
