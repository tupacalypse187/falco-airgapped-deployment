#!/bin/bash
# Script to extract Falco plugins from GHCR containers
# This script pulls plugin containers and extracts the .so files for air-gapped deployment

set -e

# Configuration
PLUGINS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins" && pwd)"
EXTRACTED_DIR="${PLUGINS_DIR}/extracted"
SOURCE_DIR="${PLUGINS_DIR}/source"

# Plugin versions to extract
# Plugin names and versions (using parallel arrays for Bash 3.2 compatibility)
PLUGIN_NAMES=(
    "k8saudit-eks"
    "k8saudit"
    "container"
)

PLUGIN_VERSIONS=(
    "0.10.0"
    "0.10.0"
    "0.4.1"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Create directories
mkdir -p "${EXTRACTED_DIR}" "${SOURCE_DIR}"

log_info "Starting Falco plugin extraction process..."
log_info "Extracted plugins will be saved to: ${EXTRACTED_DIR}"

for i in "${!PLUGIN_NAMES[@]}"; do
    plugin_name="${PLUGIN_NAMES[$i]}"
    version="${PLUGIN_VERSIONS[$i]}"
    log_info "Processing plugin: ${plugin_name} (version ${version})"

    # Use falcosecurity/falcoctl Docker image to download the plugin
    # This avoids "unsupported media type" errors on some Docker versions/platforms
    # because falcoctl handles OCI artifacts correctly.
    log_info "  Downloading plugin using falcoctl (Docker)..."
    
    if ! docker run --rm \
        --user root \
        -v "${EXTRACTED_DIR}:/plugins" \
        falcosecurity/falcoctl:0.11.0 \
        artifact install "ghcr.io/falcosecurity/plugins/plugin/${plugin_name}:${version}" --plugins-dir /plugins; then
        
        log_error "  Failed to download plugin ${plugin_name}"
        log_error "  Please check internet connection or plugin version"
        continue
    fi
    
    # Rename standard lib name to versioned name expected by build/config
    # e.g. libk8saudit-eks.so -> k8saudit-eks-0.10.0.so
    if [ -f "${EXTRACTED_DIR}/lib${plugin_name}.so" ]; then
        mv "${EXTRACTED_DIR}/lib${plugin_name}.so" "${EXTRACTED_DIR}/${plugin_name}-${version}.so"
        log_info "  Renamed lib${plugin_name}.so -> ${plugin_name}-${version}.so"
    fi
    
    log_info "  ✓ Plugin ${plugin_name} downloaded successfully"
    echo ""
done

# List extracted plugins
log_info "Extraction process completed!"
log_info "Extracted plugin files:"
ls -lh "${EXTRACTED_DIR}"/*.so 2>/dev/null || log_warn "No .so files found in ${EXTRACTED_DIR}"

log_info ""
log_info "Plugin source filesystems available at: ${SOURCE_DIR}"
log_info "You can manually inspect these if automatic extraction failed."
log_info ""
log_info "Next steps:"
log_info "  1. Verify extracted .so files in: ${EXTRACTED_DIR}"
log_info "  2. Commit these files to your private Git repository"
log_info "  3. Or upload to S3 bucket for production use"
