#!/bin/bash
# Deploy Falco to Minikube
# This script deploys Falco using Helm with local registry images

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCAL_REGISTRY="localhost:5000"
FALCO_VERSION="0.42.1"
NAMESPACE="falco"
RELEASE_NAME="falco"
PLUGIN_STRATEGY="sidecar"  # Options: sidecar, s3

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
    
    if ! command -v minikube &> /dev/null; then
        log_error "Minikube is not installed"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed"
        exit 1
    fi
    
    log_info "  ✓ All prerequisites met"
}

# Check Minikube status
check_minikube() {
    log_step "Checking Minikube status..."
    
    if ! minikube status -p falcosecurity &> /dev/null; then
        log_warn "  Minikube is not running"
        read -p "Start Minikube now? (y/n): " start_minikube
        
        if [ "$start_minikube" = "y" ]; then
            log_info "  Starting Minikube..."
            minikube start -p falcosecurity --driver=docker --cpus=4 --memory=8192
        else
            log_error "  Please start Minikube first: minikube start"
            exit 1
        fi
    fi
    
    log_info "  ✓ Minikube is running"
    minikube status -p falcosecurity
}

# Configure registry access
configure_registry() {
    log_step "Configuring registry access..."
    
    # For Minikube to access localhost:5000, we need to configure it
    log_info "  Configuring Minikube to access local registry..."
    
    # Check if registry addon is enabled
    if minikube addons list -p falcosecurity | grep -q "registry.*enabled"; then
        log_info "  ✓ Registry addon is already enabled"
    else
        log_info "  Enabling registry addon..."
        minikube addons enable registry -p falcosecurity
    fi
    
    # Create port forward to local registry (if needed)
    log_info "  Setting up registry port forwarding..."
    
    # Kill any existing port forwards
    pkill -f "kubectl.*port-forward.*registry" || true
    sleep 1
    
    # Note: For Minikube, we'll use the registry addon instead of localhost:5000
    log_info "  ✓ Registry configuration complete"
}

# Create namespace
create_namespace() {
    log_step "Creating namespace..."
    
    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        log_info "  Namespace '${NAMESPACE}' already exists"
    else
        log_info "  Creating namespace '${NAMESPACE}'..."
        kubectl create namespace "${NAMESPACE}"
    fi
}

# Deploy Falco with Helm
deploy_falco() {
    log_step "Deploying Falco with Helm..."
    
    cd "${PROJECT_ROOT}/helm/falco-airgapped"
    
    # Ask user for plugin loading strategy
    echo ""
    echo "Select plugin loading strategy:"
    echo "  1) Sidecar (init container)"
    echo "  2) S3 bucket (requires S3 configuration)"
    read -p "Enter choice [1-2]: " strategy_choice
    
    case $strategy_choice in
        1)
            PLUGIN_STRATEGY="sidecar"
            ;;
        2)
            PLUGIN_STRATEGY="s3"
            read -p "Enter S3 bucket name: " s3_bucket
            read -p "Enter S3 prefix (default: falco-plugins/): " s3_prefix
            s3_prefix=${s3_prefix:-falco-plugins/}
            read -p "Enter AWS region (default: us-east-1): " aws_region
            aws_region=${aws_region:-us-east-1}
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac

    # Ask if user wants to enable Falcosidekick UI
    echo ""
    echo "Do you want to enable Falcosidekick UI? (Requires Redis/UI images)"
    echo "  1) Yes"
    echo "  2) No"
    read -p "Enter choice [1-2]: " sidekick_choice
    
    ENABLE_SIDEKICK="false"
    if [ "$sidekick_choice" = "1" ]; then
        ENABLE_SIDEKICK="true"
    fi
    
    log_info "  Plugin loading strategy: ${PLUGIN_STRATEGY}"

    # Ask user for driver kind
    echo ""
    echo "Select driver kind (If unsure, 'modern_ebpf' is faster, 'ebpf' is more compatible with VMs/Mac):"
    echo "  1) Modern eBPF (default)"
    echo "  2) Standard eBPF (requires driver loader - NOT supported on Minikube LinuxKit)"
    read -p "Enter choice [1-2]: " driver_choice
    
    DRIVER_KIND="modern_ebpf"
    DRIVER_LOADER_ENABLED="false"
    
    if [ "$driver_choice" = "2" ]; then
        DRIVER_KIND="ebpf"
        DRIVER_LOADER_ENABLED="true"
    fi
    
    log_info "  Driver kind: ${DRIVER_KIND}"

    # Ask if user wants to load images (optional)
    echo ""
    echo "Do you want to load images into Minikube? (Recommended for first deploy or after rebuild)"
    echo "  1) Yes"
    echo "  2) No"
    read -p "Enter choice [1-2]: " load_images_choice
    
    if [ "$load_images_choice" = "1" ]; then
        log_info "  Loading images into Minikube..."
        minikube -p falcosecurity image load "${LOCAL_REGISTRY}/falcosecurity/falco:${FALCO_VERSION}-almalinux9"
        minikube -p falcosecurity image load "${LOCAL_REGISTRY}/falcosecurity/falco-plugin-loader:1.0.0"
        
        if [ "$ENABLE_SIDEKICK" = "true" ]; then
            log_info "  Loading Sidekick images..."
            minikube -p falcosecurity image load "${LOCAL_REGISTRY}/falcosecurity/falcosidekick:2.28.0"
            minikube -p falcosecurity image load "${LOCAL_REGISTRY}/falcosecurity/falcosidekick-ui:2.2.0"
            minikube -p falcosecurity image load "${LOCAL_REGISTRY}/redis:alpine"
        fi

        if [ "$DRIVER_LOADER_ENABLED" = "true" ]; then
            log_info "  Loading Driver Loader image..."
            minikube -p falcosecurity image load "${LOCAL_REGISTRY}/falcosecurity/falco-driver-loader:${FALCO_VERSION}"
        fi
        log_info "  ✓ Images loaded into Minikube"
    else
        log_info "  Skipping image loading"
    fi
    
    # Prepare Helm values
    cat > /tmp/falco-local-values.yaml <<EOF
