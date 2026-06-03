# ============================================================
# Stage 1: Build Go binary
# ============================================================
FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /ticket-db .

# ============================================================
# Stage 2: 最小运行时镜像
# ============================================================
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app
COPY --from=builder /ticket-db .

# PVC 挂载点
RUN mkdir -p /data/ticket-db
VOLUME ["/data/ticket-db"]

EXPOSE 8081

HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8081/healthz || exit 1

ENTRYPOINT ["./ticket-db"]
