# Air-Gapped Releases Walkthrough

This guide explains how to download all required Falco binaries from upstream sources, create GitHub releases in your repository, and build container images using those releases for true air-gapped deployment.

## Overview

For true air-gapped environments, you need to:
1. Download binaries from upstream on a machine with internet access
2. Store them in your own GitHub releases
3. Build container images that pull from YOUR releases (not upstream)
4. Transfer images to your air-gapped environment

## Prerequisites

- **GitHub CLI** (`gh`) installed and authenticated: `gh auth login`
- **curl**, **tar**, **unzip** installed
- **Docker** installed and running
- **jq** installed (for sync script)

Verify prerequisites:
```bash
gh auth status
curl --version
docker --version
```

### Multiple GitHub Accounts

If you use multiple GitHub accounts (e.g., work enterprise and personal), you'll need to switch to the correct account before running the scripts:

```bash
# Add your public GitHub account (one-time setup)
gh auth login --hostname github.com

# Switch to public GitHub before running scripts
gh auth switch --hostname github.com

# Switch back to your enterprise GitHub when done
gh auth switch --hostname github.your-company.com
```

List all configured accounts:
```bash
gh auth status
```

## Binary Sources Reference

| Component | Version | Upstream Source |
|-----------|---------|-----------------|
| Falco | 0.42.1 | `https://download.falco.org/packages/bin/{ARCH}/falco-{VERSION}-{ARCH}.tar.gz` |
| falcoctl | 0.11.4 | `https://github.com/falcosecurity/falcoctl/releases/download/v{VERSION}/falcoctl_{VERSION}_linux_{ARCH}.tar.gz` |
| AWS CLI v2 | latest | `https://awscli.amazonaws.com/awscli-exe-linux-{ARCH}.zip` |
| Plugins | various | `ghcr.io/falcosecurity/plugins/plugin/{name}:{version}` (OCI registry) |

## Quick Start

### Step 1: Configure Your Repository

Edit `versions.env` and set your GitHub repository:

```bash
# Edit the file
nano versions.env

# Set GITHUB_REPO to your repository:
GITHUB_REPO="your-username/falco-airgapped-deployment"
```

### Step 2: Switch GitHub Account (if needed)

If you have multiple GitHub accounts, switch to the one that owns this repository:

```bash
gh auth switch --hostname github.com
```

### Step 3: Download Binaries & Create Releases

Run the setup script to download all binaries and create GitHub releases:

```bash
./scripts/create-github-releases.sh
```

This creates the following releases in your repository:
- `falco-v0.42.1` - Falco binary (x86_64 + aarch64)
- `falcoctl-v0.11.4` - falcoctl CLI (amd64 + arm64)
- `awscli-v2` - AWS CLI v2 (x86_64 + aarch64)
- `plugins-v1.0.0` - Pre-extracted plugin .so files

### Step 4: Build Container Images

Build container images that pull from YOUR GitHub releases:

```bash
./scripts/build-from-releases.sh
```

This builds:
- `localhost:5000/falcosecurity/falco:0.42.1-almalinux9` - Base image
- `localhost:5000/falcosecurity/falco:0.42.1-s3-almalinux9` - S3 loader variant
- `localhost:5000/falcosecurity/falco-plugin-loader:v1.0.0` - Plugin sidecar

### Step 5: Deploy

For local testing with Minikube:
```bash
cd ../scripts/local
./deploy-minikube.sh
```

For AWS EKS:
```bash
cd ../scripts/aws
./deploy-eks.sh
```

### Step 6: Switch Back (if needed)

If you switched GitHub accounts earlier, switch back to your default:

```bash
gh auth switch --hostname github.your-company.com
```

## Keeping Up to Date

### Check for New Upstream Releases

```bash
./scripts/sync-upstream-releases.sh --check-only
```

### Sync New Releases & Rebuild

```bash
./scripts/sync-upstream-releases.sh --build
```