# Local Minikube values
image:
  registry: "${LOCAL_REGISTRY}"
  repository: "falcosecurity/falco"
  tag: "${FALCO_VERSION}-almalinux9"
  pullPolicy: IfNotPresent

falco:
  config:
    engine:
      kind: modern_ebpf

    # Ensure alerts are visible in logs (text format)
    jsonOutput: true
    logLevel: info
    stdoutOutput:
      enabled: true

    plugins:
      - name: k8saudit
        library_path: /usr/share/falco/plugins/k8saudit-0.10.0.so
        init_config: ""
        open_params: "http://0.0.0.0:9765/k8s-audit"
      - name: container
        library_path: /usr/share/falco/plugins/container-0.4.1.so
        init_config: ""
        open_params: ""
    
    http_output:
      enabled: ${ENABLE_SIDEKICK}
      url: "http://\${FALCO_FALCOSIDEKICK_SERVICE_HOST}:\${FALCO_FALCOSIDEKICK_SERVICE_PORT}/"

falcosidekick:
  enabled: ${ENABLE_SIDEKICK}
  webui:
    enabled: ${ENABLE_SIDEKICK}
    service:
      type: ClusterIP

  config:
    debug: true
    redis:
      address: "${RELEASE_NAME}-falcosidekick-ui-redis:6379"
      port: "6379"
      minimumpriority: "debug"

  # Configure Redis to use local air-gapped image
  redis:
    enabled: true
    image:
      registry: "${LOCAL_REGISTRY}"
      repository: "redis"
      tag: "alpine"
      pullPolicy: IfNotPresent

pluginLoadingStrategy: "${PLUGIN_STRATEGY}"

pluginLoader:
  enabled: $([ "$PLUGIN_STRATEGY" = "sidecar" ] && echo "true" || echo "false")
  image:
    registry: "${LOCAL_REGISTRY}"
    repository: "falcosecurity/falco-plugin-loader"
    tag: "1.0.0"
    pullPolicy: IfNotPresent

s3PluginLoader:
  enabled: $([ "$PLUGIN_STRATEGY" = "s3" ] && echo "true" || echo "false")
$(if [ "$PLUGIN_STRATEGY" = "s3" ]; then
cat <<INNER
  bucket: "${s3_bucket}"
  prefix: "${s3_prefix}"
  region: "${aws_region}"
INNER
fi)

driver:
  enabled: true
  kind: ${DRIVER_KIND}
  loader:
    enabled: ${DRIVER_LOADER_ENABLED}
    initContainer:
      enabled: ${DRIVER_LOADER_ENABLED}
      image:
        registry: "${LOCAL_REGISTRY}"
        repository: "falcosecurity/falco-driver-loader"
        tag: "${FALCO_VERSION}"
        pullPolicy: IfNotPresent

