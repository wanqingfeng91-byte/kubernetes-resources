# ============================================================
# Stage 1: Build Java application with Maven
# ============================================================
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline -B 2>/dev/null || mvn dependency:resolve -B

COPY src ./src
RUN mvn package -DskipTests -B

# ============================================================
# Stage 2: JRE runtime (StatefulSet 数据库)
# ============================================================
FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache tzdata curl && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app
COPY --from=builder /build/target/ticket-db-*.jar app.jar

RUN mkdir -p /data/ticket-db
VOLUME ["/data/ticket-db"]

EXPOSE 8081

HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:8081/healthz || exit 1

ENTRYPOINT ["java", "-XX:+UseZGC", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
