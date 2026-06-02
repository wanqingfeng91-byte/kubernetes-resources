package com.ticket.settle;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.atomic.AtomicBoolean;

@SpringBootApplication
public class TicketSettleApplication implements CommandLineRunner {

    private static final AtomicBoolean terminated = new AtomicBoolean(false);

    public static void main(String[] args) {
        // 注册 SIGTERM 处理器
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            if (!terminated.get()) {
                System.out.println("[CronJob] ⚠️ 收到终止信号，安全退出...");
                terminated.set(true);
            }
        }));

        SpringApplication.run(TicketSettleApplication.class, args);
    }

    @Override
    public void run(String... args) throws Exception {
        Instant startTime = Instant.now();
        String reportDate = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE);

        System.out.println("══════════════════════════════════════════════");
        System.out.println("[CronJob] 📊 ===== 每日财务对账与报表任务开始 (Java) =====");
        System.out.printf("[CronJob] ⏰ 执行时间: %s%n", LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
        System.out.printf("[CronJob] 🏷️  Pod 名称: %s%n",
                System.getenv().getOrDefault("HOSTNAME", "unknown"));
        System.out.printf("[CronJob] 📅 对账日期: %s (前一天)%n", reportDate);
        System.out.println("══════════════════════════════════════════════");

        // 阶段 1：拉取第三方支付账单
        System.out.println("[CronJob] 📥 阶段 1/3：拉取第三方支付渠道账单...");
        System.out.println("[CronJob] 🔗 正在连接微信支付 API...");
        Thread.sleep(10_000);
        System.out.println("[CronJob] ✅ 微信支付账单拉取完成 (1,250 条记录)");

        System.out.println("[CronJob] 🔗 正在连接支付宝 API...");
        Thread.sleep(10_000);
        System.out.println("[CronJob] ✅ 支付宝账单拉取完成 (980 条记录)");

        // 阶段 2：对账比对
        System.out.println("[CronJob] 🔍 阶段 2/3：执行订单对账比对...");
        System.out.println("[CronJob] 🔗 连接主数据库: ticket-db-0.ticket-db-svc.ticket-sre.svc.cluster.local:8081");
        Thread.sleep(5_000);

        System.out.println("[CronJob] 📊 对账结果：");
        System.out.println("[CronJob]    ✅ 匹配成功: 2,180 笔");
        System.out.println("[CronJob]    ⚠️ 金额不匹配: 15 笔 (已标记人工审核)");
        System.out.println("[CronJob]    ↩️ 已退款: 35 笔");
        System.out.println("[CronJob]    🚫 疑似刷票欺诈: 5 笔 (已自动冻结)");

        // 阶段 3：生成报表
        System.out.println("[CronJob] 📄 阶段 3/3：生成财务报表并发送邮件...");
        Thread.sleep(5_000);

        String report = String.format("""
                {
                  "reportDate": "%s",
                  "totalRevenue": 1284500.00,
                  "totalOrders": 2230,
                  "totalTickets": 4500,
                  "paymentBreakdown": {
                    "wechat": 680000.00,
                    "alipay": 604500.00
                  },
                  "reconciliation": {
                    "matched": 2180,
                    "mismatched": 15,
                    "refunded": 35,
                    "fraudBlocked": 5
                  }
                }""", reportDate);

        System.out.printf("[CronJob] 📋 报表内容:%n%s%n", report);
        System.out.println("[CronJob] 📧 发送报表至: finance@ticket-sre.com...");
        Thread.sleep(2_000);
        System.out.println("[CronJob] ✅ 邮件发送成功！");

        long elapsed = Duration.between(startTime, Instant.now()).getSeconds();
        System.out.println("══════════════════════════════════════════════");
        System.out.printf("[CronJob] 💰 对账完成！总耗时: %ds (Java)%n", elapsed);
        System.out.println("[CronJob] 💤 CronJob Pod 退出 — 等待下次调度");
        System.out.println("══════════════════════════════════════════════");

        System.exit(0);
    }
}
