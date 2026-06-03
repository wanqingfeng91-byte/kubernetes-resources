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
# Stage 2: JRE runtime (CronJob 定时任务)
# ============================================================
FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app
COPY --from=builder /build/target/ticket-settle-*.jar app.jar

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]
