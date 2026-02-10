#!/bin/bash
# =============================================================================
# Sync Upstream Releases for Air-Gapped Falco Deployment
# =============================================================================
# This script checks for new upstream releases and syncs them to your
# GitHub repository for air-gapped deployment.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - curl, jq installed
#   - Docker installed (for plugin extraction and building)
#
# Usage:
#   ./sync-upstream-releases.sh [OPTIONS]
#
# Options:
#   --check-only       Only check for updates, don't download or create releases
#   --build            After syncing, rebuild container images
#   --component NAME   Only sync specific component (falco, falcoctl, plugins)
#   -h, --help         Show this help message
# =============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_update() { echo -e "${CYAN}[UPDATE]${NC} $1"; }

# Load configuration
load_config() {
    if [ -f "${RELEASES_ROOT}/versions.env" ]; then
        source "${RELEASES_ROOT}/versions.env"
    else
        log_error "versions.env not found at ${RELEASES_ROOT}/versions.env"
        exit 1
    fi

    if [ -z "${GITHUB_REPO}" ]; then
        log_error "GITHUB_REPO is not set in versions.env"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing=()

    command -v gh &>/dev/null || missing+=("gh (GitHub CLI)")
    command -v curl &>/dev/null || missing+=("curl")
    command -v jq &>/dev/null || missing+=("jq")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI is not authenticated. Run: gh auth login"
        exit 1
    fi

    log_info "  ✓ All prerequisites met"
}

# =============================================================================
# VERSION CHECKING
# =============================================================================

# Get latest Falco version from upstream
get_latest_falco_version() {
    gh release list --repo falcosecurity/falco --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null | sed 's/^v//'
}

# Get latest falcoctl version from upstream
get_latest_falcoctl_version() {
    gh release list --repo falcosecurity/falcoctl --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null | sed 's/^v//'
}

# Get your current Falco release version
get_current_falco_version() {
    gh release list --repo "${GITHUB_REPO}" --json tagName -q '.[] | select(.tagName | startswith("falco-v")) | .tagName' 2>/dev/null | head -1 | sed 's/falco-v//'
}

# Get your current falcoctl release version
get_current_falcoctl_version() {
    gh release list --repo "${GITHUB_REPO}" --json tagName -q '.[] | select(.tagName | startswith("falcoctl-v")) | .tagName' 2>/dev/null | head -1 | sed 's/falcoctl-v//'
}

# Compare versions (returns 0 if v1 > v2)
version_gt() {
    local v1="$1"
    local v2="$2"

    if [ -z "$v2" ]; then
        return 0  # No current version means upstream is newer
    fi

    # Use sort -V for version comparison
    local highest=$(echo -e "${v1}\n${v2}" | sort -V | tail -1)
    [ "$highest" = "$v1" ] && [ "$v1" != "$v2" ]
}

# =============================================================================
# SYNC FUNCTIONS
# =============================================================================

sync_falco() {
    log_step "Checking Falco versions..."

    local upstream_version=$(get_latest_falco_version)
    local current_version=$(get_current_falco_version)

    log_info "  Upstream: ${upstream_version:-unknown}"
    log_info "  Current:  ${current_version:-none}"

    if [ -z "${upstream_version}" ]; then
        log_warn "  Could not determine upstream Falco version"
        return 1
    fi

    if version_gt "${upstream_version}" "${current_version}"; then
        log_update "  New version available: ${upstream_version}"

        if [ "${CHECK_ONLY}" = true ]; then
            UPDATES_AVAILABLE=true
            return 0
        fi

        # Update versions.env
        sed -i.bak "s/^FALCO_VERSION=.*/FALCO_VERSION=\"${upstream_version}\"/" "${RELEASES_ROOT}/versions.env"

        # Download and create release
        log_info "  Downloading Falco ${upstream_version}..."
        FALCO_VERSION="${upstream_version}" "${SCRIPT_DIR}/create-github-releases.sh" \
            --skip-falcoctl --skip-awscli --skip-plugins

        UPDATES_SYNCED=true
        log_info "  ✓ Falco ${upstream_version} synced"
    else
        log_info "  ✓ Falco is up to date"
    fi
}

