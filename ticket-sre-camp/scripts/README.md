# Scripts 脚本说明

`ticket-sre-camp/scripts/` 目录包含项目的构建、部署、测试和环境安装脚本。所有脚本使用 Bash，需要 `set -euo pipefail` 确保错误即停。

---

## 脚本清单

### 环境安装（Ubuntu）

| 脚本 | 用途 | 前置条件 | 典型用法 |
|------|------|----------|----------|
| `setup-ubuntu.sh` | **一键安装**所有开发环境（Go + Java + Maven + Docker + kubectl + Helm + KinD） | Ubuntu 20.04+，海外网络 | `bash scripts/setup-ubuntu.sh` |
| `install-go.sh` | 下载并安装 Go 工具链到 `/usr/local/go`，配置 GOROOT/GOPATH | curl, tar | `bash scripts/install-go.sh` |
| `install-java.sh` | 通过 Adoptium APT 仓库安装 Eclipse Temurin JDK + Apache Maven | apt-get, wget | `bash scripts/install-java.sh` |
| `install-k8s-tools.sh` | 安装 Docker Engine + kubectl + Helm + KinD（可选 k9s） | apt-get, curl | `bash scripts/install-k8s-tools.sh` |

**setup-ubuntu.sh 参数：**

```bash
bash scripts/setup-ubuntu.sh                # 全部安装（默认）
bash scripts/setup-ubuntu.sh --skip-docker   # 跳过 Docker / kubectl
bash scripts/setup-ubuntu.sh --skip-go       # 跳过 Go
bash scripts/setup-ubuntu.sh --skip-java     # 跳过 Java + Maven
bash scripts/setup-ubuntu.sh --only-go       # 仅安装 Go
bash scripts/setup-ubuntu.sh --only-java     # 仅安装 Java + Maven
bash scripts/setup-ubuntu.sh --only-k8s      # 仅安装 Docker / kubectl
```

**环境变量（安装脚本）：**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `GO_VERSION` | `1.22.0` | 要安装的 Go 版本 |
| `JAVA_VERSION` | `21` | 要安装的 Java 主版本号 |
| `MAVEN_VERSION` | `3.9.9` | 要安装的 Maven 版本 |
| `NONINTERACTIVE` | `0` | 设为 `1` 跳过交互式确认（CI 环境用） |

### 构建

| 脚本 | 用途 | 前置条件 | 输出 |
|------|------|----------|------|
| `build-go.sh` | 编译所有 Go 微服务，交叉编译为 Linux amd64 二进制 | Go 工具链 | `bin/${svc}-go` |
| `build-java.sh` | 编译所有 Java 微服务（`mvn clean package`） | JDK 21+, Maven | `java/${svc}/target/*.jar` |
| `build-images.sh` | 构建所有微服务的 Docker 镜像 | Docker, 已编译产物 | Docker 镜像 |

**build-images.sh 环境变量：**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOCKER_REGISTRY` | `ticket-sre` | 镜像仓库前缀 |
| `IMAGE_TAG` | `latest` | 镜像标签 |

### 部署与验证

| 脚本 | 用途 | 前置条件 |
|------|------|----------|
| `deploy.sh` | 按 namespace → ConfigMap → Kustomize 顺序部署全部资源到 K8s | kubectl 已配置，k8s/ 清单完整 |
| `verify-k8s.sh` | Dry-run 校验 YAML + kustomize build + 查询集群资源状态（只读不部署） | kubectl 已配置 |

### 测试

| 脚本 | 用途 | 前置条件 |
|------|------|----------|
| `test.sh` | 端到端集成测试，覆盖 API、数据库读写分离、Job/CronJob、探针、PVC | 已通过 deploy.sh 部署 |

---

## 典型工作流

```bash
# 1. 首次使用：一键安装所有开发工具
bash scripts/setup-ubuntu.sh

# 2. 编译所有服务
bash scripts/build-go.sh
bash scripts/build-java.sh

# 3. 构建 Docker 镜像
bash scripts/build-images.sh

# 4. 部署到 K8s
bash scripts/deploy.sh

# 5. 验证部署
bash scripts/verify-k8s.sh

# 6. 运行集成测试
bash scripts/test.sh
```

---

## 修复记录（2026-06-03）

本批脚本的修复内容：

1. **路径修复** — `build-go.sh` 和 `build-images.sh` 中 Go 服务路径从 `cmd/` 修正为 `go/`（与实际目录结构一致）
2. **版本修复** — `install-go.sh` 默认 Go 版本从 `1.25.1`（不存在）修正为 `1.22.0`；`install-java.sh` 默认 Java 版本从 `25`（不存在）修正为 `21`
3. **兼容性修复** — `grep -oP`（GNU 特有）改为 POSIX 兼容的 `awk` 提取方式，`sha256sum` 增加 macOS `shasum` 回退
4. **CI 兼容** — `install-java.sh` 和 `install-k8s-tools.sh` 的交互式 `read` 增加 `NONINTERACTIVE=1` 跳过机制
5. **镜像修复** — `test.sh` 中 `alpine/curl:latest`（不存在）修正为 `curlimages/curl:latest`
6. **废弃标志** — `kubectl version --short` 移除，新版 kubectl 直接使用 `kubectl version --client`
7. **健壮性** — `setup-ubuntu.sh` 增加 `lsb_release` 缺失时的回退逻辑
8. **文档补充** — 所有脚本头部增加了中文用途说明、前置条件、用法示例
