#!/bin/bash

# Helm chart operations and tooling utilities
#
# Usage:
#   ./optools.sh helm setup
#   ./optools.sh helm create <name> [--generate-name]
#   ./optools.sh helm push [--dry-run] [--skip-sync] <chart-version>
#   ./optools.sh helm <any-helm-command> [flags] [args]
#   ./optools.sh --help / -h
#
# Environment variables (can also be set via .env file in project root):
#   HELM_REPO_URL         Helm repository URL
#   HELM_REPO_NAME        Helm repository name (e.g. myrepo)
#   HELM_REPO_USERNAME    Username for helm repo auth
#   HELM_REPO_PASSWORD    Password for helm repo auth
#   BCS_SYNC_URL          BCS repo sync trigger URL (optional)
#   BCS_SYNC_USERNAME     BCS sync auth username
#   BCS_SYNC_PASSWORD     BCS sync auth password
#
# .env file example (in project root):
#   HELM_REPO_URL=http://helm.example.com/charts/
#   HELM_REPO_NAME=myrepo
#   HELM_REPO_USERNAME=admin
#   HELM_REPO_PASSWORD=secret
#   BCS_SYNC_URL=http://bcs.example.com/bcs/api/.../helm/repositories/sync/
#   BCS_SYNC_USERNAME=admin
#   BCS_SYNC_PASSWORD=secret

set -e

# ------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
TOOLS_DIR="${PROJECT_ROOT}/tools"
HELM_VERSION="4.1.3"
DEFAULT_VERSION="0.1.0"

# Chart directory (relative to project root)
CHART_DIR="${PROJECT_ROOT}/deploy/helm/my-chart"

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

Examples:
    ./optools.sh helm setup
    ./optools.sh helm create mychart
    ./optools.sh helm push --dry-run
    ./optools.sh helm push 1.0.0
    ./optools.sh helm push --skip-sync 1.1.0-rc1
    ./optools.sh helm lint deploy/helm/mychart
    ./optools.sh helm template mychart deploy/helm/mychart
    ./optools.sh helm install myrelease deploy/helm/mychart --dry-run
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
        return 0
    fi

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
}

install_helm_push() {
    if "${HELM_BIN}" plugin list 2>/dev/null | grep -q "^cm-push"; then
        return 0
    fi
    echo "==> Installing helm-push plugin ..."
    "${HELM_BIN}" plugin install https://github.com/chartmuseum/helm-push --verify=false
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

# ------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------
DRY_RUN=false
SKIP_SYNC=false
CHART_VERSION=""
COMMAND=""
HELM_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        helm)
            COMMAND="helm"
            shift
            break
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

# Parse helm subcommands
while [[ $# -gt 0 ]]; do
    case "$1" in
        setup)
            COMMAND="helm setup"
            shift
            break
            ;;
        push)
            COMMAND="helm push"
            shift
            break
            ;;
        create)
            COMMAND="helm create"
            shift
            break
            ;;
        --dry-run|--dry|-d)
            DRY_RUN=true
            shift
            ;;
        --skip-sync|--skip|-s)
            SKIP_SYNC=true
            shift
            ;;
        *)
            HELM_ARGS+=("$1")
            shift
            ;;
    esac
done

# Collect any remaining positional args not handled by the loop above
while [[ $# -gt 0 ]]; do
    HELM_ARGS+=("$1")
    shift
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
        if [[ ${#HELM_ARGS[@]} -eq 0 ]]; then
            echo "ERROR: chart name is required." >&2
            echo "Usage: $0 helm create <name>" >&2
            echo "       Example: $0 helm create mychart" >&2
            exit 1
        fi
        echo "==> Creating chart: ${HELM_ARGS[*]}"
        "${HELM_BIN}" create "${HELM_ARGS[@]}"
        exit 0
        ;;
    "helm push")
        load_env
        setup_helm

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
            echo "==> Running dry-run: validating chart templates ..."

            if [[ -n "${CHART_VERSION}" ]]; then
                echo "    Note: chart version will be temporarily set to ${CHART_VERSION} for validation"
                sed -i "s/^version:.*/version: ${CHART_VERSION}/" "${CHART_DIR}/Chart.yaml"
            fi

            echo "==> Rendering chart templates ..."
            if "${HELM_BIN}" template "${CHART_DIR}" 2>&1; then
                echo ""
                echo "==> succ: dry-run passed, chart templates are valid"
            else
                echo "ERROR: dry-run failed, chart templates have errors" >&2
                sed -i "s/^version:.*/version: ${DEFAULT_VERSION}/" "${CHART_DIR}/Chart.yaml"
                exit 1
            fi

            if [[ -n "${CHART_VERSION}" ]]; then
                sed -i "s/^version:.*/version: ${DEFAULT_VERSION}/" "${CHART_DIR}/Chart.yaml"
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
            sed -i "s/^version: ${ORIGINAL_VERSION}/version: ${CHART_VERSION}/" "${CHART_DIR}/Chart.yaml"
        fi

        # Add helm repo
        echo "==> Adding helm repo ${HELM_REPO_NAME} ..."
        "${HELM_BIN}" repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}" \
            --username="${HELM_REPO_USERNAME}" --password="${HELM_REPO_PASSWORD}" 2>/dev/null || {
            echo "WARNING: repo add failed (may already exist), continuing ..."
        }

        "${HELM_BIN}" repo update

        # Push chart
        echo "==> Pushing chart to ${HELM_REPO_NAME} ..."
        set +e
        PUSH_OUTPUT=$("${HELM_BIN}" cm-push "${CHART_DIR}" "${HELM_REPO_NAME}" 2>&1)
        PUSH_EXIT=$?
        set -e

        if [[ "${PUSH_EXIT}" -ne 0 ]]; then
            if echo "${PUSH_OUTPUT}" | grep -q "409.*already exists"; then
                echo "    Note: chart version ${CHART_VERSION} already exists in repo"
                CHART_VERSION=""  # skip version restore since chart was not newly pushed
            else
                echo "ERROR: failed to push chart (exit ${PUSH_EXIT}): ${PUSH_OUTPUT}" >&2
                sed -i "s/^version: ${CHART_VERSION}/version: ${ORIGINAL_VERSION}/" "${CHART_DIR}/Chart.yaml" 2>/dev/null
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
            sed -i "s/^version: ${CHART_VERSION}/version: ${ORIGINAL_VERSION}/" "${CHART_DIR}/Chart.yaml"
            echo "==> Restored original chart version: ${ORIGINAL_VERSION}"
        fi

        echo ""
        echo "==> succ: chart pushed successfully"
        ;;
    "helm")
        # Pass through arbitrary helm commands
        setup_helm
        echo "==> Running: helm ${HELM_ARGS[*]}"
        "${HELM_BIN}" "${HELM_ARGS[@]}"
        ;;
    *)
        show_help
        exit 1
        ;;
esac