sync_falcoctl() {
    log_step "Checking falcoctl versions..."

    local upstream_version=$(get_latest_falcoctl_version)
    local current_version=$(get_current_falcoctl_version)

    log_info "  Upstream: ${upstream_version:-unknown}"
    log_info "  Current:  ${current_version:-none}"

    if [ -z "${upstream_version}" ]; then
        log_warn "  Could not determine upstream falcoctl version"
        return 1
    fi

    if version_gt "${upstream_version}" "${current_version}"; then
        log_update "  New version available: ${upstream_version}"

        if [ "${CHECK_ONLY}" = true ]; then
            UPDATES_AVAILABLE=true
            return 0
        fi

        # Update versions.env
        sed -i.bak "s/^FALCOCTL_VERSION=.*/FALCOCTL_VERSION=\"${upstream_version}\"/" "${RELEASES_ROOT}/versions.env"

        # Download and create release
        log_info "  Downloading falcoctl ${upstream_version}..."
        FALCOCTL_VERSION="${upstream_version}" "${SCRIPT_DIR}/create-github-releases.sh" \
            --skip-falco --skip-awscli --skip-plugins

        UPDATES_SYNCED=true
        log_info "  ✓ falcoctl ${upstream_version} synced"
    else
        log_info "  ✓ falcoctl is up to date"
    fi
}

sync_plugins() {
    log_step "Checking plugin versions..."

    # Plugins don't have a simple "latest" API, so we check known plugin repos
    # For now, just report current versions

    log_info "  k8saudit-eks: ${K8SAUDIT_EKS_VERSION}"
    log_info "  k8saudit: ${K8SAUDIT_VERSION}"
    log_info "  container: ${CONTAINER_PLUGIN_VERSION}"
    log_info ""
    log_info "  To check for plugin updates, visit:"
    log_info "    https://github.com/falcosecurity/plugins/releases"
    log_info ""
    log_info "  Then update versions.env and run:"
    log_info "    ./create-github-releases.sh --skip-falco --skip-falcoctl --skip-awscli"
}

# =============================================================================
# MAIN
# =============================================================================

show_help() {
    head -25 "$0" | tail -20
    exit 0
}

main() {
    CHECK_ONLY=false
    DO_BUILD=false
    COMPONENT=""
    UPDATES_AVAILABLE=false
    UPDATES_SYNCED=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-only) CHECK_ONLY=true; shift ;;
            --build) DO_BUILD=true; shift ;;
            --component) COMPONENT="$2"; shift 2 ;;
            -h|--help) show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done

    echo ""
    log_info "============================================="
    log_info "Sync Upstream Releases"
    log_info "============================================="
    echo ""

    load_config
    log_info "GitHub Repository: ${GITHUB_REPO}"
    echo ""

    check_prerequisites
    echo ""

    # Sync components
    case "${COMPONENT}" in
        falco)
            sync_falco
            ;;
        falcoctl)
            sync_falcoctl
            ;;
        plugins)
            sync_plugins
            ;;
        "")
            sync_falco
            echo ""
            sync_falcoctl
            echo ""
            sync_plugins
            ;;
        *)
            log_error "Unknown component: ${COMPONENT}"
            log_error "Valid components: falco, falcoctl, plugins"
            exit 1
            ;;
    esac

    echo ""

    # Summary
    if [ "${CHECK_ONLY}" = true ]; then
        if [ "${UPDATES_AVAILABLE}" = true ]; then
            log_update "Updates available! Run without --check-only to sync."
        else
            log_info "All components are up to date."
        fi
    else
        if [ "${UPDATES_SYNCED}" = true ]; then
            log_info "============================================="
            log_info "Updates synced!"
            log_info "============================================="

            # Build if requested
            if [ "${DO_BUILD}" = true ]; then
                echo ""
                log_step "Building container images with new versions..."
                "${SCRIPT_DIR}/build-from-releases.sh"
            else
                echo ""
                log_info "To build containers with new versions:"
                log_info "  ./scripts/build-from-releases.sh"
            fi
        else
            log_info "No updates needed. All components are current."
        fi
    fi
    echo ""
}

main "$@"
