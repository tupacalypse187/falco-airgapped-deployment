#!/bin/bash
# Deploy Falco to AWS EKS
# This script can be run manually or as part of CI/CD pipeline

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Default values (override with environment variables)
DEPLOYMENT_ENV="${DEPLOYMENT_ENV:-dev}"
PLUGIN_STRATEGY="${PLUGIN_STRATEGY:-sidecar}"
FALCO_VERSION="${FALCO_VERSION:-0.41.0}"
ECR_REGISTRY="${ECR_REGISTRY:-}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
S3_BUCKET="${S3_BUCKET:-}"
K8S_NAMESPACE="falco-${DEPLOYMENT_ENV}"
HELM_RELEASE="falco-${DEPLOYMENT_ENV}"

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

# Show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy Falco to AWS EKS cluster

Required Environment Variables:
  ECR_REGISTRY         ECR registry URL (e.g., 123456789012.dkr.ecr.us-east-1.amazonaws.com)
  EKS_CLUSTER_NAME     EKS cluster name

Optional Environment Variables:
  DEPLOYMENT_ENV       Deployment environment (default: dev)
  PLUGIN_STRATEGY      Plugin loading strategy: sidecar or s3 (default: sidecar)
  FALCO_VERSION        Falco version (default: 0.41.0)
  AWS_REGION           AWS region (default: us-east-1)
  S3_BUCKET            S3 bucket for plugins (required if PLUGIN_STRATEGY=s3)

Options:
  -h, --help           Show this help message
  -b, --build          Build and push images before deploying
  -d, --deploy-only    Deploy only (skip image build)

Examples:
  # Deploy with sidecar strategy
  ECR_REGISTRY=123456789012.dkr.ecr.us-east-1.amazonaws.com \\
  EKS_CLUSTER_NAME=my-eks-cluster \\
  $0 --build

  # Deploy with S3 strategy
  ECR_REGISTRY=123456789012.dkr.ecr.us-east-1.amazonaws.com \\
  EKS_CLUSTER_NAME=my-eks-cluster \\
  PLUGIN_STRATEGY=s3 \\
  S3_BUCKET=my-falco-plugins \\
  $0 --build

EOF
    exit 1
}

# Parse arguments
BUILD_IMAGES=false
DEPLOY_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -b|--build)
            BUILD_IMAGES=true
            shift
            ;;
        -d|--deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate configuration
validate_config() {
    log_step "Validating configuration..."
    
    if [ -z "${ECR_REGISTRY}" ]; then
        log_error "ECR_REGISTRY is not set"
        usage
    fi
    
    if [ -z "${EKS_CLUSTER_NAME}" ]; then
        log_error "EKS_CLUSTER_NAME is not set"
        usage
    fi
    
    if [ "${PLUGIN_STRATEGY}" = "s3" ] && [ -z "${S3_BUCKET}" ]; then
        log_error "S3_BUCKET is required when using S3 plugin strategy"
        usage
    fi
    
    log_info "  Environment: ${DEPLOYMENT_ENV}"
    log_info "  Plugin Strategy: ${PLUGIN_STRATEGY}"
    log_info "  Falco Version: ${FALCO_VERSION}"
    log_info "  ECR Registry: ${ECR_REGISTRY}"
    log_info "  EKS Cluster: ${EKS_CLUSTER_NAME}"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  Namespace: ${K8S_NAMESPACE}"
    
    if [ "${PLUGIN_STRATEGY}" = "s3" ]; then
        log_info "  S3 Bucket: ${S3_BUCKET}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    log_info "  ✓ AWS CLI: $(aws --version)"
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    log_info "  ✓ Docker: $(docker --version)"
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    log_info "  ✓ kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed"
        exit 1
    fi
    log_info "  ✓ Helm: $(helm version --short)"
}

