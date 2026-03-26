# my-chart

A Helm chart project with an operational toolkit script for common chart operations.

## Prerequisites

- macOS or Linux
- `curl` installed
- Helm repository credentials (for `push` command)

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

## Tools

| File | Description |
|------|-------------|
| `optools.sh` | Helm operations control script |
| `tools/` | Downloaded helm binaries (auto-created on first run) |

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

./optools.sh helm create <name> [--generate-name]
    Scaffold a new Helm chart

./optools.sh helm push [--dry-run] [--skip-sync] <chart-version>
    Validate and push a chart to the remote repository

./optools.sh helm <any-helm-command> [flags] [args]
    Pass through to helm CLI directly

Options:
    --help / -h         Show help message and exit
    --dry-run / -d      Validate templates without pushing
    --skip-sync / -s    Skip the repo sync step after pushing
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
