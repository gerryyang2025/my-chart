#!/bin/bash

# Helm chart operations and tooling utilities
#
# This script provides convenient commands for helm chart development and deployment.
# It wraps helm with additional functionality like chart pushing and repository syncing.
#
# =============================================================================
# QUICK START
# =============================================================================
#   ./optools.sh helm setup              # First time: install helm and plugin
#   ./optools.sh helm push --dry-run      # Validate chart without pushing
#   ./optools.sh helm push 1.0.0          # Push chart to repository
#
# =============================================================================
# COMMON WORKFLOWS
# =============================================================================
#
# 1. LOCAL DEVELOPMENT / VALIDATION (no cluster needed)
#    - helm lint mychart                  # Check chart syntax
#    - helm template myrelease mychart    # Render and preview YAML
#
# 2. CLUSTER TESTING (requires kubeconfig)
#    - helm install myrelease mychart --dry-run    # Validate against cluster
#    - helm upgrade myrelease mychart --dry-run     # Test upgrade
#
# 3. PUBLISHING
#    - helm push --dry-run                # Validate before push
#    - helm push 1.0.0                   # Push with version
#    - helm push -s 1.1.0-rc1            # Push without repo sync
#
# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================
# Can be set via environment or .env file in project root:
#
#   HELM_REPO_URL       Helm repository URL (e.g. http://helm.example.com/charts/)
#   HELM_REPO_NAME      Repository name (e.g. myrepo)
#   HELM_REPO_USERNAME  Username for repository auth
#   HELM_REPO_PASSWORD  Password for repository auth
#   BCS_SYNC_URL        BCS repo sync trigger URL (optional, triggers index refresh)
#   BCS_SYNC_USERNAME   BCS sync auth username
#   BCS_SYNC_PASSWORD   BCS sync auth password
#
# .env file example (in project root):
#   HELM_REPO_URL=http://helm.example.com/charts/
#   HELM_REPO_NAME=myrepo
#   HELM_REPO_USERNAME=admin
#   HELM_REPO_PASSWORD=secret
#   BCS_SYNC_URL=http://bcs.example.com/bcs/api/.../helm/repositories/sync/
#   BCS_SYNC_USERNAME=admin
#   BCS_SYNC_PASSWORD=secret
#
# =============================================================================
# PASS-THROUGH HELM COMMANDS
# =============================================================================
# Any helm command not explicitly handled will be passed through to helm directly.
# Supported passthrough commands include:
#   lint, template, install, uninstall, upgrade, rollback, history, list,
#   get, show, inspect, pull, package, registry, repo, plugin, search, chart, env, version
#
# Examples:
#   ./optools.sh helm show values mychart
#   ./optools.sh helm pull mychart --untar
#   ./optools.sh helm list
#   ./optools.sh helm history myrelease
#
# =============================================================================

set -e

# ------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
TOOLS_DIR="${PROJECT_ROOT}/tools"
HELM_VERSION="3.14.1"
DEFAULT_VERSION="0.1.0"

# Chart directory (relative to project root)
CHART_DIR="${PROJECT_ROOT}/mychart"

# ------------------------------------------------------------------------
# Environment / .env loading
# ------------------------------------------------------------------------
load_env() {
    local envfile="${PROJECT_ROOT}/.env"
    if [[ -f "${envfile}" ]]; then
        echo "    Loading environment from ${envfile}"
        set -a
        source "${envfile}"
        set +a
    fi
}

