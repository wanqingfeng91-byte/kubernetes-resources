package com.ticket.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

@SpringBootApplication
@RestController
public class TicketApiApplication {

    private static final Instant startTime = Instant.now();
    private static final AtomicBoolean isReady = new AtomicBoolean(false);
    private static final AtomicBoolean isHealthy = new AtomicBoolean(false);
    private static final AtomicBoolean isDeadlock = new AtomicBoolean(false);
    private static final AtomicInteger requestCount = new AtomicInteger(0);

    public static void main(String[] args) {
        System.out.println("══════════════════════════════════════════════");
        System.out.println("[Init] 🚀 抢票API服务启动中 (Java/Spring Boot)...");
        System.out.println("[Init] 📡 正在从配置中心加载 1GB 全国场馆座位数据...");
        System.out.println("[Init] ⏳ 预计需要 30 秒完成数据预热...");
        System.out.println("══════════════════════════════════════════════");

        // 异步预热线程
        Thread warmup = new Thread(() -> {
            try {
                System.out.println("[Init] ⏳ 模拟加载场馆数据 (30秒)...");
                Thread.sleep(30_000);
                isHealthy.set(true);
                isReady.set(true);
                System.out.println("[Init] ✅ 数据预热完成！Service 已就绪");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });
        warmup.setDaemon(true);
        warmup.start();

        SpringApplication.run(TicketApiApplication.class, args);
    }

    // ═══════════════ K8s Startup Probe ═══════════════
    @GetMapping("/startup")
    public ResponseEntity<String> startup() {
        long elapsed = Duration.between(startTime, Instant.now()).getSeconds();
        if (elapsed < 30) {
            System.out.printf("[StartupProbe] ❌ 数据仍在加载 (%ds/30s)...%n", elapsed);
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body("loading venue data...");
        }
        return ResponseEntity.ok("startup complete");
    }

    // ═══════════════ K8s Liveness Probe ═══════════════
    @GetMapping("/healthz")
    public ResponseEntity<String> healthz() {
        if (isDeadlock.get()) {
            System.out.println("[LivenessProbe] 💀 检测到死锁！返回 503");
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body("DEADLOCK DETECTED");
        }
        if (!isHealthy.get()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body("initializing");
        }
        return ResponseEntity.ok("OK");
    }

    // ═══════════════ K8s Readiness Probe ═══════════════
    @GetMapping("/ready")
    public ResponseEntity<String> ready() {
        if (!isReady.get()) {
            System.out.println("[ReadinessProbe] ⚠️ 服务未就绪，临时摘除流量");
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body("not ready");
        }
        return ResponseEntity.ok("ready");
    }

    // ═══════════════ 核心业务：抢票 ═══════════════
    @PostMapping("/buy")
    public ResponseEntity<Map<String, String>> buy() {
        if (isDeadlock.get()) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("status", "error", "msg", "系统繁忙"));
        }
        int count = requestCount.incrementAndGet();
        System.out.printf("[Business] 📥 抢票请求 #%d → 扣减库存 → 锁定座位 → 生成订单...%n", count);
        try { Thread.sleep(2000); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        return ResponseEntity.ok(Map.of(
                "status", "success",
                "msg", "🎉 恭喜！天王演唱会门票抢购成功！",
                "orderId", "ORD-JAVA-" + System.currentTimeMillis()
        ));
    }

    // ═══════════════ 管理接口 ═══════════════
    @PostMapping("/simulate-deadlock")
    public ResponseEntity<Map<String, String>> simulateDeadlock() {
        isDeadlock.set(true);
        System.out.println("[Simulate] 💀 已触发模拟死锁！livenessProbe 将在探测失败后重启 Pod");
        return ResponseEntity.ok(Map.of("status", "ok", "msg", "deadlock simulated"));
    }

    @PostMapping("/simulate-notready")
    public ResponseEntity<Map<String, String>> simulateNotReady() {
        isReady.set(false);
        System.out.println("[Simulate] ⚠️ 已标记 NotReady，Service 将摘除流量");
        return ResponseEntity.ok(Map.of("status", "ok", "msg", "marked not ready"));
    }

    @PostMapping("/recover")
    public ResponseEntity<Map<String, String>> recover() {
        isDeadlock.set(false);
        isReady.set(true);
        System.out.println("[Simulate] ✅ 恢复正常");
        return ResponseEntity.ok(Map.of("status", "ok", "msg", "recovered"));
    }
}
