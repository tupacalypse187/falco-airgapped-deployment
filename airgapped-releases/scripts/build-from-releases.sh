#!/bin/bash
# =============================================================================
# Build Container Images from GitHub Releases
# =============================================================================
# This script builds Falco container images using binaries from your
# GitHub releases (for air-gapped deployment).
#
# Prerequisites:
#   - Docker installed and running
#   - GitHub releases created (run create-github-releases.sh first)
#
# Usage:
#   ./build-from-releases.sh [OPTIONS]
#
# Options:
#   --base-only        Build only the base Falco image
#   --s3-only          Build only the S3 loader image
#   --plugin-only      Build only the plugin loader image
#   --skip-s3          Skip S3 loader image (build base + plugin only)
#   --push             Push to local registry after building
#   --registry URL     Override registry (default: localhost:5000)
#   -h, --help         Show this help message
# =============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKER_DIR="${RELEASES_ROOT}/docker"
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
        log_error "versions.env not found"
        exit 1
    fi

    if [ -z "${GITHUB_REPO}" ]; then
        log_error "GITHUB_REPO is not set in versions.env"
        exit 1
    fi

    # Use registry from args or config
    REGISTRY="${REGISTRY_OVERRIDE:-${LOCAL_REGISTRY:-localhost:5000}}"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker is not running"
        exit 1
    fi

    log_info "  ✓ Docker is available"
}