# ------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------
show_help() {
    cat <<'EOF'
Helm chart operations and tooling utilities

Usage:
    ./optools.sh helm setup
    ./optools.sh helm create <name> [--generate-name]
    ./optools.sh helm push [--dry-run] [--skip-sync] <chart-version>
    ./optools.sh helm <any-helm-command> [flags] [args]
    ./optools.sh --help / -h

Commands:
    helm setup          Download and install helm and helm-push plugin
    helm create         Scaffold a new chart (wrapper for helm create)
    helm push           Push helm chart to remote repository
    helm <any>          Pass through to helm CLI directly

Arguments:
    name                Chart name to create
    chart-version       Chart version to push (required unless --dry-run).
                        Example: 1.0.0

Options:
    --help / -h         Show this help message and exit.
    --dry-run / -d      Validate chart templates without pushing (push only).
    --skip-sync / -s    Skip the repo sync step after pushing.

Environment variables (or set in .env file in project root):
    HELM_REPO_URL         Helm repository URL
    HELM_REPO_NAME        Helm repository name
    HELM_REPO_USERNAME    Username for helm repo auth
    HELM_REPO_PASSWORD    Password for helm repo auth
    BCS_SYNC_URL          BCS repo sync trigger URL (optional)
    BCS_SYNC_USERNAME     BCS sync auth username
    BCS_SYNC_PASSWORD     BCS sync auth password

Prerequisites:
    - helm plugin 'helm-push' will be installed automatically on first run
    - Helm repository credentials must be valid

Common Examples:

    # Setup / Installation
    ./optools.sh helm setup                              # Install helm and helm-push plugin

    # Chart Creation
    ./optools.sh helm create mychart                     # Create a new chart named 'mychart'

    # Local Validation (no cluster required)
    ./optools.sh helm lint mychart                        # Lint chart for syntax errors
    ./optools.sh helm template myrelease mychart          # Render templates, output YAML
    ./optools.sh helm template myrelease mychart --set image.tag=v1.0  # Render with custom values

    # Dry-run / Validation (requires cluster connection)
    ./optools.sh helm install myrelease mychart --dry-run # Validate install against cluster
    ./optools.sh helm upgrade myrelease mychart --dry-run # Validate upgrade against cluster

    # Push to Repository
    ./optools.sh helm push --dry-run                      # Validate templates, don't push
    ./optools.sh helm push 1.0.0                          # Push chart version 1.0.0
    ./optools.sh helm push --skip-sync 1.0.0              # Push without triggering repo sync
    ./optools.sh helm push -s 2.0.0                       # Short form of --skip-sync

    # Repository Management
    ./optools.sh helm repo list                           # List configured repos
    ./optools.sh helm repo update                         # Update repo index cache
    ./optools.sh helm search repo mychart                 # Search for chart in repos

    # Release Management (requires cluster)
    ./optools.sh helm list                                # List installed releases
    ./optools.sh helm status myrelease                    # Show release status
    ./optools.sh helm history myrelease                   # Show release upgrade history
    ./optools.sh helm uninstall myrelease                 # Uninstall a release

    # Chart Inspection
    ./optools.sh helm show chart mychart                  # Show Chart.yaml contents
    ./optools.sh helm show values mychart                 # Show values.yaml contents
    ./optools.sh helm show all mychart                    # Show Chart.yaml + values.yaml (full details)
    ./optools.sh helm pull mychart                        # Download chart to local directory
EOF
}

