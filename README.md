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
```

## Common Workflows

### Local Development / Validation (no cluster needed)

```bash
./optools.sh helm lint mychart                                      # Check chart syntax
./optools.sh helm template myrelease mychart                        # Render all templates
./optools.sh helm template myrelease mychart --set image.tag=v1.0    # Render with custom values
./optools.sh helm template myrelease mychart --show-only templates/deployment.yaml  # Render specific template
./optools.sh helm template myrelease mychart | grep -v '^# Source:'  # Render without source comments
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
mychart/               # Default chart (scaffolded by helm create)
├── Chart.yaml          # Chart metadata
├── charts/             # Chart dependencies
├── templates/          # Kubernetes manifest templates
└── values.yaml         # Default configuration values
```

## License

MIT
