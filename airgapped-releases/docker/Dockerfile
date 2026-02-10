FROM almalinux:9

# =============================================================================
# Falco Air-Gapped Deployment - Base Image
# =============================================================================
# This Dockerfile downloads Falco binaries from YOUR GitHub releases
# instead of upstream sources, enabling true air-gapped deployment.
#
# Build with:
#   docker build --build-arg GITHUB_REPO="your-user/your-repo" \
#                --build-arg FALCO_VERSION="0.42.1" \
#                -t falco:0.42.1-almalinux9 .
# =============================================================================

# Metadata
LABEL maintainer="your-team@company.com"
LABEL description="Falco Security - Air-gapped deployment on AlmaLinux 9 (GitHub Releases)"

# Build arguments - YOUR GitHub repository
ARG GITHUB_REPO
ARG FALCO_VERSION=0.42.1
ARG FALCOCTL_VERSION=0.11.4

# Validate GITHUB_REPO is provided
RUN if [ -z "${GITHUB_REPO}" ]; then \
        echo "ERROR: GITHUB_REPO build argument is required"; \
        echo "Usage: docker build --build-arg GITHUB_REPO=user/repo ..."; \
        exit 1; \
    fi

# Environment variables
ENV FALCO_VERSION=${FALCO_VERSION}
ENV FALCOCTL_VERSION=${FALCOCTL_VERSION}
ENV FALCO_BIN_DIR=/usr/bin
ENV FALCO_CONFIG_DIR=/etc/falco
ENV FALCO_PLUGINS_DIR=/usr/share/falco/plugins
ENV FALCO_RULES_DIR=/etc/falco/rules.d

# Install system dependencies
RUN dnf install -y --allowerasing \
    ca-certificates \
    curl \
    gnupg \
    jq \
    tar \
    gzip \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Create necessary directories
RUN mkdir -p \
    ${FALCO_BIN_DIR} \
    ${FALCO_CONFIG_DIR} \
    ${FALCO_PLUGINS_DIR} \
    ${FALCO_RULES_DIR} \
    /var/log/falco \
    /var/run/secrets/kubernetes.io/serviceaccount

# Download and install Falco from YOUR GitHub releases
ARG GITHUB_REPO
RUN ARCH=$(uname -m) && \
    echo "Downloading Falco ${FALCO_VERSION} for ${ARCH} from GitHub release..." && \
    curl -L -o /tmp/falco.tar.gz \
    "https://github.com/${GITHUB_REPO}/releases/download/falco-v${FALCO_VERSION}/falco-${FALCO_VERSION}-${ARCH}.tar.gz" && \
    tar -xzf /tmp/falco.tar.gz -C /tmp && \
    cp -r /tmp/falco-${FALCO_VERSION}-${ARCH}/usr/bin/* ${FALCO_BIN_DIR}/ && \
    cp -r /tmp/falco-${FALCO_VERSION}-${ARCH}/etc/falco/* ${FALCO_CONFIG_DIR}/ && \
    rm -rf /tmp/falco* && \
    chmod +x ${FALCO_BIN_DIR}/falco && \
    echo "Falco installed successfully"

# Download and install falcoctl from YOUR GitHub releases
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; fi && \
    if [ "$ARCH" = "aarch64" ]; then ARCH="arm64"; fi && \
    echo "Downloading falcoctl ${FALCOCTL_VERSION} for ${ARCH} from GitHub release..." && \
    curl -L -o /tmp/falcoctl.tar.gz \
    "https://github.com/${GITHUB_REPO}/releases/download/falcoctl-v${FALCOCTL_VERSION}/falcoctl_${FALCOCTL_VERSION}_linux_${ARCH}.tar.gz" && \
    tar -xzf /tmp/falcoctl.tar.gz -C /tmp && \
    mv /tmp/falcoctl ${FALCO_BIN_DIR}/falcoctl && \
    chmod +x ${FALCO_BIN_DIR}/falcoctl && \
    rm -rf /tmp/falcoctl* && \
    echo "falcoctl installed successfully"

# Copy default Falco configuration
# This will be overridden by ConfigMaps in Kubernetes
COPY falco.yaml ${FALCO_CONFIG_DIR}/falco.yaml

# Create a non-root user for Falco (optional, depends on driver requirements)
RUN groupadd -r falco && useradd -r -g falco falco

# Expose gRPC and metrics ports
EXPOSE 5060 8765

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ${FALCO_BIN_DIR}/falco --version || exit 1

# Default command
# Note: In Kubernetes, this will be overridden by the deployment
CMD ["/usr/bin/falco", "-c", "/etc/falco/falco.yaml"]