This will:
1. Check upstream for newer Falco/falcoctl versions
2. Download new binaries if available
3. Create new GitHub releases
4. Rebuild container images with new versions

## Script Reference

### create-github-releases.sh

Downloads all binaries from upstream and creates GitHub releases.

```bash
# Full setup
./scripts/create-github-releases.sh

# Skip specific components
./scripts/create-github-releases.sh --skip-falco
./scripts/create-github-releases.sh --skip-awscli

# Dry run (download only, no releases created)
./scripts/create-github-releases.sh --dry-run
```

### sync-upstream-releases.sh

Checks for and syncs new upstream releases.

```bash
# Check only
./scripts/sync-upstream-releases.sh --check-only

# Sync all components
./scripts/sync-upstream-releases.sh

# Sync and rebuild images
./scripts/sync-upstream-releases.sh --build

# Sync specific component
./scripts/sync-upstream-releases.sh --component falco
```

### build-from-releases.sh

Builds container images from your GitHub releases.

```bash
# Build all images
./scripts/build-from-releases.sh

# Build without S3 loader (sidecar strategy only - recommended for air-gapped)
./scripts/build-from-releases.sh --skip-s3

# Build specific image
./scripts/build-from-releases.sh --base-only
./scripts/build-from-releases.sh --s3-only
./scripts/build-from-releases.sh --plugin-only

# Build and push to registry
./scripts/build-from-releases.sh --push

# Use different registry
./scripts/build-from-releases.sh --registry my-registry.com:5000
```

### Sidecar-Only Workflow (Recommended)

For fully air-gapped deployments, you only need the sidecar strategy (no S3):

```bash
# Create releases without AWS CLI
./scripts/create-github-releases.sh --skip-awscli

# Build images without S3 loader
./scripts/build-from-releases.sh --skip-s3
```

This produces only:
- `falco:VERSION-almalinux9` - Base Falco image
- `falco-plugin-loader:VERSION` - Plugin sidecar (init container)

## Manual Steps (Alternative)

If you prefer to run the commands manually:

### Download Falco Binary

```bash
FALCO_VERSION="0.42.1"
YOUR_REPO="your-username/falco-airgapped-deployment"

mkdir -p downloads/falco
curl -L -o downloads/falco/falco-${FALCO_VERSION}-x86_64.tar.gz \
  "https://download.falco.org/packages/bin/x86_64/falco-${FALCO_VERSION}-x86_64.tar.gz"
curl -L -o downloads/falco/falco-${FALCO_VERSION}-aarch64.tar.gz \
  "https://download.falco.org/packages/bin/aarch64/falco-${FALCO_VERSION}-aarch64.tar.gz"

gh release create "falco-v${FALCO_VERSION}" downloads/falco/* \
  --repo "$YOUR_REPO" \
  --title "Falco Binary ${FALCO_VERSION}" \
  --notes "Falco binaries for air-gapped deployment"
```

### Download falcoctl

```bash
FALCOCTL_VERSION="0.11.4"

mkdir -p downloads/falcoctl
curl -L -o downloads/falcoctl/falcoctl_${FALCOCTL_VERSION}_linux_amd64.tar.gz \
  "https://github.com/falcosecurity/falcoctl/releases/download/v${FALCOCTL_VERSION}/falcoctl_${FALCOCTL_VERSION}_linux_amd64.tar.gz"
curl -L -o downloads/falcoctl/falcoctl_${FALCOCTL_VERSION}_linux_arm64.tar.gz \
  "https://github.com/falcosecurity/falcoctl/releases/download/v${FALCOCTL_VERSION}/falcoctl_${FALCOCTL_VERSION}_linux_arm64.tar.gz"

gh release create "falcoctl-v${FALCOCTL_VERSION}" downloads/falcoctl/* \
  --repo "$YOUR_REPO" \
  --title "falcoctl ${FALCOCTL_VERSION}" \
  --notes "falcoctl CLI for air-gapped deployment"
```

