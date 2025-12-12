#!/bin/bash
# Falco Wrapper Script
# Downloads plugins from S3 (if configured) before starting Falco

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_info "========================================="
log_info "Falco Startup Wrapper"
log_info "========================================="

# Check if S3 plugin loading is enabled
if [ -n "${S3_BUCKET}" ]; then
    log_info "S3 plugin loading is enabled"
    log_info "Running S3 plugin loader..."
    
    if /usr/local/bin/s3-plugin-loader.sh; then
        log_info "S3 plugin loader completed successfully"
    else
        log_error "S3 plugin loader failed"
        
        # Check if we should fail or continue
        if [ "${FAIL_ON_PLUGIN_ERROR:-true}" = "true" ]; then
            log_error "FAIL_ON_PLUGIN_ERROR is true, exiting..."
            exit 1
        else
            log_warn "FAIL_ON_PLUGIN_ERROR is false, continuing anyway..."
        fi
    fi
else
    log_info "S3 plugin loading is disabled (S3_BUCKET not set)"
    log_info "Assuming plugins are pre-installed or loaded via init container"
fi

# Verify plugins are present
PLUGINS_DIR="${FALCO_PLUGINS_DIR:-/usr/share/falco/plugins}"
log_info "Verifying plugins in ${PLUGINS_DIR}..."

if ls "${PLUGINS_DIR}"/*.so 1> /dev/null 2>&1; then
    log_info "Found plugins:"
    ls -lh "${PLUGINS_DIR}"/*.so
else
    log_warn "No plugins found in ${PLUGINS_DIR}"
    log_warn "Falco will start without additional plugins"
fi

# Display Falco version
log_info "Falco version: $(/usr/bin/falco --version 2>&1 | head -n1)"

# Display configuration
log_info "Falco configuration:"
log_info "  Config file: ${FALCO_CONFIG_FILE:-/etc/falco/falco.yaml}"
log_info "  Plugins dir: ${PLUGINS_DIR}"
log_info "  Rules dir: ${FALCO_RULES_DIR:-/etc/falco/rules.d}"

log_info "========================================="
log_info "Starting Falco..."
log_info "========================================="

# Execute Falco with provided arguments
exec "$@"