setup_helm() {
    # Detect OS and architecture
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64)  ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *)
            echo "ERROR: Unsupported architecture: ${ARCH}" >&2
            exit 1
            ;;
    esac
    if [[ "${OS}" != "linux" && "${OS}" != "darwin" ]]; then
        echo "ERROR: Unsupported OS: ${OS}" >&2
        exit 1
    fi

    # Compute paths at runtime based on detected OS/arch
    HELM_DIR="${TOOLS_DIR}/helm-v${HELM_VERSION}-${OS}-${ARCH}"
    HELM_BIN="${HELM_DIR}/helm"
    export HELM_BIN

    if [[ -x "${HELM_BIN}" ]]; then
        echo "    helm found: $(${HELM_BIN} version --short)"
    else
        echo "==> Setting up helm v${HELM_VERSION} (${OS}/${ARCH}) ..."

        mkdir -p "${HELM_DIR}"

        HELM_ARCHIVE="helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
        HELM_URL="https://get.helm.sh/${HELM_ARCHIVE}"
        HELM_SUBDIR="${HELM_DIR}/${OS}-${ARCH}"

        if [[ ! -f "${HELM_DIR}/${HELM_ARCHIVE}" ]]; then
            echo "    Downloading ${HELM_URL} ..."
            curl -fsSL "${HELM_URL}" -o "${HELM_DIR}/${HELM_ARCHIVE}"
        fi

        if [[ ! -f "${HELM_SUBDIR}/helm" ]]; then
            echo "    Extracting ..."
            tar -xzf "${HELM_DIR}/${HELM_ARCHIVE}" -C "${HELM_DIR}"
            mv "${HELM_SUBDIR}"/* "${HELM_DIR}/"
            rmdir "${HELM_SUBDIR}"
            rm -f "${HELM_DIR}/${HELM_ARCHIVE}"
        fi

        if [[ ! -x "${HELM_BIN}" ]]; then
            echo "ERROR: Failed to setup helm at ${HELM_BIN}" >&2
            exit 1
        fi

        echo "    helm installed: $(${HELM_BIN} version --short)"
    fi

    # Set HELM_PLUGINS to global plugin directory (for cm-push)
    HELM_PLUGINS="${HOME}/Library/helm/plugins"
    export HELM_PLUGINS
}

install_helm_push() {
    if "${HELM_BIN}" cm-push --help >/dev/null 2>&1; then
        return 0
    fi
    echo "==> Installing helm-push plugin ..."
    "${HELM_BIN}" plugin install https://github.com/chartmuseum/helm-push --version 0.10.4 --verify=false 2>/dev/null || {
        echo "    Note: plugin install failed, checking if already installed..."
        if "${HELM_BIN}" cm-push --help >/dev/null 2>&1; then
            return 0
        fi
    }
}

validate_version() {
    local ver="$1"
    if [[ -z "${ver}" ]]; then
        echo "ERROR: Chart version is required." >&2
        echo "Usage: $0 helm push <chart-version>" >&2
        echo "       Example: $0 helm push 1.0.0" >&2
        exit 1
    fi
}

require_env() {
    local var="$1"
    local desc="${2:-${var}}"
    if [[ -z "${!var}" ]]; then
        echo "ERROR: ${desc} is not set. Set it via environment variable or .env file." >&2
        exit 1
    fi
}

# Commands that require Kubernetes cluster connection
CLUSTER_COMMANDS="list|install|uninstall|upgrade|rollback|history|status|get"

check_cluster() {
    if ! "${HELM_BIN}" version --short >/dev/null 2>&1; then
        echo "ERROR: Cannot connect to Kubernetes cluster" >&2
        echo "Please check:" >&2
        echo "  1. kubeconfig is properly configured (kubectl config current-context)" >&2
        echo "  2. Cluster is accessible" >&2
        echo "  3. For local validation, use: helm template" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------
DRY_RUN=false
SKIP_SYNC=false
CHART_VERSION=""
COMMAND=""
HELM_ARGS=()

# Parse helm commands and flags
COMMAND=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        setup)
            COMMAND="helm setup"
            shift
            ;;
        push)
            COMMAND="helm push"
            shift
            ;;
        create)
            COMMAND="helm create"
            shift
            ;;
        --dry-run|--dry|-d)
            DRY_RUN=true
            shift
            ;;
        --skip-sync|--skip|-s)
            SKIP_SYNC=true
            shift
            ;;
        -*)
            # Unknown flag — collect for passthrough
            HELM_ARGS+=("$1")
            shift
            ;;
        helm)
            # Skip 'helm' itself, it's the tool name
            shift
            ;;
        lint|template|install|uninstall|upgrade|rollback|history|list|get|show|inspect|pull|package|registry|repo|plugin|search|chart|env|version|status|help)
            # These are common helm commands - treat as passthrough
            COMMAND="helm"
            HELM_ARGS+=("$1")
            shift
            ;;
        *)
            HELM_ARGS+=("$1")
            shift
            ;;
    esac
done

# ------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------
case "${COMMAND}" in
    "helm setup")
        setup_helm
        install_helm_push
        echo "==> succ: helm and helm-push are ready"
        exit 0
        ;;
    "helm create")
        setup_helm
        # Extract first non-flag arg as chart name
        CHART_NAME=""
        for arg in "${HELM_ARGS[@]}"; do
            if [[ -z "${CHART_NAME}" && ! "${arg}" =~ ^- ]]; then
                CHART_NAME="${arg}"
            fi
        done
        if [[ -z "${CHART_NAME}" ]]; then
            echo "ERROR: chart name is required." >&2
            echo "Usage: $0 helm create <name>" >&2
            echo "       Example: $0 helm create mychart" >&2
            exit 1
        fi

        # Check if chart directory already exists
        if [[ -d "${CHART_NAME}" ]]; then
            echo "ERROR: chart '${CHART_NAME}' already exists at ${CHART_NAME}/" >&2
            echo "Please choose a different name or remove the existing directory." >&2
            exit 1
        fi

        echo "==> Creating chart: ${CHART_NAME}"
        "${HELM_BIN}" create "${CHART_NAME}"
        exit 0
        ;;
    "helm push")
        load_env
        setup_helm

        # Extract chart version from args (first non-flag positional arg)
        CHART_VERSION=""
        REMAINING=()
        for arg in "${HELM_ARGS[@]}"; do
            if [[ -z "${CHART_VERSION}" && ! "${arg}" =~ ^- ]]; then
                CHART_VERSION="${arg}"
            else
                REMAINING+=("${arg}")
            fi
        done
        HELM_ARGS=("${REMAINING[@]}")

        if [[ "${DRY_RUN}" != "true" && -z "${CHART_VERSION}" ]]; then
            validate_version "${CHART_VERSION}"
        fi

        if [[ ! -d "${CHART_DIR}" ]]; then
            echo "ERROR: Chart directory not found: ${CHART_DIR}" >&2
            echo "Create your helm chart at: ${CHART_DIR}" >&2
            exit 1
        fi

        # --dry-run: validate templates without pushing
        if [[ "${DRY_RUN}" == "true" ]]; then
            echo "==> Running dry-run: validating chart ..."

            # Only override version if CHART_VERSION looks like a semver (contains at least one dot)
            # and the override actually differs from current version
            CURRENT_VERSION=$(grep "^version:" "${CHART_DIR}/Chart.yaml" | awk '{print $2}')
            if [[ -n "${CHART_VERSION}" && "${CHART_VERSION}" == *.* && "${CHART_VERSION}" != "${CURRENT_VERSION}" ]]; then
                echo "    Note: chart version will be temporarily set to ${CHART_VERSION} for validation"
                sed -i '' "s/^version:.*/version: ${CHART_VERSION}/" "${CHART_DIR}/Chart.yaml"
            fi

            # Step 1: Lint chart structure
            echo "==> Linting chart structure ..."
            if ! "${HELM_BIN}" lint "${CHART_DIR}" 2>&1; then
                echo "ERROR: chart lint failed" >&2
                if [[ -n "${CURRENT_VERSION}" ]]; then
                    sed -i '' "s/^version:.*/version: ${CURRENT_VERSION}/" "${CHART_DIR}/Chart.yaml"
                fi
                exit 1
            fi

            # Step 2: Render templates
            echo "==> Rendering chart templates ..."
            if ! "${HELM_BIN}" template "${CHART_DIR}" 2>&1; then
                echo "ERROR: chart template render failed" >&2
                if [[ -n "${CURRENT_VERSION}" ]]; then
                    sed -i '' "s/^version:.*/version: ${CURRENT_VERSION}/" "${CHART_DIR}/Chart.yaml"
                fi
                exit 1
            fi

            echo ""
            echo "==> succ: dry-run passed (lint + template render)"
            echo "    Chart is ready to push"

            # Restore original version if we changed it
            if [[ -n "${CURRENT_VERSION}" && "${CHART_VERSION}" == *.* && "${CHART_VERSION}" != "${CURRENT_VERSION}" ]]; then
                sed -i '' "s/^version:.*/version: ${CURRENT_VERSION}/" "${CHART_DIR}/Chart.yaml"
            fi
            exit 0
        fi

        install_helm_push

        cd "${PROJECT_ROOT}"

        # Validate required env vars
        require_env "HELM_REPO_URL" "HELM_REPO_URL"
        require_env "HELM_REPO_NAME" "HELM_REPO_NAME"
        require_env "HELM_REPO_USERNAME" "HELM_REPO_USERNAME"
        require_env "HELM_REPO_PASSWORD" "HELM_REPO_PASSWORD"

        # Preserve original version for restoration after push
        ORIGINAL_VERSION=$(grep "^version:" "${CHART_DIR}/Chart.yaml" | awk '{print $2}')
        if [[ -z "${ORIGINAL_VERSION}" ]]; then
            echo "ERROR: Failed to read original version from ${CHART_DIR}/Chart.yaml" >&2
            exit 1
        fi

        # Temporarily update chart version if requested
        if [[ -n "${CHART_VERSION}" ]]; then
            echo "==> Updating chart version: ${ORIGINAL_VERSION} -> ${CHART_VERSION}"
            sed -i '' "s/^version: ${ORIGINAL_VERSION}/version: ${CHART_VERSION}/" "${CHART_DIR}/Chart.yaml"
        fi

        # Add helm repo if not already present
        if ! "${HELM_BIN}" repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME} "; then
            echo "==> Adding helm repo ${HELM_REPO_NAME} ..."
            "${HELM_BIN}" repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}" \
                --username="${HELM_REPO_USERNAME}" --password="${HELM_REPO_PASSWORD}"
        fi

        echo "==> Updating helm repo index ..."
        "${HELM_BIN}" repo update

        # Push chart directly using cm-push binary (bypasses helm plugin interface)
        echo "==> Pushing chart to ${HELM_REPO_NAME} ..."
        CM_PUSH_BIN="${HOME}/Library/helm/plugins/helm-push/bin/helm-cm-push"
        if [[ ! -x "${CM_PUSH_BIN}" ]]; then
            echo "ERROR: helm-push plugin binary not found at ${CM_PUSH_BIN}" >&2
            exit 1
        fi

        set +e
        PUSH_OUTPUT=$("${CM_PUSH_BIN}" "${CHART_DIR}" "${HELM_REPO_URL}" \
            --username="${HELM_REPO_USERNAME}" --password="${HELM_REPO_PASSWORD}" 2>&1)
        PUSH_EXIT=$?
        set -e

        if [[ "${PUSH_EXIT}" -ne 0 ]]; then
            if echo "${PUSH_OUTPUT}" | grep -q "already exists"; then
                echo "    Note: chart version ${CHART_VERSION} already exists in repo (no changes made)"
                echo "==> Chart is already up to date"
            else
                echo "ERROR: failed to push chart (exit ${PUSH_EXIT}): ${PUSH_OUTPUT}" >&2
                sed -i '' "s/^version: ${CHART_VERSION}/version: ${ORIGINAL_VERSION}/" "${CHART_DIR}/Chart.yaml" 2>/dev/null
                echo "==> Restored original chart version: ${ORIGINAL_VERSION}"
                exit 1
            fi
        fi

        # Trigger repo sync (if configured and not skipped)
        if [[ "${SKIP_SYNC}" != "true" && -n "${BCS_SYNC_URL}" ]]; then
            echo "==> Triggering repo sync ..."
            BCS_AUTH="${BCS_SYNC_USERNAME:-${HELM_REPO_USERNAME}}:${BCS_SYNC_PASSWORD:-${HELM_REPO_PASSWORD}}"
            curl -fsSL -X POST \
                "${BCS_SYNC_URL}" \
                -u "${BCS_AUTH}" \
                -o /dev/null 2>/dev/null \
                || echo "WARNING: repo sync failed (chart was pushed successfully, sync is optional)"
        fi

        # Restore original chart version after push
        if [[ -n "${CHART_VERSION}" ]]; then
            sed -i '' "s/^version: ${CHART_VERSION}/version: ${ORIGINAL_VERSION}/" "${CHART_DIR}/Chart.yaml"
            echo "==> Restored original chart version: ${ORIGINAL_VERSION}"
        fi

        echo ""
        echo "==> succ: chart pushed successfully"
        ;;
    "helm")
        # Pass through arbitrary helm commands
        setup_helm

        # Check cluster connectivity for cluster-dependent commands
        if [[ -n "${HELM_ARGS[*]}" ]]; then
            FIRST_CMD="${HELM_ARGS[0]}"
            if [[ "${FIRST_CMD}" =~ ^(${CLUSTER_COMMANDS})$ ]]; then
                echo "    Checking cluster connection ..."
                if ! check_cluster; then
                    exit 1
                fi
            fi
        fi

        echo "==> Running: helm ${HELM_ARGS[*]}"
        "${HELM_BIN}" "${HELM_ARGS[@]}"
        ;;
    *)
        show_help
        exit 1
        ;;
esac
