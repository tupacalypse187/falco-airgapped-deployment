#!/bin/bash
# =============================================================================
# Create GitHub Releases for Air-Gapped Falco Deployment
# =============================================================================
# This script downloads all required binaries from upstream sources and
# creates GitHub releases in your repository for air-gapped deployment.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - curl, tar, unzip installed
#   - Docker installed (for plugin extraction)
#
# Usage:
#   ./create-github-releases.sh [OPTIONS]
#
# Options:
#   --skip-falco       Skip Falco binary release
#   --skip-falcoctl    Skip falcoctl release
#   --skip-awscli      Skip AWS CLI release
#   --skip-plugins     Skip plugins release
#   --dry-run          Download only, don't create releases
#   -h, --help         Show this help message
# =============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELEASES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOWNLOAD_DIR="${RELEASES_ROOT}/downloads"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

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
        log_error "Please edit versions.env and set GITHUB_REPO to your repository"
        log_error "Example: GITHUB_REPO=\"myusername/falco-airgapped-deployment\""
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing=()

    command -v gh &>/dev/null || missing+=("gh (GitHub CLI)")
    command -v curl &>/dev/null || missing+=("curl")
    command -v tar &>/dev/null || missing+=("tar")
    command -v unzip &>/dev/null || missing+=("unzip")
    command -v docker &>/dev/null || missing+=("docker")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # Check gh authentication
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI is not authenticated. Run: gh auth login"
        exit 1
    fi

    log_info "  ✓ All prerequisites met"
}