daemonset:
  tolerations:
    - effect: NoSchedule
      operator: Exists

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

extraVolumes:
  - name: test-rules
    configMap:
      name: falco-falco-airgapped-rules-local-test-rules-yaml
  - name: debugfs
    hostPath:
      path: /sys/kernel/debug

extraVolumeMounts:
  - name: test-rules
    mountPath: /etc/falco/rules.d/local_test_rules.yaml
    subPath: local_test_rules.yaml
  - name: debugfs
    mountPath: /sys/kernel/debug

customRules:
  local_test_rules.yaml: |-
    - rule: Terminal Shell in Container
      desc: A shell was spawned in a container with an attached terminal.
      condition: >
        spawned_process and container
        and shell_procs
      output: >
        Shell spawned in a container
        (user=%user.name user_loginuid=%user.loginuid
        container_id=%container.id container_name=%container.name
        shell=%proc.name parent=%proc.pname cmdline=%proc.cmdline terminal=%proc.tty)
      priority: WARNING
      tags: [container, shell, mitre_execution]
EOF
    
    log_info "  Generated Helm values:"
    cat /tmp/falco-local-values.yaml
    echo ""
    
    # Install or upgrade Falco
    log_info "  Installing/upgrading Falco..."
    helm upgrade --install "${RELEASE_NAME}" . \
        --namespace "${NAMESPACE}" \
        --values /tmp/falco-local-values.yaml \
        --wait \
        --timeout 5m
    
    log_info "  ✓ Falco deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    log_info "  Waiting for Falco pods to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=falco-airgapped \
        -n "${NAMESPACE}" \
        --timeout=300s || {
        log_warn "  Pods did not become ready in time"
        log_warn "  Checking pod status..."
        kubectl get pods -n "${NAMESPACE}"
        log_warn "  Checking logs..."
        kubectl logs -n "${NAMESPACE}" -l app.kubernetes.io/name=falco-airgapped --tail=50
    }
    
    log_info "  Falco pods:"
    kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=falco-airgapped
    
    log_info "  Falco DaemonSet:"
    kubectl get daemonset -n "${NAMESPACE}"
}

# Show logs
show_logs() {
    log_step "Showing Falco logs..."
    
    echo ""
    log_info "Recent Falco logs:"
    kubectl logs -n "${NAMESPACE}" -l app.kubernetes.io/name=falco-airgapped --tail=20
    
    echo ""
    log_info "To follow logs, run:"
    echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=falco-airgapped -f"
}

# Show access commands
show_access_commands() {
    log_info ""
    log_info "========================================="
    log_info "Access Commands"
    log_info "========================================="
    log_info ""
    log_info "View pods:"
    log_info "  kubectl get pods -n ${NAMESPACE}"
    log_info ""
    log_info "View logs:"
    log_info "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=falco-airgapped -f"
    log_info ""
    log_info "Describe pod:"
    log_info "  kubectl describe pod -n ${NAMESPACE} -l app.kubernetes.io/name=falco-airgapped"
    log_info ""
    log_info "Port forward to metrics endpoint:"
    log_info "  kubectl port-forward -n ${NAMESPACE} daemonset/falco 8765:8765"
    log_info "  Then access: http://localhost:8765/metrics"
    log_info ""
    if [ "$ENABLE_SIDEKICK" = "true" ]; then
        log_info "Port forward to Falcosidekick UI:"
        log_info "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-falcosidekick-ui 2802:2802"
        log_info "  Then access: http://localhost:2802"
        log_info "  (Default credentials: admin / admin)"
        log_info ""
    fi
    log_info "Uninstall:"
    log_info "  helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
    log_info ""
}

# Main function
main() {
    log_info "========================================="
    log_info "Falco Minikube Deployment"
    log_info "========================================="
    log_info ""
    
    check_prerequisites
    echo ""
    
    check_minikube
    echo ""
    
    configure_registry
    echo ""
    
    create_namespace
    echo ""
    
    deploy_falco
    echo ""
    
    verify_deployment
    echo ""
    
    show_logs
    echo ""
    
    show_access_commands
    
    log_info "========================================="
    log_info "Deployment completed successfully!"
    log_info "========================================="
}

main "$@"
