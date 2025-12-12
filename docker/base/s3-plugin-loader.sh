#!/bin/bash
# S3 Plugin Loader for Falco
# Downloads plugin .so files from private S3 bucket before Falco starts

set -e

# Configuration from environment variables
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-falco-plugins/}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PLUGIN_DOWNLOAD_TIMEOUT="${PLUGIN_DOWNLOAD_TIMEOUT:-300}"
PLUGINS_DIR="${FALCO_PLUGINS_DIR:-/usr/share/falco/plugins}"
TEMP_DIR="/tmp/plugins"

# Required plugins list (can be overridden by environment variable)
REQUIRED_PLUGINS="${REQUIRED_PLUGINS:-k8saudit-eks-0.10.0.so container-0.4.1.so}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Validate configuration
validate_config() {
    log_info "Validating S3 plugin loader configuration..."
    
    if [ -z "${S3_BUCKET}" ]; then
        log_error "S3_BUCKET environment variable is not set!"
        log_error "Please set S3_BUCKET to your private S3 bucket name"
        return 1
    fi
    
    log_info "  S3 Bucket: ${S3_BUCKET}"
    log_info "  S3 Prefix: ${S3_PREFIX}"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  Plugins Directory: ${PLUGINS_DIR}"
    log_info "  Download Timeout: ${PLUGIN_DOWNLOAD_TIMEOUT}s"
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed!"
        return 1
    fi
    
    log_info "  AWS CLI Version: $(aws --version)"
    
    return 0
}

# Test S3 connectivity
test_s3_connectivity() {
    log_info "Testing S3 connectivity..."
    
    if timeout 30 aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}" --region "${AWS_REGION}" > /dev/null 2>&1; then
        log_info "  ✓ Successfully connected to S3 bucket"
        return 0
    else
        log_error "  ✗ Failed to connect to S3 bucket"
        log_error "  Please verify:"
        log_error "    - S3 bucket exists: ${S3_BUCKET}"
        log_error "    - IAM permissions are correct"
        log_error "    - Network connectivity to S3"
        log_error "    - AWS region is correct: ${AWS_REGION}"
        return 1
    fi
}

# List available plugins in S3
list_s3_plugins() {
    log_info "Listing available plugins in S3..."
    
    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}" --region "${AWS_REGION}" | grep '\.so$' || true
}

# Download plugin from S3
download_plugin() {
    local plugin_name=$1
    local s3_path="s3://${S3_BUCKET}/${S3_PREFIX}${plugin_name}"
    local temp_file="${TEMP_DIR}/${plugin_name}"
    local target_file="${PLUGINS_DIR}/${plugin_name}"
    
    log_info "Downloading plugin: ${plugin_name}"
    log_debug "  S3 Path: ${s3_path}"
    log_debug "  Target: ${target_file}"
    
    # Download to temp directory first
    if timeout "${PLUGIN_DOWNLOAD_TIMEOUT}" aws s3 cp \
        "${s3_path}" \
        "${temp_file}" \
        --region "${AWS_REGION}" \
        --no-progress; then
        
        # Verify download
        if [ -f "${temp_file}" ]; then
            local file_size=$(stat -c%s "${temp_file}")
            log_info "  Downloaded ${plugin_name} (${file_size} bytes)"
            
            # Verify it's a valid shared library
            if file "${temp_file}" | grep -q "shared object"; then
                log_info "  ✓ Verified as valid shared library"
                
                # Move to plugins directory
                mv "${temp_file}" "${target_file}"
                chmod 644 "${target_file}"
                
                log_info "  ✓ Successfully installed ${plugin_name}"
                return 0
            else
                log_error "  ✗ Downloaded file is not a valid shared library"
                rm -f "${temp_file}"
                return 1
            fi
        else
            log_error "  ✗ Downloaded file not found"
            return 1
        fi
    else
        log_error "  ✗ Failed to download ${plugin_name}"
        return 1
    fi
}

# Main function
main() {
    log_info "========================================="
    log_info "Falco S3 Plugin Loader"
    log_info "========================================="
    
    # Validate configuration
    if ! validate_config; then
        log_error "Configuration validation failed"
        exit 1
    fi
    
    # Create directories
    mkdir -p "${PLUGINS_DIR}" "${TEMP_DIR}"
    
    # Test S3 connectivity
    if ! test_s3_connectivity; then
        log_error "S3 connectivity test failed"
        exit 1
    fi
    
    # List available plugins
    list_s3_plugins
    
    # Download required plugins
    log_info "Downloading required plugins..."
    success_count=0
    fail_count=0
    
    for plugin in ${REQUIRED_PLUGINS}; do
        if download_plugin "${plugin}"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
    # Clean up temp directory
    rm -rf "${TEMP_DIR}"
    
    # Summary
    log_info ""
    log_info "========================================="
    log_info "Plugin Download Summary"
    log_info "========================================="
    log_info "Successfully downloaded: ${success_count}"
    log_info "Failed: ${fail_count}"
    log_info "========================================="
    
    # List installed plugins
    log_info ""
    log_info "Installed plugins:"
    ls -lh "${PLUGINS_DIR}"/*.so 2>/dev/null || log_warn "No plugins found in ${PLUGINS_DIR}"
    
    # Exit with appropriate status
    if [ "${fail_count}" -gt 0 ]; then
        log_error "Plugin download completed with errors"
        exit 1
    else
        log_info "All plugins downloaded successfully!"
        exit 0
    fi
}

# Run main function
main "$@"
