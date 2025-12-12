#!/bin/bash
# Falco Plugin Loader Installation Script
# This script runs as an init container to copy plugins to the shared volume

set -e

# Configuration
SOURCE_DIR="/plugins"
TARGET_DIR="${FALCO_PLUGINS_DIR:-/usr/share/falco/plugins}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

log_info "Falco Plugin Loader starting..."
log_info "Source directory: ${SOURCE_DIR}"
log_info "Target directory: ${TARGET_DIR}"

# Verify source directory exists
if [ ! -d "${SOURCE_DIR}" ]; then
    log_error "Source directory ${SOURCE_DIR} does not exist!"
    exit 1
fi

# Create target directory if it doesn't exist
if [ ! -d "${TARGET_DIR}" ]; then
    log_info "Creating target directory: ${TARGET_DIR}"
    mkdir -p "${TARGET_DIR}"
fi

# Count available plugins
plugin_count=$(find "${SOURCE_DIR}" -name "*.so" -type f | wc -l)
log_info "Found ${plugin_count} plugin(s) to install"

if [ "${plugin_count}" -eq 0 ]; then
    log_error "No plugin files found in ${SOURCE_DIR}"
    log_error "Expected .so files to be present"
    exit 1
fi

# Copy plugins to target directory
log_info "Installing plugins..."
installed=0
failed=0

for plugin_file in "${SOURCE_DIR}"/*.so; do
    if [ -f "${plugin_file}" ]; then
        plugin_name=$(basename "${plugin_file}")
        target_file="${TARGET_DIR}/${plugin_name}"
        
        log_info "  Installing: ${plugin_name}"
        
        if cp -v "${plugin_file}" "${target_file}"; then
            # Set appropriate permissions
            chmod 644 "${target_file}"
            
            # Verify the file was copied correctly
            if [ -f "${target_file}" ]; then
                source_size=$(stat -c%s "${plugin_file}")
                target_size=$(stat -c%s "${target_file}")
                
                if [ "${source_size}" -eq "${target_size}" ]; then
                    log_info "    ✓ Successfully installed ${plugin_name} (${source_size} bytes)"
                    installed=$((installed + 1))
                else
                    log_error "    ✗ Size mismatch for ${plugin_name}"
                    log_error "      Source: ${source_size} bytes, Target: ${target_size} bytes"
                    failed=$((failed + 1))
                fi
            else
                log_error "    ✗ Failed to verify ${plugin_name} after copy"
                failed=$((failed + 1))
            fi
        else
            log_error "    ✗ Failed to copy ${plugin_name}"
            failed=$((failed + 1))
        fi
    fi
done

# Copy any additional configuration files
log_info "Checking for plugin configuration files..."
config_count=0
for config_file in "${SOURCE_DIR}"/*.yaml "${SOURCE_DIR}"/*.json; do
    if [ -f "${config_file}" ]; then
        config_name=$(basename "${config_file}")
        cp -v "${config_file}" "${TARGET_DIR}/${config_name}"
        log_info "  Copied config: ${config_name}"
        config_count=$((config_count + 1))
    fi
done

if [ "${config_count}" -eq 0 ]; then
    log_info "  No configuration files found"
fi

# Create installation manifest
manifest_file="${TARGET_DIR}/installation-manifest.txt"
log_info "Creating installation manifest: ${manifest_file}"

cat > "${manifest_file}" << EOF
# Falco Plugins Installation Manifest
# Installation Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Hostname: $(hostname)
# User: $(whoami)

Installed Plugins:
EOF

ls -lh "${TARGET_DIR}"/*.so >> "${manifest_file}" 2>/dev/null || echo "No plugins installed" >> "${manifest_file}"

if [ "${config_count}" -gt 0 ]; then
    echo "" >> "${manifest_file}"
    echo "Configuration Files:" >> "${manifest_file}"
    ls -lh "${TARGET_DIR}"/*.yaml "${TARGET_DIR}"/*.json >> "${manifest_file}" 2>/dev/null
fi

# Summary
log_info ""
log_info "========================================="
log_info "Plugin Installation Summary"
log_info "========================================="
log_info "Successfully installed: ${installed}"
log_info "Failed: ${failed}"
log_info "Configuration files: ${config_count}"
log_info "========================================="

# List installed plugins
log_info ""
log_info "Installed plugins in ${TARGET_DIR}:"
ls -lh "${TARGET_DIR}"/*.so 2>/dev/null || log_warn "No .so files found in target directory"

# Exit with appropriate status
if [ "${failed}" -gt 0 ]; then
    log_error "Plugin installation completed with errors"
    exit 1
else
    log_info "Plugin installation completed successfully!"
    exit 0
fi