### Download AWS CLI

```bash
mkdir -p downloads/awscli
curl -L -o downloads/awscli/awscli-exe-linux-x86_64.zip \
  "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
curl -L -o downloads/awscli/awscli-exe-linux-aarch64.zip \
  "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"

gh release create "awscli-v2" downloads/awscli/* \
  --repo "$YOUR_REPO" \
  --title "AWS CLI v2" \
  --notes "AWS CLI for S3 plugin loader variant"
```

### Extract Plugins

```bash
# Use the project's extraction script
cd ../scripts/local
./extract-plugins.sh
cd ../../airgapped-releases

# Copy extracted plugins
mkdir -p downloads/plugins
cp ../plugins/extracted/*.so downloads/plugins/

# Create release
gh release create "plugins-v1.0.0" downloads/plugins/*.so \
  --repo "$YOUR_REPO" \
  --title "Falco Plugins v1.0.0" \
  --notes "Pre-extracted plugin .so files"
```

## Custom Rules

Add custom Falco rules in your Helm values:

```yaml
# In your values.yaml or values-custom.yaml
customRules:
  custom-rules.yaml: |-
    - rule: Detect Shell in Container
      desc: Detect shell execution inside a container
      condition: >
        spawned_process and container and
        proc.name in (bash, sh, ash, dash, zsh)
      output: >
        Shell spawned in container
        (user=%user.name container=%container.name
        shell=%proc.name parent=%proc.pname cmdline=%proc.cmdline)
      priority: WARNING
      tags: [container, shell, process]

    - rule: Detect Sensitive File Access
      desc: Detect access to sensitive files
      condition: >
        open_read and
        (fd.name startswith /etc/shadow or
         fd.name startswith /etc/passwd or
         fd.name startswith /root/.ssh)
      output: >
        Sensitive file accessed (user=%user.name file=%fd.name container=%container.name)
      priority: WARNING
      tags: [filesystem, sensitive_files]
```

## Verification

After deployment, verify everything is working:

```bash
# Check pods
kubectl get pods -n falco

# Check logs
kubectl logs -n falco -l app.kubernetes.io/name=falco-airgapped -f

# Verify plugins loaded
kubectl exec -n falco -it $(kubectl get pods -n falco -l app.kubernetes.io/name=falco-airgapped -o jsonpath='{.items[0].metadata.name}') -- ls -la /usr/share/falco/plugins/

# Check Falco version
kubectl exec -n falco -it $(kubectl get pods -n falco -l app.kubernetes.io/name=falco-airgapped -o jsonpath='{.items[0].metadata.name}') -- falco --version
```

## Troubleshooting

### Release creation fails
- Ensure `gh auth status` shows you're authenticated
- Verify you have write access to the repository
- Check if the release tag already exists

### Image build fails
- Ensure GitHub releases exist: check `https://github.com/YOUR_REPO/releases`
- Verify `versions.env` has correct GITHUB_REPO value
- Check Docker is running: `docker info`

### Plugin extraction fails
- Ensure Docker is running
- Check internet connectivity to ghcr.io
- Try running `../scripts/local/extract-plugins.sh` directly

## File Structure

```
airgapped-releases/
├── README.md                    # This guide
├── versions.env                 # Version configuration
├── scripts/
│   ├── create-github-releases.sh    # Initial setup
│   ├── sync-upstream-releases.sh    # Check for updates
│   └── build-from-releases.sh       # Build images
├── docker/
│   ├── Dockerfile                   # Base Falco image
│   ├── Dockerfile.s3-loader         # S3 loader variant
│   ├── falco.yaml                   # Default config
│   ├── s3-plugin-loader.sh          # S3 download script
│   └── falco-wrapper.sh             # Startup wrapper
└── downloads/                       # Temporary downloads (gitignored)
```
