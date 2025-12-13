# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common Development Commands

### Local Development (Minikube)

This project uses a set of scripts in `scripts/local/` to manage the local development lifecycle.

- **Extract Plugins**: Before building, you must extract plugins from official containers.
    ```bash
    bash scripts/local/extract-plugins.sh
    ```

- **Build Images**: Build custom Falco images and push to a local registry (localhost:5000).
    ```bash
    bash scripts/local/build-local.sh
    # Interactive: Select option 6 for a full build (extract + build all)
    ```

- **Deploy to Minikube**: Deploy the Helm chart to a local Minikube cluster (profile: falcosecurity).
    ```bash
    bash scripts/local/deploy-minikube.sh
    # Interactive: Select option 1 for sidecar strategy
    ```

- **Verify Local Deployment**:
    ```bash
    kubectl get pods -n falco
    kubectl logs -n falco -l app.kubernetes.io/name=falco-airgapped -f
    ```

### Production Deployment (AWS EKS)

Deployment to AWS is managed via `scripts/aws/deploy-eks.sh` or the Jenkins pipeline.

- **Manual EKS Deployment**:
    ```bash
    # Required env vars: ECR_REGISTRY, EKS_CLUSTER_NAME, AWS_REGION, S3_BUCKET (if S3 strategy)
    export ECR_REGISTRY="your-registry"
    export EKS_CLUSTER_NAME="your-cluster"
    cd scripts/aws
    bash deploy-eks.sh --build
    ```

## Architecture Overview

This project implements an **air-gapped deployment for Falco** on Kubernetes, avoiding runtime internet dependencies.

### Core Strategy
1.  **Plugin Extraction**: Official Falco plugins (`k8saudit-eks`, `container`) are extracted from their official container images in a connected environment and stored locally or in S3.
2.  **Custom Images**: All images are rebuilt on **AlmaLinux 9** base to ensure security compliance and independence from public registries.
    -   `base`: Core Falco runtime (`docker/base/Dockerfile`).
    -   `s3-loader`: Falco + AWS CLI for pulling plugins from S3 (`docker/base/Dockerfile.s3`).
    -   `plugin-loader`: Sidecar init container containing pre-extracted plugins (`docker/plugin-loader/Dockerfile`).

### Plugin Loading Strategies
The Helm chart (`helm/falco-airgapped`) supports two modes via `values.yaml`:

1.  **Sidecar (Default)**:
    -   An init container (`plugin-loader`) copies plugins to a shared volume mounted by the Falco container.
    -   **Pros**: Self-contained, no external runtime dependencies (S3/IAM), versioned with the release.
    -   **Cons**: Larger image footprint if many plugins are used.

2.  **S3**:
    -   Falco container downloads plugins from a private S3 bucket on startup.
    -   **Pros**: Centralized plugin management, smaller images, easier plugin updates without redeploying images.
    -   **Cons**: Requires IAM permissions and connectivity to S3.

### Automation
-   **Jenkins**: A `Jenkinsfile` orchestrates the entire pipeline: Plugin extraction -> Build -> ECR Push -> Helm Deploy.
-   **Helm**: The chart is designed to be flexible for both local (Minikube) and production (EKS) environments using the same templates but different values.
