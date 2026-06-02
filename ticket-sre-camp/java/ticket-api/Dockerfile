# ============================================================
# Stage 1: Build Java application with Maven
# ============================================================
FROM maven:3.9-eclipse-temurin-25 AS builder

WORKDIR /build
COPY pom.xml .
# 先下载依赖，利用 Docker 缓存
RUN mvn dependency:go-offline -B 2>/dev/null || mvn dependency:resolve -B

COPY src ./src
RUN mvn package -DskipTests -B

# ============================================================
# Stage 2: JRE runtime
# ============================================================
FROM eclipse-temurin:25-jre-alpine

RUN apk add --no-cache tzdata curl && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app
COPY --from=builder /build/target/ticket-api-*.jar app.jar

EXPOSE 8080

HEALTHCHECK --interval=5s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -sf http://localhost:8080/healthz || exit 1

ENTRYPOINT ["java", "-XX:+UseZGC", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