# Clean and prepare download directory
prepare_downloads() {
    log_step "Preparing download directory..."
    rm -rf "${DOWNLOAD_DIR:?}"/*
    mkdir -p "${DOWNLOAD_DIR}"
    log_info "  ✓ Download directory ready: ${DOWNLOAD_DIR}"
}

# =============================================================================
# FALCO BINARY
# =============================================================================
download_falco() {
    log_step "Downloading Falco binary v${FALCO_VERSION}..."

    local falco_dir="${DOWNLOAD_DIR}/falco"
    mkdir -p "${falco_dir}"

    for arch in x86_64 aarch64; do
        local url="https://download.falco.org/packages/bin/${arch}/falco-${FALCO_VERSION}-${arch}.tar.gz"
        local output="${falco_dir}/falco-${FALCO_VERSION}-${arch}.tar.gz"

        log_info "  Downloading for ${arch}..."
        curl -L -o "${output}" "${url}" || {
            log_error "Failed to download Falco for ${arch}"
            return 1
        }
    done

    log_info "  ✓ Falco binaries downloaded"
}

create_falco_release() {
    log_step "Creating Falco GitHub release..."

    local tag="falco-v${FALCO_VERSION}"
    local falco_dir="${DOWNLOAD_DIR}/falco"

    # Check if release already exists
    if gh release view "${tag}" --repo "${GITHUB_REPO}" &>/dev/null; then
        log_warn "  Release ${tag} already exists. Skipping."
        return 0
    fi

    gh release create "${tag}" "${falco_dir}"/* \
        --repo "${GITHUB_REPO}" \
        --title "Falco Binary ${FALCO_VERSION}" \
        --notes "Falco binary packages for air-gapped deployment.

## Assets
- falco-${FALCO_VERSION}-x86_64.tar.gz - Linux x86_64 architecture
- falco-${FALCO_VERSION}-aarch64.tar.gz - Linux ARM64 architecture

## Source
Downloaded from https://download.falco.org/packages/bin/

## Version
Falco ${FALCO_VERSION}"

    log_info "  ✓ Release ${tag} created"
}

# =============================================================================
# FALCOCTL
# =============================================================================
download_falcoctl() {
    log_step "Downloading falcoctl v${FALCOCTL_VERSION}..."

    local falcoctl_dir="${DOWNLOAD_DIR}/falcoctl"
    mkdir -p "${falcoctl_dir}"

    # falcoctl uses amd64/arm64 naming
    for arch in amd64 arm64; do
        local url="https://github.com/falcosecurity/falcoctl/releases/download/v${FALCOCTL_VERSION}/falcoctl_${FALCOCTL_VERSION}_linux_${arch}.tar.gz"
        local output="${falcoctl_dir}/falcoctl_${FALCOCTL_VERSION}_linux_${arch}.tar.gz"

        log_info "  Downloading for ${arch}..."
        curl -L -o "${output}" "${url}" || {
            log_error "Failed to download falcoctl for ${arch}"
            return 1
        }
    done

    # Also download checksums if available
    local checksums_url="https://github.com/falcosecurity/falcoctl/releases/download/v${FALCOCTL_VERSION}/checksums.txt"
    curl -L -o "${falcoctl_dir}/checksums.txt" "${checksums_url}" 2>/dev/null || true

    log_info "  ✓ falcoctl binaries downloaded"
}

create_falcoctl_release() {
    log_step "Creating falcoctl GitHub release..."

    local tag="falcoctl-v${FALCOCTL_VERSION}"
    local falcoctl_dir="${DOWNLOAD_DIR}/falcoctl"

    # Check if release already exists
    if gh release view "${tag}" --repo "${GITHUB_REPO}" &>/dev/null; then
        log_warn "  Release ${tag} already exists. Skipping."
        return 0
    fi

    gh release create "${tag}" "${falcoctl_dir}"/* \
        --repo "${GITHUB_REPO}" \
        --title "falcoctl ${FALCOCTL_VERSION}" \
        --notes "falcoctl CLI tool for air-gapped deployment.

## Assets
- falcoctl_${FALCOCTL_VERSION}_linux_amd64.tar.gz - Linux x86_64 architecture
- falcoctl_${FALCOCTL_VERSION}_linux_arm64.tar.gz - Linux ARM64 architecture
- checksums.txt - SHA256 checksums

## Source
Mirrored from https://github.com/falcosecurity/falcoctl/releases/tag/v${FALCOCTL_VERSION}

## Version
falcoctl ${FALCOCTL_VERSION}"

    log_info "  ✓ Release ${tag} created"
}

# =============================================================================
# AWS CLI
# =============================================================================
download_awscli() {
    log_step "Downloading AWS CLI v2..."

    local awscli_dir="${DOWNLOAD_DIR}/awscli"
    mkdir -p "${awscli_dir}"

    for arch in x86_64 aarch64; do
        local url="https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip"
        local output="${awscli_dir}/awscli-exe-linux-${arch}.zip"

        log_info "  Downloading for ${arch}..."
        curl -L -o "${output}" "${url}" || {
            log_error "Failed to download AWS CLI for ${arch}"
            return 1
        }
    done

    log_info "  ✓ AWS CLI packages downloaded"
}

create_awscli_release() {
    log_step "Creating AWS CLI GitHub release..."

    local tag="${AWSCLI_RELEASE_TAG}"
    local awscli_dir="${DOWNLOAD_DIR}/awscli"

    # Check if release already exists
    if gh release view "${tag}" --repo "${GITHUB_REPO}" &>/dev/null; then
        log_warn "  Release ${tag} already exists. Skipping."
        return 0
    fi

    gh release create "${tag}" "${awscli_dir}"/* \
        --repo "${GITHUB_REPO}" \
        --title "AWS CLI v2" \
        --notes "AWS CLI v2 packages for air-gapped deployment (S3 plugin loader variant).

## Assets
- awscli-exe-linux-x86_64.zip - Linux x86_64 architecture
- awscli-exe-linux-aarch64.zip - Linux ARM64 architecture

## Source
Downloaded from https://awscli.amazonaws.com/

## Note
This is the latest AWS CLI v2 at the time of download."

    log_info "  ✓ Release ${tag} created"
}

# =============================================================================
# PLUGINS
# =============================================================================
extract_plugins() {
    log_step "Extracting Falco plugins..."

    local plugins_dir="${DOWNLOAD_DIR}/plugins"
    mkdir -p "${plugins_dir}"

    # Use falcoctl to download and extract plugins
    local falcoctl_image="falcosecurity/falcoctl:${FALCOCTL_VERSION}"

    log_info "  Pulling falcoctl image..."
    docker pull "${falcoctl_image}"

    # Extract each plugin
    local plugins=(
        "k8saudit-eks:${K8SAUDIT_EKS_VERSION}"
        "k8saudit:${K8SAUDIT_VERSION}"
        "container:${CONTAINER_PLUGIN_VERSION}"
    )

    for plugin_spec in "${plugins[@]}"; do
        local plugin_name="${plugin_spec%%:*}"
        local plugin_version="${plugin_spec##*:}"
        local plugin_ref="ghcr.io/falcosecurity/plugins/plugin/${plugin_name}:${plugin_version}"

        log_info "  Extracting ${plugin_name} v${plugin_version}..."

        # Create temp directory for extraction
        local temp_dir=$(mktemp -d)

        # Use falcoctl to install the plugin
        docker run --rm \
            -v "${temp_dir}:/plugins" \
            "${falcoctl_image}" \
            artifact install "${plugin_ref}" --plugins-dir=/plugins 2>/dev/null || {
            log_warn "  Direct install failed, trying alternative method..."

            # Alternative: pull and extract manually
            docker run --rm \
                -v "${temp_dir}:/plugins" \
                --entrypoint /bin/sh \
                "${falcoctl_image}" \
                -c "falcoctl artifact install ${plugin_ref} --plugins-dir=/plugins" 2>/dev/null || true
        }

        # Find and copy .so files
        find "${temp_dir}" -name "*.so" -exec cp {} "${plugins_dir}/" \; 2>/dev/null || true

        # Rename to include version if not already
        for so_file in "${plugins_dir}"/*.so; do
            if [ -f "${so_file}" ]; then
                local basename=$(basename "${so_file}" .so)
                if [[ ! "${basename}" =~ -[0-9] ]]; then
                    mv "${so_file}" "${plugins_dir}/${basename}-${plugin_version}.so" 2>/dev/null || true
                fi
            fi
        done

        rm -rf "${temp_dir}"
    done

    # Verify plugins were extracted
    if ls "${plugins_dir}"/*.so 1>/dev/null 2>&1; then
        log_info "  ✓ Plugins extracted:"
        ls -la "${plugins_dir}"/*.so
    else
        log_warn "  No plugins extracted via falcoctl, trying project's extract script..."

        # Fallback to project's extract script
        if [ -f "${PROJECT_ROOT}/scripts/local/extract-plugins.sh" ]; then
            bash "${PROJECT_ROOT}/scripts/local/extract-plugins.sh"
            cp "${PROJECT_ROOT}/plugins/extracted/"*.so "${plugins_dir}/" 2>/dev/null || true
        fi

        if ls "${plugins_dir}"/*.so 1>/dev/null 2>&1; then
            log_info "  ✓ Plugins extracted via fallback method"
        else
            log_error "  Failed to extract plugins"
            return 1
        fi
    fi
}

create_plugins_release() {
    log_step "Creating plugins GitHub release..."

    local tag="${PLUGINS_RELEASE_TAG}"
    local plugins_dir="${DOWNLOAD_DIR}/plugins"

    # Check if release already exists
    if gh release view "${tag}" --repo "${GITHUB_REPO}" &>/dev/null; then
        log_warn "  Release ${tag} already exists. Skipping."
        return 0
    fi

    if ! ls "${plugins_dir}"/*.so 1>/dev/null 2>&1; then
        log_error "  No plugin files found to release"
        return 1
    fi

    gh release create "${tag}" "${plugins_dir}"/*.so \
        --repo "${GITHUB_REPO}" \
        --title "Falco Plugins ${PLUGINS_RELEASE_TAG}" \
        --notes "Pre-extracted Falco plugin shared objects for air-gapped deployment.

## Included Plugins
- k8saudit-eks-${K8SAUDIT_EKS_VERSION}.so - Kubernetes audit plugin for AWS EKS
- k8saudit-${K8SAUDIT_VERSION}.so - Generic Kubernetes audit plugin
- container-${CONTAINER_PLUGIN_VERSION}.so - Container metadata enrichment plugin

## Source
Extracted from ghcr.io/falcosecurity/plugins using falcoctl

## Usage
These .so files should be placed in /usr/share/falco/plugins/ in your Falco container."

    log_info "  ✓ Release ${tag} created"
}

# =============================================================================
# MAIN
# =============================================================================
show_help() {
    head -30 "$0" | tail -25
    exit 0
}

main() {
    local skip_falco=false
    local skip_falcoctl=false
    local skip_awscli=false
    local skip_plugins=false
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-falco) skip_falco=true; shift ;;
            --skip-falcoctl) skip_falcoctl=true; shift ;;
            --skip-awscli) skip_awscli=true; shift ;;
            --skip-plugins) skip_plugins=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            -h|--help) show_help ;;
            *) log_error "Unknown option: $1"; show_help ;;
        esac
    done

    echo ""
    log_info "============================================="
    log_info "Create GitHub Releases for Air-Gapped Falco"
    log_info "============================================="
    echo ""

    load_config
    log_info "GitHub Repository: ${GITHUB_REPO}"
    echo ""

    check_prerequisites
    echo ""

    prepare_downloads
    echo ""

    # Falco
    if [ "${skip_falco}" = false ]; then
        download_falco
        if [ "${dry_run}" = false ]; then
            create_falco_release
        fi
        echo ""
    fi

    # falcoctl
    if [ "${skip_falcoctl}" = false ]; then
        download_falcoctl
        if [ "${dry_run}" = false ]; then
            create_falcoctl_release
        fi
        echo ""
    fi

    # AWS CLI
    if [ "${skip_awscli}" = false ]; then
        download_awscli
        if [ "${dry_run}" = false ]; then
            create_awscli_release
        fi
        echo ""
    fi

    # Plugins
    if [ "${skip_plugins}" = false ]; then
        extract_plugins
        if [ "${dry_run}" = false ]; then
            create_plugins_release
        fi
        echo ""
    fi

    log_info "============================================="
    log_info "Complete!"
    log_info "============================================="
    echo ""
    log_info "Created releases in: https://github.com/${GITHUB_REPO}/releases"
    echo ""
    log_info "Next steps:"
    log_info "  1. Verify releases at: https://github.com/${GITHUB_REPO}/releases"
    log_info "  2. Build containers: ./scripts/build-from-releases.sh"
    log_info "  3. Deploy: See README.md for deployment instructions"
    echo ""
}

main "$@"
