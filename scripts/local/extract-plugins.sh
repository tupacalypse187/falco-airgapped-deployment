#!/bin/bash
# Script to extract Falco plugins from GHCR containers
# This script pulls plugin containers and extracts the .so files for air-gapped deployment

set -e

# Configuration
PLUGINS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins" && pwd)"
EXTRACTED_DIR="${PLUGINS_DIR}/extracted"
SOURCE_DIR="${PLUGINS_DIR}/source"

# Plugin versions to extract
declare -A PLUGINS=(
    ["k8saudit-eks"]="0.10.0"
    ["container"]="0.4.1"
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

for plugin_name in "${!PLUGINS[@]}"; do
    version="${PLUGINS[$plugin_name]}"
    image="ghcr.io/falcosecurity/plugins/plugin/${plugin_name}:${version}"
    container_name="falco-plugin-extract-${plugin_name}"
    
    log_info "Processing plugin: ${plugin_name} (version ${version})"
    
    # Pull the plugin container
    log_info "  Pulling container: ${image}"
    if docker pull "${image}"; then
        log_info "  Successfully pulled ${image}"
    else
        log_error "  Failed to pull ${image}"
        continue
    fi
    
    # Create container without running it
    log_info "  Creating container for extraction..."
    if docker create --name "${container_name}" "${image}" >/dev/null 2>&1; then
        log_info "  Container created: ${container_name}"
    else
        log_warn "  Container ${container_name} may already exist, removing..."
        docker rm "${container_name}" >/dev/null 2>&1 || true
        docker create --name "${container_name}" "${image}" >/dev/null 2>&1
    fi
    
    # Try to find and extract plugin files
    log_info "  Searching for plugin files in container..."
    
    # Common plugin locations in Falco plugin containers
    plugin_paths=(
        "/plugins"
        "/usr/share/falco/plugins"
        "/lib"
        "/"
    )
    
    extracted=false
    for path in "${plugin_paths[@]}"; do
        log_info "    Checking path: ${path}"
        
        # Try to copy the entire directory first
        if docker cp "${container_name}:${path}" "${SOURCE_DIR}/${plugin_name}-temp" 2>/dev/null; then
            log_info "    Found files in ${path}"
            
            # Search for .so files
            find "${SOURCE_DIR}/${plugin_name}-temp" -name "*.so" -type f | while read -r so_file; do
                filename=$(basename "${so_file}")
                cp "${so_file}" "${EXTRACTED_DIR}/${plugin_name}-${version}.so"
                log_info "    Extracted: ${filename} -> ${plugin_name}-${version}.so"
                extracted=true
            done
            
            # Also copy any config files
            find "${SOURCE_DIR}/${plugin_name}-temp" -name "*.yaml" -o -name "*.json" | while read -r config_file; do
                filename=$(basename "${config_file}")
                cp "${config_file}" "${EXTRACTED_DIR}/${plugin_name}-${version}-${filename}"
                log_info "    Extracted config: ${filename}"
            done
            
            # Clean up temp directory
            rm -rf "${SOURCE_DIR}/${plugin_name}-temp"
            break
        fi
    done
    
    # If no .so file found, try direct file copy
    if [ ! -f "${EXTRACTED_DIR}/${plugin_name}-${version}.so" ]; then
        log_info "    Attempting direct .so file extraction..."
        for path in "${plugin_paths[@]}"; do
            if docker cp "${container_name}:${path}/lib${plugin_name}.so" "${EXTRACTED_DIR}/${plugin_name}-${version}.so" 2>/dev/null; then
                log_info "    Successfully extracted lib${plugin_name}.so"
                extracted=true
                break
            fi
            if docker cp "${container_name}:${path}/${plugin_name}.so" "${EXTRACTED_DIR}/${plugin_name}-${version}.so" 2>/dev/null; then
                log_info "    Successfully extracted ${plugin_name}.so"
                extracted=true
                break
            fi
        done
    else
        extracted=true
    fi
    
    # Export the container filesystem as a tarball for manual inspection if needed
    log_info "  Exporting container filesystem for reference..."
    docker export "${container_name}" > "${SOURCE_DIR}/${plugin_name}-${version}-filesystem.tar"
    log_info "  Container filesystem exported to: ${SOURCE_DIR}/${plugin_name}-${version}-filesystem.tar"
    
    # Extract the tarball to inspect structure
    mkdir -p "${SOURCE_DIR}/${plugin_name}-${version}-fs"
    tar -xf "${SOURCE_DIR}/${plugin_name}-${version}-filesystem.tar" -C "${SOURCE_DIR}/${plugin_name}-${version}-fs"
    
    # Search for .so files in the extracted filesystem
    log_info "  Searching extracted filesystem for .so files..."
    find "${SOURCE_DIR}/${plugin_name}-${version}-fs" -name "*.so" -type f | while read -r so_file; do
        filename=$(basename "${so_file}")
        relative_path="${so_file#${SOURCE_DIR}/${plugin_name}-${version}-fs}"
        cp "${so_file}" "${EXTRACTED_DIR}/${plugin_name}-${version}.so"
        log_info "    Found and extracted: ${relative_path} -> ${plugin_name}-${version}.so"
        extracted=true
    done
    
    # Clean up container
    log_info "  Cleaning up container..."
    docker rm "${container_name}" >/dev/null 2>&1
    
    if [ "$extracted" = true ] || [ -f "${EXTRACTED_DIR}/${plugin_name}-${version}.so" ]; then
        log_info "  ✓ Plugin ${plugin_name} extraction completed"
    else
        log_error "  ✗ Failed to extract plugin ${plugin_name}"
        log_warn "  Manual inspection required. Check: ${SOURCE_DIR}/${plugin_name}-${version}-fs"
    fi
    
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
