# ============================================================
# Stage 1: Build Go binary
# ============================================================
FROM golang:1.25-alpine AS builder

WORKDIR /build

# 先复制依赖文件，利用 Docker 缓存层
COPY go.mod go.sum ./
RUN go mod download 2>/dev/null || true

# 复制源码并编译
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /ticket-api .

# ============================================================
# Stage 2: 最小运行时镜像
# ============================================================
FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app
COPY --from=builder /ticket-api .

EXPOSE 8080

# 健康检查 — K8s 会优先使用 Pod spec 中的探针配置，
# 此处的 HEALTHCHECK 用于 docker run 时的快速验证
HEALTHCHECK --interval=5s --timeout=3s --start-period=40s --retries=3 \
    CMD wget -qO- http://localhost:8080/healthz || exit 1

ENTRYPOINT ["./ticket-api"]
