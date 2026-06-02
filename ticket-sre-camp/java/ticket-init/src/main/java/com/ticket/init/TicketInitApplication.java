package com.ticket.init;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@SpringBootApplication
public class TicketInitApplication implements CommandLineRunner {

    public static void main(String[] args) {
        SpringApplication.run(TicketInitApplication.class, args);
    }

    @Override
    public void run(String... args) throws Exception {
        Instant startTime = Instant.now();

        System.out.println("══════════════════════════════════════════════");
        System.out.println("[Job] 🏁 ===== 抢票数据初始化任务开始 (Java) =====");
        System.out.printf("[Job] ⏰ 启动时间: %s%n", java.time.LocalDateTime.now());
        System.out.printf("[Job] 🏷️  Pod 名称: %s%n",
                System.getenv().getOrDefault("HOSTNAME", "unknown"));
        System.out.println("══════════════════════════════════════════════");

        // 阶段 1：连接主数据库
        System.out.println("[Job] 📡 阶段 1/3：连接主数据库...");
        System.out.println("[Job] 🔗 连接地址: ticket-db-0.ticket-db-svc.ticket-sre.svc.cluster.local:8081");
        Thread.sleep(2000);
        System.out.println("[Job] ✅ 成功连接主数据库 (ticket-db-0)");

        // 阶段 2：注入门票库存
        System.out.println("[Job] 📥 阶段 2/3：注入「2026天王全球巡回演唱会」门票库存...");

        Map<String, Integer> venues = new LinkedHashMap<>();
        venues.put("北京·鸟巢国家体育场", 91000);
        venues.put("上海·虹口足球场", 35000);
        venues.put("广州·天河体育中心", 60000);
        venues.put("深圳·大运中心", 58000);
        venues.put("成都·凤凰山体育公园", 50000);
        venues.put("杭州·奥体中心", 80000);

        int totalTickets = 0;
        for (Map.Entry<String, Integer> entry : venues.entrySet()) {
            System.out.printf("[Job] ➡️  [%s] 注入 %d 张门票...%n",
                    entry.getKey(), entry.getValue());
            Thread.sleep(800);
            totalTickets += entry.getValue();
        }

        System.out.printf("[Job] ✅ 门票库存注入完成！总计 %d 张门票%n", totalTickets);

        // 阶段 3：预加载缓存
        System.out.println("[Job] 📦 阶段 3/3：预加载 Redis 热点数据缓存...");
        Thread.sleep(2000);
        System.out.println("[Job] ✅ Redis 缓存预热完成");

        long elapsed = Duration.between(startTime, Instant.now()).getSeconds();
        System.out.println("══════════════════════════════════════════════");
        System.out.printf("[Job] 🏆 初始化任务完成！耗时: %ds (Java)%n", elapsed);
        System.out.println("[Job] 💤 任务退出 — Pod 进入 Completed 状态");
        System.out.println("══════════════════════════════════════════════");

        // Spring Boot 正常退出
        System.exit(0);
    }
}
