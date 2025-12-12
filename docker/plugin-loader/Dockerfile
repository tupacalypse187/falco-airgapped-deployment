FROM almalinux:9

# Metadata
LABEL maintainer="your-team@company.com"
LABEL description="Falco Plugin Loader - Sidecar for air-gapped plugin deployment"
LABEL version="1.0.0"

# Install minimal dependencies
RUN dnf install -y \
    ca-certificates \
    curl \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Create plugins directory
RUN mkdir -p /plugins

# Copy extracted plugin .so files
# These files should be placed in the same directory as this Dockerfile before building
COPY plugins/*.so /plugins/

# Copy plugin installation script
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
RUN chmod +x /usr/local/bin/install-plugins.sh

# Create a manifest file for tracking installed plugins
RUN echo "# Falco Plugins Manifest" > /plugins/manifest.txt && \
    echo "# Generated at build time: $(date)" >> /plugins/manifest.txt && \
    echo "" >> /plugins/manifest.txt && \
    ls -lh /plugins/*.so >> /plugins/manifest.txt 2>/dev/null || echo "No plugins found" >> /plugins/manifest.txt

# Verify plugins are present
RUN ls -lh /plugins/ && cat /plugins/manifest.txt

# Default command: copy plugins to mounted volume
CMD ["/usr/local/bin/install-plugins.sh"]
