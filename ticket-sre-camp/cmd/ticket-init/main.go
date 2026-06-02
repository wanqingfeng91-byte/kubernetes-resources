package main

import (
	"log"
	"os"
	"time"
)

func main() {
	startTime := time.Now()

	log.Println("══════════════════════════════════════════════")
	log.Println("[Job] 🏁 ===== 抢票数据初始化任务开始 =====")
	log.Printf("[Job] ⏰ 启动时间: %s", startTime.Format(time.RFC3339))
	log.Printf("[Job] 🏷️  Pod 名称: %s", os.Getenv("HOSTNAME"))
	log.Println("══════════════════════════════════════════════")

	// ── 阶段 1：连接主数据库 ──────────────────────────────
	log.Println("[Job] 📡 阶段 1/3：连接主数据库...")
	log.Println("[Job] 🔗 连接地址: ticket-db-0.ticket-db-svc.ticket-sre.svc.cluster.local:8081")
	time.Sleep(2 * time.Second)
	log.Println("[Job] ✅ 成功连接主数据库 (ticket-db-0)")

	// ── 阶段 2：注入演唱会门票库存 ────────────────────────
	log.Println("[Job] 📥 阶段 2/3：注入「2026天王全球巡回演唱会」门票库存...")

	venues := map[string]int{
		"北京·鸟巢国家体育场": 91000,
		"上海·虹口足球场":   35000,
		"广州·天河体育中心":  60000,
		"深圳·大运中心":     58000,
		"成都·凤凰山体育公园": 50000,
		"杭州·奥体中心":     80000,
	}

	totalTickets := 0
	for venue, capacity := range venues {
		log.Printf("[Job] ➡️  [%s] 注入 %d 张门票...", venue, capacity)
		time.Sleep(800 * time.Millisecond)
		totalTickets += capacity
	}

	log.Printf("[Job] ✅ 门票库存注入完成！总计 %d 张门票", totalTickets)

	// ── 阶段 3：预加载 Redis 缓存 ─────────────────────────
	log.Println("[Job] 📦 阶段 3/3：预加载 Redis 热点数据缓存...")
	time.Sleep(2 * time.Second)
	log.Println("[Job] ✅ Redis 缓存预热完成 (热门场次前 5000 张票已加载)")

	// ── 任务完成 ──────────────────────────────────────────
	elapsed := time.Since(startTime)
	log.Println("══════════════════════════════════════════════")
	log.Printf("[Job] 🏆 初始化任务全部完成！耗时: %s", elapsed.Round(time.Second))
	log.Println("[Job] 💤 任务退出 (exit 0) — Pod 将进入 Completed 状态")
	log.Println("══════════════════════════════════════════════")

	// Job 正常退出，K8s 会将 Pod 标记为 Completed
	os.Exit(0)
}
