package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

var (
	isReady    int32
	isHealthy  int32
	isDeadlock int32
	startTime  time.Time
)

func main() {
	startTime = time.Now()
	log.Println("══════════════════════════════════════════════")
	log.Println("[Init] 🚀 抢票API服务启动中...")
	log.Println("[Init] 📡 正在从配置中心加载 1GB 全国场馆座位数据...")
	log.Println("[Init] ⏳ 预计需要 30 秒完成数据预热...")
	log.Println("══════════════════════════════════════════════")

	mux := http.NewServeMux()

	// ── K8s Startup Probe ──────────────────────────────────
	// 用于检测容器是否完成启动初始化。
	// 在 startupProbe 成功之前，livenessProbe 和 readinessProbe 不会被调用。
	mux.HandleFunc("/startup", func(w http.ResponseWriter, r *http.Request) {
		elapsed := time.Since(startTime)
		if elapsed < 30*time.Second {
			log.Printf("[StartupProbe] ❌ 数据仍在加载中 (已耗时 %.0fs / 30s)...", elapsed.Seconds())
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("loading venue data..."))
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("startup complete"))
	})

	// ── K8s Liveness Probe ─────────────────────────────────
	// 用于检测容器是否还"活着"。如果进程死锁，返回 503，K8s 会重启 Pod。
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&isDeadlock) == 1 {
			log.Println("[LivenessProbe] 💀 检测到死锁！返回 503，K8s 将重启此 Pod")
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("DEADLOCK DETECTED"))
			return
		}
		if atomic.LoadInt32(&isHealthy) == 0 {
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("initializing"))
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	// ── K8s Readiness Probe ────────────────────────────────
	// 用于检测容器是否可以接收流量。当返回非 200 时，Service 不会将流量路由到此 Pod。
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&isReady) == 0 {
			log.Println("[ReadinessProbe] ⚠️  服务未就绪，暂时从 Service 摘除")
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("not ready"))
			return
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	})

	// ── 核心业务接口：抢票 ────────────────────────────────
	mux.HandleFunc("/buy", func(w http.ResponseWriter, r *http.Request) {
		if atomic.LoadInt32(&isDeadlock) == 1 {
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(`{"status":"error","msg":"系统繁忙"}`))
			return
		}
		log.Println("[Business] 📥 收到抢票请求 → 扣减库存 → 锁定座位 → 生成订单...")
		time.Sleep(2 * time.Second)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"success","msg":"🎉 恭喜！天王演唱会门票抢购成功！","orderId":"ORD20260602001"}`))
	})

	// ── 管理接口：模拟故障场景 ────────────────────────────
	mux.HandleFunc("/simulate-deadlock", func(w http.ResponseWriter, r *http.Request) {
		atomic.StoreInt32(&isDeadlock, 1)
		log.Println("[Simulate] 💀 已触发模拟死锁！/healthz 将返回 503，等待 K8s livenessProbe 重启")
		w.Write([]byte(`{"status":"ok","msg":"deadlock simulated, livenessProbe will restart pod in ~30s"}`))
	})

	mux.HandleFunc("/simulate-notready", func(w http.ResponseWriter, r *http.Request) {
		atomic.StoreInt32(&isReady, 0)
		log.Println("[Simulate] ⚠️  已标记为 NotReady，K8s Service 将摘除流量")
		w.Write([]byte(`{"status":"ok","msg":"marked not ready, traffic will be drained"}`))
	})

	mux.HandleFunc("/recover", func(w http.ResponseWriter, r *http.Request) {
		atomic.StoreInt32(&isDeadlock, 0)
		atomic.StoreInt32(&isReady, 1)
		log.Println("[Simulate] ✅ 已恢复正常状态")
		w.Write([]byte(`{"status":"ok","msg":"recovered"}`))
	})

	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	// ── 异步完成数据预热 ──────────────────────────────────
	go func() {
		log.Println("[Init] ⏳ 模拟加载场馆数据 (30秒)...")
		time.Sleep(30 * time.Second)
		atomic.StoreInt32(&isHealthy, 1)
		atomic.StoreInt32(&isReady, 1)
		log.Println("[Init] ✅ 数据预热完成！startupProbe → 成功，readinessProbe → Ready")
	}()

	// ── 启动 HTTP 服务 ────────────────────────────────────
	go func() {
		log.Println("[Server] 🎧 抢票API已监听 :8080")
		if err := server.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("[Server] ❌ 服务异常: %v", err)
		}
	}()

	// ── K8s 优雅下线 (Graceful Shutdown) ─────────────────
	// preStop Hook 会先执行 sleep 15s，然后 K8s 才发送 SIGTERM
	// 这段时间内 readinessProbe 已经失败，Service 不再转发新请求
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	<-stopChan
	log.Println("──────────────────────────────────────────────────")
	log.Println("[Shutdown] ⚠️  收到 SIGTERM 信号！")
	log.Println("[Shutdown] 📋 preStop Hook 已让 Service 摘除本 Pod 流量")
	log.Println("[Shutdown] ⏳ 等待 15 秒以处理完在途请求...")
	log.Println("──────────────────────────────────────────────────")

	// 立即标记 NotReady
	atomic.StoreInt32(&isReady, 0)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Printf("[Shutdown] ❌ 强制退出: %v", err)
		os.Exit(1)
	}
	log.Println("[Shutdown] ✅ 所有在途请求已处理完毕，安全退出")
}
