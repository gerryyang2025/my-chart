# my-chart

A Helm chart project with an operational toolkit script for common chart operations.

## Prerequisites

- macOS or Linux
- `curl` installed
- Helm repository credentials (for `push` command)

## Version Compatibility

This project uses **Helm v3.14.1**. For compatibility with your Kubernetes cluster, please refer to the official [Helm Version Support Policy](https://helm.sh/docs/topics/version_skew/).

> **Note**: It is not recommended to use Helm with a version of Kubernetes that is newer than the version it was compiled against.

## Quick Start

```bash
# Set up helm and helm-push plugin
./optools.sh helm setup

# Create a new chart
./optools.sh helm create mychart

# Validate chart templates (dry-run)
./optools.sh helm push --dry-run

# Push chart to repository
./optools.sh helm push 1.0.0

# Pass arbitrary helm commands through
./optools.sh helm lint mychart
./optools.sh helm template myrelease mychart
./optools.sh helm install myrelease mychart --dry-run
```

## Features

### Automatic Environment Detection

The toolkit automatically detects your operating system and architecture:
- **Supported OS**: macOS (darwin), Linux
- **Supported Architectures**: amd64, arm64

### Helm Setup

Downloads and installs Helm v3.14.1 and the helm-push plugin automatically.

### Chart Validation

- **Dry-run mode**: Complete validation (lint + template render) without pushing to repository
- **Lint**: Check chart structure and syntax
- **Template**: Render and preview YAML manifests
- **Cluster check**: Automatic check for cluster-dependent commands (install, upgrade, list, etc.)

### Safety Checks

- **Duplicate prevention**: Prevents creating charts with existing directory names
- **Version conflict handling**: Detects already-pushed chart versions
- **Cluster connectivity**: Validates Kubernetes connection before cluster commands

## Tools

| File | Description |
|------|-------------|
| `optools.sh` | Helm operations control script |
| `tools/` | Downloaded helm binaries (auto-created on first run) |
| `mychart/` | Default Helm chart directory |

## Configuration

Copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
```

| Variable | Description | Required |
|----------|-------------|----------|
| `HELM_REPO_URL` | Helm repository URL | Yes |
| `HELM_REPO_NAME` | Helm repository name | Yes |
| `HELM_REPO_USERNAME` | Username for repo auth | Yes |
| `HELM_REPO_PASSWORD` | Password for repo auth | Yes |
| `BCS_SYNC_URL` | BCS repo sync trigger URL | No |
| `BCS_SYNC_USERNAME` | BCS sync auth username | No |
| `BCS_SYNC_PASSWORD` | BCS sync auth password | No |

## Usage

```
./optools.sh helm setup
    Download and install helm and helm-push plugin

./optools.sh helm create <name>
    Scaffold a new Helm chart

./optools.sh helm push [--dry-run] [--skip-sync] <chart-version>
    Validate and push a chart to the remote repository

./optools.sh helm <any-helm-command> [flags] [args]
    Pass through to helm CLI directly

Options:
    --help / -h         Show help message and exit
    --dry-run / -d      Validate templates without pushing
    --skip-sync / -s    Skip the repo sync step after pushing

Note:
    Commands requiring cluster connection (install, upgrade, list, etc.)
    will check connectivity before execution

### Passing Flags to Helm

When passing flags to helm through optools, use `--` to prevent optools from intercepting flags:

```bash
./optools.sh helm get -- -h    # Show helm get help (not optools help)
./optools.sh helm install -- --dry-run  # Pass --dry-run to helm
```

`--` is a Unix/Linux convention that tells the shell to treat everything after it as arguments, not options.
```

## Common Workflows

### Local Development / Validation (no cluster needed)

```bash
./optools.sh helm lint mychart                                      # Check chart syntax
./optools.sh helm template myrelease mychart                        # Render all templates
./optools.sh helm template myrelease mychart --set image.tag=v1.0    # Render with custom values
./optools.sh helm template myrelease mychart --show-only templates/deployment.yaml  # Render specific template
./optools.sh helm template myrelease mychart | grep -v '^# Source:'  # Render without source comments

# Multi-document values: multiple -f flags, or a single YAML with --- separators
./optools.sh helm template myrelease mychart -f base.yaml -f dev.yaml  # Multiple files (merged)
./optools.sh helm template myrelease mychart -f values.yaml            # Single file with --- separators
```

### Cluster Testing (requires kubeconfig)

```bash
./optools.sh helm install myrelease mychart --dry-run  # Validate against cluster
./optools.sh helm upgrade myrelease mychart --dry-run # Test upgrade
```

### Publishing

```bash
./optools.sh helm push --dry-run                # Validate before push
./optools.sh helm push 1.0.0                    # Push with version
./optools.sh helm push --skip-sync 1.0.0        # Push without repo sync
./optools.sh helm push -s 1.1.0-rc1             # Short form of --skip-sync
```

## Chart Structure

```
mychart/
├── Chart.yaml                    # Chart metadata (name, version, appVersion)
├── charts/                       # Chart dependencies (subcharts)
├── templates/                    # Kubernetes manifest templates
│   ├── _helpers.tpl              # Reusable template functions and labels
│   ├── deployment.yaml           # Deployment manifest
│   ├── service.yaml              # Service manifest
│   ├── serviceaccount.yaml       # ServiceAccount manifest
│   ├── ingress.yaml              # Ingress manifest (external access)
│   ├── hpa.yaml                  # HorizontalPodAutoscaler manifest
│   ├── httproute.yaml            # HTTPRoute manifest (Gateway API)
│   ├── NOTES.txt                 # Post-install instructions
│   └── tests/                    # Helm test resources
│       └── test-connection.yaml  # Pod connectivity test (helm.sh/hook: test)
├── .helmignore                   # Files to exclude from packaging
└── values.yaml                   # Default configuration values
```

### Template Files

| File | Kind | Description |
|------|------|-------------|
| `_helpers.tpl` | N/A | 定义可复用的模板函数：名称生成、标准标签、ServiceAccount 名 |
| `deployment.yaml` | Deployment | 主应用工作负载，管理 Pod 副本数、容器配置、探针等 |
| `service.yaml` | Service | 内部服务发现，暴露 Deployment 给集群内其他组件 |
| `serviceaccount.yaml` | ServiceAccount | Pod 访问 Kubernetes API 的身份凭证 |
| `ingress.yaml` | Ingress | 外部 HTTP/HTTPS 访问（传统方式） |
| `hpa.yaml` | HorizontalPodAutoscaler | 自动扩缩容，根据 CPU/内存调整副本数 |
| `httproute.yaml` | HTTPRoute | Gateway API 方式暴露服务（现代方式） |
| `NOTES.txt` | N/A | `helm install` 后显示的使用说明 |

### Chart.yaml

```yaml
apiVersion: v2              # Chart API 版本（v2 支持 library charts）
name: mychart               # Chart 名称
description: A Helm chart for Kubernetes
type: application           # chart 类型：application 或 library
version: 1.0.0              # Chart 版本（Semantic Versioning）
appVersion: "1.16.0"        # 实际应用版本
```

### values.yaml

控制模板渲染的默认配置：

| 配置项 | 说明 |
|--------|------|
| `replicaCount` | Pod 副本数，默认 1 |
| `image.repository` | 容器镜像仓库 |
| `image.tag` | 镜像 tag（默认为 appVersion） |
| `image.pullPolicy` | 镜像拉取策略：Always / IfNotPresent / Never |
| `service.type` | Service 类型：ClusterIP / NodePort / LoadBalancer |
| `service.port` | Service 暴露的端口 |
| `ingress.enabled` | 是否启用 Ingress |
| `autoscaling.enabled` | 是否启用 HPA 自动扩缩容 |
| `resources` | 容器 CPU/内存资源限制 |
| `livenessProbe` | 存活探针配置 |
| `readinessProbe` | 就绪探针配置 |

### Labels

所有资源通过 `_helpers.tpl` 注入标准 Kubernetes 标签：

| Label | 来源 |
|-------|------|
| `helm.sh/chart` | Chart name + version |
| `app.kubernetes.io/name` | 应用名称 |
| `app.kubernetes.io/instance` | Helm release 名称 |
| `app.kubernetes.io/version` | 应用版本（appVersion） |
| `app.kubernetes.io/managed-by` | 固定值 `Helm` |

### Chart Dependencies (Subcharts)

Helm 支持两种依赖管理方式：

#### Hard Dependency（硬依赖）

依赖的 chart 文件存储在 `charts/` 目录中，随主 chart 一起打包分发。

**结构**：
```
mychart/
├── Chart.yaml
├── charts/                  # 依赖的 .tgz 包放在这里
│   └── redis-1.0.0.tgz
└── templates/
```

**特点**：
- 安装时自动一起安装所有依赖
- 可离线使用（依赖已打包在本地）
- 打包时 `helm package` 会将 `charts/` 中的依赖一起打包

**使用场景**：紧密耦合的组件，必须同时部署

#### Soft Dependency（软依赖）

依赖信息声明在 `Chart.yaml` 的 `dependencies` 字段中，但 chart 包不存储在本地。

**Chart.yaml 配置**：
```yaml
dependencies:
  - name: redis
    version: "1.0.0"
    repository: "https://charts.bitnami.com"
```

**特点**：
- 依赖从远程仓库动态下载
- 需要先 `helm repo add` 添加仓库
- `helm install` 时自动解析并下载依赖

**安装依赖**：
```bash
./optools.sh helm repo add bitnami https://charts.bitnami.com  # 添加仓库
./optools.sh helm dependency build mychart/                   # 下载依赖到 charts/
```

**使用场景**：运行时依赖、可选组件、用户自行选择实现方式

#### 对比

| 特性 | Hard Dependency | Soft Dependency |
|------|-----------------|-----------------|
| 存储位置 | `charts/` 目录 (.tgz) | 远程仓库 |
| 安装方式 | 自动一起安装 | 动态下载 |
| 离线支持 | 支持 | 不支持（需要缓存） |
| 分发方式 | 打包在一起 | 独立分发 |
| 依赖管理 | 手动放入 | `helm dependency build` |

## License

MIT