# Download plugins from release for plugin loader image
download_plugins_from_release() {
    log_step "Downloading plugins from GitHub release..."

    local plugins_dir="${DOWNLOAD_DIR}/plugins-for-build"
    rm -rf "${plugins_dir}"
    mkdir -p "${plugins_dir}"

    # Download plugin .so files from release
    gh release download "${PLUGINS_RELEASE_TAG}" \
        --repo "${GITHUB_REPO}" \
        --pattern "*.so" \
        --dir "${plugins_dir}" || {
        log_error "Failed to download plugins from release ${PLUGINS_RELEASE_TAG}"
        log_error "Run create-github-releases.sh first to create the release"
        exit 1
    }

    log_info "  ✓ Plugins downloaded"
    ls -la "${plugins_dir}"/*.so
}

# Build Falco base image
build_base_image() {
    log_step "Building Falco base image..."

    local image_tag="${REGISTRY}/${IMAGE_PREFIX}/falco:${FALCO_VERSION}-almalinux9"

    log_info "  Image: ${image_tag}"
    log_info "  Using releases from: ${GITHUB_REPO}"

    docker build \
        --build-arg GITHUB_REPO="${GITHUB_REPO}" \
        --build-arg FALCO_VERSION="${FALCO_VERSION}" \
        --build-arg FALCOCTL_VERSION="${FALCOCTL_VERSION}" \
        -t "${image_tag}" \
        -f "${DOCKER_DIR}/Dockerfile" \
        "${DOCKER_DIR}"

    log_info "  ✓ Base image built: ${image_tag}"

    if [ "${DO_PUSH}" = true ]; then
        log_info "  Pushing to registry..."
        docker push "${image_tag}"
        log_info "  ✓ Pushed"
    fi
}

# Build S3 loader image
build_s3_image() {
    log_step "Building Falco S3 loader image..."

    local image_tag="${REGISTRY}/${IMAGE_PREFIX}/falco:${FALCO_VERSION}-s3-almalinux9"

    log_info "  Image: ${image_tag}"
    log_info "  Using releases from: ${GITHUB_REPO}"

    docker build \
        --build-arg GITHUB_REPO="${GITHUB_REPO}" \
        --build-arg FALCO_VERSION="${FALCO_VERSION}" \
        --build-arg FALCOCTL_VERSION="${FALCOCTL_VERSION}" \
        --build-arg AWSCLI_RELEASE_TAG="${AWSCLI_RELEASE_TAG}" \
        -t "${image_tag}" \
        -f "${DOCKER_DIR}/Dockerfile.s3-loader" \
        "${DOCKER_DIR}"

    log_info "  ✓ S3 loader image built: ${image_tag}"

    if [ "${DO_PUSH}" = true ]; then
        log_info "  Pushing to registry..."
        docker push "${image_tag}"
        log_info "  ✓ Pushed"
    fi
}

# Build plugin loader image
build_plugin_loader_image() {
    log_step "Building plugin loader image..."

    download_plugins_from_release

    local image_tag="${REGISTRY}/${IMAGE_PREFIX}/falco-plugin-loader:${PLUGINS_RELEASE_TAG#plugins-}"
    local plugins_dir="${DOWNLOAD_DIR}/plugins-for-build"

    log_info "  Image: ${image_tag}"

    # Create temporary build context with plugins
    local build_context=$(mktemp -d)
    cp "${plugins_dir}"/*.so "${build_context}/"

    # Create Dockerfile for plugin loader
    cat > "${build_context}/Dockerfile" <<'EOF'
FROM alpine:3.19

LABEL description="Falco Plugin Loader - Air-gapped deployment"

# Create plugin directory
RUN mkdir -p /plugins

# Copy plugin .so files
COPY *.so /plugins/

# Create install script
RUN echo '#!/bin/sh' > /usr/local/bin/install-plugins.sh && \
    echo 'DEST="${FALCO_PLUGINS_DIR:-/usr/share/falco/plugins}"' >> /usr/local/bin/install-plugins.sh && \
    echo 'mkdir -p "$DEST"' >> /usr/local/bin/install-plugins.sh && \
    echo 'cp /plugins/*.so "$DEST/"' >> /usr/local/bin/install-plugins.sh && \
    echo 'echo "Plugins installed to $DEST:"' >> /usr/local/bin/install-plugins.sh && \
    echo 'ls -la "$DEST"/*.so' >> /usr/local/bin/install-plugins.sh && \
    chmod +x /usr/local/bin/install-plugins.sh

# Default command copies plugins to target directory
CMD ["/usr/local/bin/install-plugins.sh"]
EOF

    docker build \
        -t "${image_tag}" \
        "${build_context}"

    rm -rf "${build_context}"

    log_info "  ✓ Plugin loader image built: ${image_tag}"

    if [ "${DO_PUSH}" = true ]; then
        log_info "  Pushing to registry..."
        docker push "${image_tag}"
        log_info "  ✓ Pushed"
    fi
}

# Start local registry if needed
start_local_registry() {
    if [[ "${REGISTRY}" == "localhost:5000" ]]; then
        log_step "Ensuring local registry is running..."

        if docker ps | grep -q "registry:2"; then
            log_info "  ✓ Local registry already running"
        else
            log_info "  Starting local registry..."
            docker run -d -p 5000:5000 --restart=always --name registry registry:2 2>/dev/null || \
                docker start registry 2>/dev/null || true
            sleep 2
            log_info "  ✓ Local registry started"
        fi
    fi
}

# =============================================================================
# MAIN
# =============================================================================

show_help() {
    head -25 "$0" | tail -20
    exit 0
}

main() {
    BUILD_BASE=true
    BUILD_S3=true
    BUILD_PLUGIN=true
    DO_PUSH=false
    REGISTRY_OVERRIDE=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --base-only)
                BUILD_S3=false
                BUILD_PLUGIN=false
                shift
                ;;
            --s3-only)
                BUILD_BASE=false
                BUILD_PLUGIN=false
                shift
                ;;
            --plugin-only)
                BUILD_BASE=false
                BUILD_S3=false
                shift
                ;;
            --skip-s3)
                BUILD_S3=false
                shift
                ;;
            --push)
                DO_PUSH=true
                shift
                ;;
            --registry)
                REGISTRY_OVERRIDE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done

    echo ""
    log_info "============================================="
    log_info "Build Images from GitHub Releases"
    log_info "============================================="
    echo ""

    load_config
    log_info "GitHub Repository: ${GITHUB_REPO}"
    log_info "Target Registry: ${REGISTRY}"
    echo ""

    check_prerequisites
    echo ""

    if [ "${DO_PUSH}" = true ]; then
        start_local_registry
        echo ""
    fi

    # Build images
    if [ "${BUILD_BASE}" = true ]; then
        build_base_image
        echo ""
    fi

    if [ "${BUILD_S3}" = true ]; then
        build_s3_image
        echo ""
    fi

    if [ "${BUILD_PLUGIN}" = true ]; then
        build_plugin_loader_image
        echo ""
    fi

    log_info "============================================="
    log_info "Build Complete!"
    log_info "============================================="
    echo ""

    log_info "Built images:"
    if [ "${BUILD_BASE}" = true ]; then
        log_info "  - ${REGISTRY}/${IMAGE_PREFIX}/falco:${FALCO_VERSION}-almalinux9"
    fi
    if [ "${BUILD_S3}" = true ]; then
        log_info "  - ${REGISTRY}/${IMAGE_PREFIX}/falco:${FALCO_VERSION}-s3-almalinux9"
    fi
    if [ "${BUILD_PLUGIN}" = true ]; then
        log_info "  - ${REGISTRY}/${IMAGE_PREFIX}/falco-plugin-loader:${PLUGINS_RELEASE_TAG#plugins-}"
    fi
    echo ""

    log_info "Next steps:"
    log_info "  1. For local testing: bash ../scripts/local/deploy-minikube.sh"
    log_info "  2. For AWS EKS: bash ../scripts/aws/deploy-eks.sh"
    echo ""
}

main "$@"
