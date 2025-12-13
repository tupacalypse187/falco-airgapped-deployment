#!/bin/bash
# Local Build Script for Falco Air-Gapped Deployment
# Compatible with Windows 11 (Git Bash/WSL) and Mac Mini 2018
# Requires: Docker Desktop, Minikube

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCAL_REGISTRY="localhost:5000"
FALCO_VERSION="0.42.1"
PLUGIN_LOADER_VERSION="1.0.0"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        log_error "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
    log_info "  ✓ Docker found: $(docker --version)"
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running"
        log_error "Please start Docker Desktop"
        exit 1
    fi
    log_info "  ✓ Docker is running"
    
    # Check Minikube
    if ! command -v minikube &> /dev/null; then
        log_warn "  ⚠ Minikube is not installed"
        log_warn "  Install from: https://minikube.sigs.k8s.io/docs/start/"
        log_warn "  Skipping Minikube checks..."
    else
        log_info "  ✓ Minikube found: $(minikube version --short)"
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_warn "  ⚠ kubectl is not installed"
        log_warn "  Install from: https://kubernetes.io/docs/tasks/tools/"
    else
        log_info "  ✓ kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    fi
    
    # Check Helm
    if ! command -v helm &> /dev/null; then
        log_warn "  ⚠ Helm is not installed"
        log_warn "  Install from: https://helm.sh/docs/intro/install/"
    else
        log_info "  ✓ Helm found: $(helm version --short)"
    fi
}

# Start local registry
start_local_registry() {
    log_step "Starting local Docker registry..."
    
    if docker ps | grep -q "registry:2"; then
        log_info "  Local registry is already running"
    else
        log_info "  Starting registry container..."
        docker run -d -p 5000:5000 --restart=always --name registry registry:2 || {
            log_warn "  Registry container may already exist, trying to start it..."
            docker start registry || log_error "Failed to start registry"
        }
        sleep 2
        log_info "  ✓ Local registry started at ${LOCAL_REGISTRY}"
    fi
}

