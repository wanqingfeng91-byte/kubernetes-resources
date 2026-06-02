package com.ticket.db;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.nio.file.*;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;

@SpringBootApplication
@RestController
public class TicketDbApplication {

    private static final Instant startTime = Instant.now();
    private static final AtomicBoolean isReady = new AtomicBoolean(false);
    private static final AtomicBoolean isHealthy = new AtomicBoolean(false);

    private static String hostname;
    private static String role;
    private static int ordinal;
    private static String dataDir = "/data/ticket-db";
    private static Path identityFile;
    private static Path ordersFile;

    public static void main(String[] args) {
        hostname = System.getenv().getOrDefault("HOSTNAME", "unknown");
        dataDir = System.getenv().getOrDefault("DATA_DIR", "/data/ticket-db");
        ordinal = parseOrdinal(hostname);
        role = (ordinal == 0) ? "master" : "slave";

        identityFile = Paths.get(dataDir, "node-identity.txt");
        ordersFile = Paths.get(dataDir, "orders.dat");

        System.out.println("══════════════════════════════════════════════");
        System.out.printf("[Identity] 🏷️  主机名: %s%n", hostname);
        System.out.printf("[Identity] 📊 Pod 序号: %d (StatefulSet 固定)%n", ordinal);
        System.out.printf("[Identity] 👑 角色: %s%n", role);
        System.out.printf("[Identity] 💾 数据目录: %s (PVC)%n", dataDir);
        System.out.println("══════════════════════════════════════════════");

        // 初始化 PVC 存储
        try {
            Files.createDirectories(Paths.get(dataDir));

            if (Files.exists(identityFile)) {
                String existing = Files.readString(identityFile).trim();
                System.out.printf("[Storage] 📄 已有身份: %s%n", existing);
                System.out.println("[Storage] ✅ 证明：Pod 重启后仍绑定同一 PVC 硬盘！");
            } else {
                String content = String.format("hostname=%s role=%s ordinal=%d created=%s (Java)",
                        hostname, role, ordinal, LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
                Files.writeString(identityFile, content);
                System.out.printf("[Storage] 📝 首次写入: %s%n", identityFile);
            }

            if (!Files.exists(ordersFile)) {
                Files.writeString(ordersFile, "# 抢票订单数据 (Java)\n");
                System.out.printf("[Storage] 📝 初始化: %s%n", ordersFile);
            }
        } catch (IOException e) {
            System.err.printf("[Storage] ❌ 错误: %s%n", e.getMessage());
        }

        // 异步就绪
        new Thread(() -> {
            try { Thread.sleep(3000); } catch (InterruptedException ex) { return; }
            isHealthy.set(true);
            isReady.set(true);
            System.out.printf("[Init] ✅ %s (%s) 已就绪%n", hostname, role);
        }).start();

        SpringApplication.run(TicketDbApplication.class, args);
    }

    // ═══════════════ 健康检查 ═══════════════
    @GetMapping("/healthz")
    public ResponseEntity<String> healthz() {
        return isHealthy.get() ? ResponseEntity.ok("OK")
                : ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body("init");
    }

    @GetMapping("/ready")
    public ResponseEntity<String> ready() {
        return isReady.get() ? ResponseEntity.ok("ready")
                : ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body("not ready");
    }

    // ═══════════════ 节点信息 ═══════════════
    @GetMapping("/node-info")
    public ResponseEntity<Map<String, Object>> nodeInfo() {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("hostname", hostname);
        info.put("role", role);
        info.put("ordinal", ordinal);
        info.put("dataDir", dataDir);
        info.put("uptime", Duration.between(startTime, Instant.now()).toSeconds() + "s");
        info.put("language", "Java/Spring Boot");
        return ResponseEntity.ok(info);
    }

    // ═══════════════ 写订单 (仅主库) ═══════════════
    @PostMapping("/order/write")
    public ResponseEntity<Map<String, String>> writeOrder() {
        if (!"master".equals(role)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("status", "error", "msg",
                            "当前节点是 " + role + "，写请求请发送到主库 ticket-db-0"));
        }
        String orderLine = String.format("order_id=ORD-JAVA-%d timestamp=%s%n",
                System.currentTimeMillis(), LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME));
        try {
            Files.writeString(ordersFile, orderLine, StandardOpenOption.APPEND, StandardOpenOption.CREATE);
            return ResponseEntity.ok(Map.of(
                    "status", "success", "msg", "订单已写入主库",
                    "node", hostname, "written", orderLine.trim()
            ));
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("status", "error", "msg", e.getMessage()));
        }
    }

    // ═══════════════ 读订单 ═══════════════
    @GetMapping("/order/read")
    public ResponseEntity<Map<String, String>> readOrders() {
        try {
            String data = Files.readString(ordersFile);
            return ResponseEntity.ok(Map.of(
                    "status", "success", "node", hostname,
                    "role", role, "data", data,
                    "size", data.length() + " bytes"
            ));
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("status", "error", "msg", e.getMessage()));
        }
    }

    // ═══════════════ PVC 身份 ═══════════════
    @GetMapping("/storage/identity")
    public ResponseEntity<String> storageIdentity() {
        try {
            return ResponseEntity.ok(Files.readString(identityFile));
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(e.getMessage());
        }
    }

    private static int parseOrdinal(String hostname) {
        if (hostname == null) return -1;
        String[] parts = hostname.split("-");
        try {
            return Integer.parseInt(parts[parts.length - 1]);
        } catch (NumberFormatException e) {
            return -1;
        }
    }
}
