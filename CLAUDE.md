# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project deploys Falco (cloud-native runtime security tool) in air-gapped environments with no internet access. It provides custom AlmaLinux 9-based container images and two plugin loading strategies: sidecar (init container) or S3 bucket.

## Build Commands

### Local Development (Minikube)

```bash
# Full build: extract plugins + build all images
cd scripts/local && bash build-local.sh
# Select option 6 for full build

# Start Minikube with required profile
minikube start -p falcosecurity --driver=docker --cpus=4 --memory=8192
minikube addons enable registry -p falcosecurity

# Deploy to Minikube
bash scripts/local/deploy-minikube.sh
```

### AWS EKS Production

```bash
export ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"
export EKS_CLUSTER_NAME="my-eks-cluster"
export AWS_REGION="us-east-1"
export PLUGIN_STRATEGY="sidecar"  # or "s3"

cd scripts/aws && bash deploy-eks.sh --build
```

### Individual Build Steps

```bash
# Extract plugins from official containers (requires internet)
bash scripts/local/extract-plugins.sh

# Update Helm dependencies
helm dependency update helm/falco-airgapped
```

## Architecture

### Plugin Loading Strategies

The Helm chart supports two mutually exclusive plugin loading methods controlled by `pluginLoadingStrategy` in values.yaml:

1. **Sidecar** (`pluginLoadingStrategy: "sidecar"`): Init container copies pre-extracted `.so` plugin files to a shared volume before Falco starts. Fully air-gapped at runtime.

2. **S3** (`pluginLoadingStrategy: "s3"`): Falco container downloads plugins from S3 bucket on startup. Requires S3 VPC endpoint for air-gapped networks.

### Container Images

All images built on AlmaLinux 9:

- `falcosecurity/falco:<version>-almalinux9` - Base Falco image (Dockerfile: `docker/base/Dockerfile`)
- `falcosecurity/falco:<version>-s3-almalinux9` - Falco with AWS CLI for S3 plugin loading (Dockerfile: `docker/base/Dockerfile.s3-loader`)
- `falcosecurity/falco-plugin-loader:1.0.0` - Sidecar with pre-extracted plugins (Dockerfile: `docker/plugin-loader/Dockerfile`)

### Key Versions

- Falco: 0.42.1
- falcoctl: 0.11.4
- Plugins: k8saudit/k8saudit-eks 0.10.0, container 0.4.1
- Falcosidekick: 2.28.0, UI: 2.2.0

### Helm Chart Structure

The chart at `helm/falco-airgapped/` creates: DaemonSet, ServiceAccount, ClusterRole/Binding, ConfigMap, Service, and optionally ServiceMonitor. It includes falcosidekick as a subchart dependency.

Key template logic:
- `templates/daemonset.yaml` - Conditionally adds init container based on plugin strategy
- `templates/_helpers.tpl` - Template helpers for naming and labels
- `values.yaml` - Plugin strategy toggle, image configs, Falco settings, driver selection (modern_bpf/ebpf)

### Plugin Extraction Process

`scripts/local/extract-plugins.sh` pulls official plugin containers from `ghcr.io`, extracts `.so` files from their filesystem, and stores them in `plugins/extracted/`. This runs on a machine with internet access; extracted plugins are committed or transferred to air-gapped environment.

## Verification Commands

```bash
# Check pods
kubectl get pods -n falco

# View logs
kubectl logs -n falco -l app.kubernetes.io/name=falco-airgapped -f

# Access Falcosidekick UI (if enabled)
kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802

# Check metrics
kubectl port-forward -n falco daemonset/falco 8765:8765
curl http://localhost:8765/metrics
```