# Extract plugins
extract_plugins() {
    log_step "Extracting Falco plugins..."
    
    cd "${PROJECT_ROOT}"
    bash scripts/local/extract-plugins.sh
    
    if ! ls plugins/extracted/*.so 1> /dev/null 2>&1; then
        log_error "No plugins were extracted"
        exit 1
    fi
    
    log_info "  ✓ Plugins extracted successfully"
}

# Upload plugins to S3
upload_plugins_to_s3() {
    log_step "Uploading plugins to S3..."
    
    aws s3 sync "${PROJECT_ROOT}/plugins/extracted/" \
        "s3://${S3_BUCKET}/falco-plugins/" \
        --region "${AWS_REGION}" \
        --exclude "*" \
        --include "*.so"
    
    log_info "  ✓ Plugins uploaded to s3://${S3_BUCKET}/falco-plugins/"
    aws s3 ls "s3://${S3_BUCKET}/falco-plugins/" --region "${AWS_REGION}"
}

# Build and push images
build_and_push_images() {
    log_step "Building container images..."
    
    # Login to ECR
    log_info "  Logging in to ECR..."
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${ECR_REGISTRY}"
    
    # Build Falco base image
    log_info "  Building Falco base image..."
    cd "${PROJECT_ROOT}/docker/base"
    docker build \
        -t "${ECR_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-almalinux9" \
        -f Dockerfile \
        --build-arg FALCO_VERSION="${FALCO_VERSION}" \
        .
    
    # Build Falco S3 image
    log_info "  Building Falco S3 image..."
    docker build \
        -t "${ECR_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-s3-almalinux9" \
        -f Dockerfile.s3-loader \
        --build-arg FALCO_VERSION="${FALCO_VERSION}" \
        .
    
    # Build plugin loader image (if using sidecar strategy)
    if [ "${PLUGIN_STRATEGY}" = "sidecar" ]; then
        log_info "  Building plugin loader image..."
        cd "${PROJECT_ROOT}/docker/plugin-loader"
        mkdir -p plugins
        cp "${PROJECT_ROOT}"/plugins/extracted/*.so plugins/
        docker build \
            -t "${ECR_REGISTRY}/falcosecurity/falco-plugin-loader:1.0.0" \
            -f Dockerfile \
            .
        rm -rf plugins
    fi
    
    # Push images
    log_step "Pushing images to ECR..."
    docker push "${ECR_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-almalinux9"
    docker push "${ECR_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-s3-almalinux9"
    
    if [ "${PLUGIN_STRATEGY}" = "sidecar" ]; then
        docker push "${ECR_REGISTRY}/falcosecurity/falco-plugin-loader:1.0.0"
    fi
    
    log_info "  ✓ Images pushed successfully"
}

# Configure kubectl
configure_kubectl() {
    log_step "Configuring kubectl for EKS..."
    
    aws eks update-kubeconfig \
        --name "${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}"
    
    log_info "  ✓ kubectl configured"
    kubectl cluster-info
}

# Create namespace
create_namespace() {
    log_step "Creating namespace..."
    
    kubectl create namespace "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    log_info "  ✓ Namespace '${K8S_NAMESPACE}' ready"
}

# Deploy with Helm
deploy_with_helm() {
    log_step "Deploying Falco with Helm..."
    
    cd "${PROJECT_ROOT}/helm/falco-airgapped"
    
    # Determine image tag based on strategy
    local IMAGE_TAG
    if [ "${PLUGIN_STRATEGY}" = "s3" ]; then
        IMAGE_TAG="${FALCO_VERSION}-s3-almalinux9"
    else
        IMAGE_TAG="${FALCO_VERSION}-almalinux9"
    fi
    
    # Prepare Helm command
    local HELM_CMD="helm upgrade --install ${HELM_RELEASE} . \
        --namespace ${K8S_NAMESPACE} \
        --set image.registry=${ECR_REGISTRY} \
        --set image.repository=falcosecurity/falco \
        --set image.tag=${IMAGE_TAG} \
        --set pluginLoadingStrategy=${PLUGIN_STRATEGY}"
    
    # Add sidecar-specific settings
    if [ "${PLUGIN_STRATEGY}" = "sidecar" ]; then
        HELM_CMD="${HELM_CMD} \
            --set pluginLoader.enabled=true \
            --set pluginLoader.image.registry=${ECR_REGISTRY} \
            --set pluginLoader.image.repository=falcosecurity/falco-plugin-loader \
            --set pluginLoader.image.tag=1.0.0 \
            --set s3PluginLoader.enabled=false"
    fi
    
    # Add S3-specific settings
    if [ "${PLUGIN_STRATEGY}" = "s3" ]; then
        HELM_CMD="${HELM_CMD} \
            --set pluginLoader.enabled=false \
            --set s3PluginLoader.enabled=true \
            --set s3PluginLoader.bucket=${S3_BUCKET} \
            --set s3PluginLoader.region=${AWS_REGION}"
    fi
    
    # Add common settings
    HELM_CMD="${HELM_CMD} \
        --wait \
        --timeout 10m"
    
    # Execute Helm command
    eval "${HELM_CMD}"
    
    log_info "  ✓ Falco deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    log_info "  Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=falco-airgapped \
        -n "${K8S_NAMESPACE}" \
        --timeout=300s || {
        log_warn "  Pods did not become ready in time"
    }
    
    log_info "  DaemonSet status:"
    kubectl get daemonset -n "${K8S_NAMESPACE}"
    
    log_info "  Pods:"
    kubectl get pods -n "${K8S_NAMESPACE}" -l app.kubernetes.io/name=falco-airgapped
    
    log_info "  Recent logs:"
    kubectl logs -n "${K8S_NAMESPACE}" -l app.kubernetes.io/name=falco-airgapped --tail=20 || true
}

# Main function
main() {
    log_info "========================================="
    log_info "Falco AWS EKS Deployment"
    log_info "========================================="
    log_info ""
    
    validate_config
    echo ""
    
    check_prerequisites
    echo ""
    
    if [ "${BUILD_IMAGES}" = true ]; then
        extract_plugins
        echo ""
        
        if [ "${PLUGIN_STRATEGY}" = "s3" ]; then
            upload_plugins_to_s3
            echo ""
        fi
        
        build_and_push_images
        echo ""
    fi
    
    if [ "${DEPLOY_ONLY}" = false ]; then
        configure_kubectl
        echo ""
        
        create_namespace
        echo ""
        
        deploy_with_helm
        echo ""
        
        verify_deployment
        echo ""
    fi
    
    log_info "========================================="
    log_info "Deployment completed successfully!"
    log_info "========================================="
    log_info ""
    log_info "Access commands:"
    log_info "  kubectl get pods -n ${K8S_NAMESPACE}"
    log_info "  kubectl logs -n ${K8S_NAMESPACE} -l app.kubernetes.io/name=falco-airgapped -f"
    log_info "  helm status ${HELM_RELEASE} -n ${K8S_NAMESPACE}"
    log_info ""
}

main "$@"