# Extract plugins
extract_plugins() {
    log_step "Extracting Falco plugins..."
    
    cd "${PROJECT_ROOT}"
    
    if [ ! -f "scripts/local/extract-plugins.sh" ]; then
        log_error "Plugin extraction script not found!"
        exit 1
    fi
    
    log_info "  Running plugin extraction script..."
    bash scripts/local/extract-plugins.sh
    
    # Verify extracted plugins
    if ls plugins/extracted/*.so 1> /dev/null 2>&1; then
        log_info "  ✓ Plugins extracted successfully"
        ls -lh plugins/extracted/*.so
    else
        log_error "  No plugins were extracted!"
        log_error "  Please check the extraction script output above"
        exit 1
    fi
}

# Build Falco base image
build_falco_base() {
    log_step "Building Falco base image..."
    
    cd "${PROJECT_ROOT}/docker/base"
    
    log_info "  Building falco:${FALCO_VERSION}-almalinux9..."
    docker build \
        -t "falcosecurity/falco:${FALCO_VERSION}-almalinux9" \
        -f Dockerfile \
        --build-arg FALCO_VERSION="${FALCO_VERSION}" \
        .
    
    log_info "  Tagging for local registry..."
    docker tag \
        "falcosecurity/falco:${FALCO_VERSION}-almalinux9" \
        "${LOCAL_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-almalinux9"
    
    log_info "  Pushing to local registry..."
    docker push "${LOCAL_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-almalinux9"
    
    log_info "  ✓ Falco base image built and pushed"
}

# Build Falco S3 loader image
build_falco_s3() {
    log_step "Building Falco S3 loader image..."
    
    cd "${PROJECT_ROOT}/docker/base"
    
    log_info "  Building falco:${FALCO_VERSION}-s3-almalinux9..."
    docker build \
        -t "falcosecurity/falco:${FALCO_VERSION}-s3-almalinux9" \
        -f Dockerfile.s3-loader \
        --build-arg FALCO_VERSION="${FALCO_VERSION}" \
        .
    
    log_info "  Tagging for local registry..."
    docker tag \
        "falcosecurity/falco:${FALCO_VERSION}-s3-almalinux9" \
        "${LOCAL_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-s3-almalinux9"
    
    log_info "  Pushing to local registry..."
    docker push "${LOCAL_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-s3-almalinux9"
    
    log_info "  ✓ Falco S3 loader image built and pushed"
}

# Build plugin loader image
build_plugin_loader() {
    log_step "Building plugin loader image..."
    
    cd "${PROJECT_ROOT}/docker/plugin-loader"
    
    # Copy extracted plugins to build context
    log_info "  Copying extracted plugins to build context..."
    mkdir -p plugins
    cp -v "${PROJECT_ROOT}"/plugins/extracted/*.so plugins/ 2>/dev/null || {
        log_error "  No plugins found to copy!"
        log_error "  Please run extract-plugins.sh first"
        exit 1
    }
    
    log_info "  Building falco-plugin-loader:${PLUGIN_LOADER_VERSION}..."
    docker build \
        -t "falcosecurity/falco-plugin-loader:${PLUGIN_LOADER_VERSION}" \
        -f Dockerfile \
        .
    
    log_info "  Tagging for local registry..."
    docker tag \
        "falcosecurity/falco-plugin-loader:${PLUGIN_LOADER_VERSION}" \
        "${LOCAL_REGISTRY}/falcosecurity/falco-plugin-loader:${PLUGIN_LOADER_VERSION}"
    
    log_info "  Pushing to local registry..."
    docker push "${LOCAL_REGISTRY}/falcosecurity/falco-plugin-loader:${PLUGIN_LOADER_VERSION}"
    
    # Clean up
    rm -rf plugins
    
    log_info "  ✓ Plugin loader image built and pushed"
}

# Prepare Falcosidekick images
prepare_sidekick_images() {
    log_step "Preparing Falcosidekick images..."
    
    SIDEKICK_VERSION="2.28.0"
    SIDEKICK_UI_VERSION="2.2.0"
    
    # helper for pull/tag/push
    process_image() {
        local name=$1
        local version=$2
        local source_image="falcosecurity/$name:$version"
        local target_image="${LOCAL_REGISTRY}/falcosecurity/$name:$version"
        
        log_info "  Processing $source_image..."
        docker pull "$source_image"
        docker tag "$source_image" "$target_image"
        docker push "$target_image"
        log_info "  ✓ Pushed $target_image"
    }
    
    process_image "falcosidekick" "$SIDEKICK_VERSION"
    process_image "falcosidekick-ui" "$SIDEKICK_UI_VERSION"
    
    # Redis for Sidekick UI
    log_info "  Processing redis:alpine..."
    docker pull "redis:alpine"
    docker tag "redis:alpine" "${LOCAL_REGISTRY}/redis:alpine"
    docker push "${LOCAL_REGISTRY}/redis:alpine"
    
    log_info "  ✓ Falcosidekick images prepared"
}

# Update Helm chart dependencies
update_chart_deps() {
    log_step "Updating Helm chart dependencies..."
    
    if ! helm dependency update "${PROJECT_ROOT}/helm/falco-airgapped"; then
        log_error "Failed to update Helm dependencies"
        exit 1
    fi
    log_info "  ✓ Helm dependencies updated"
}

# Main function
main() {
    log_info "========================================="
    log_info "Falco Air-Gapped Local Build"
    log_info "========================================="
    log_info "Project root: ${PROJECT_ROOT}"
    log_info "Local registry: ${LOCAL_REGISTRY}"
    log_info ""
    
    check_prerequisites
    echo ""
    
    start_local_registry
    echo ""
    
    # Ask user what to build
    echo "What would you like to build?"
    echo "  1) Extract plugins only"
    echo "  2) Build all images (Falco base + S3 loader + Plugin loader)"
    echo "  3) Build Falco base image only"
    echo "  4) Build Falco S3 loader image only"
    echo "  5) Build plugin loader image only"
    echo "  6) Full build (extract plugins + build all images)"
    read -p "Enter choice [1-6]: " choice
    
    case $choice in
        1)
            extract_plugins
            ;;
        2)
            build_falco_base
            echo ""
            build_falco_s3
            echo ""
            build_plugin_loader
            ;;
        3)
            build_falco_base
            ;;
        4)
            build_falco_s3
            ;;
        5)
            build_plugin_loader
            ;;
        6)
            extract_plugins
            echo ""
            update_chart_deps
            echo ""
            prepare_sidekick_images
            echo ""
            build_falco_base
            echo ""
            build_falco_s3
            echo ""
            build_plugin_loader
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    echo ""
    log_info "========================================="
    log_info "Build completed successfully!"
    log_info "========================================="
    log_info ""
    log_info "Next steps:"
    log_info "  1. Start Minikube: minikube start -p falcosecurity"
    log_info "  2. Configure Minikube to use local registry:"
    log_info "     minikube addons enable registry -p falcosecurity"
    log_info "  3. Deploy Falco: bash scripts/local/deploy-minikube.sh"
}

main "$@"
