# Falco Air-Gapped Deployment Project

This project provides a complete solution for deploying Falco, the cloud-native runtime security tool, in air-gapped environments where there is no access to the internet. It includes local testing setups for Windows 11 and macOS, and a production-ready deployment for AWS EKS.

## Project Goals

- **Air-Gapped Deployment**: Deploy Falco in an environment with no internet connectivity.
- **Private Registries**: Use a private ECR registry for all container images.
- **Custom Base Images**: Build all container images on `almalinux:9`.
- **Plugin Management**: Handle Falco plugins (`container` and `audit-eks`) without pulling from public registries like `ghcr.io`.
- **Flexible Plugin Installation**: Provide two methods for plugin installation:
  1. **Sidecar Container**: An init container that provides the plugins to the Falco container.
  2. **S3 Bucket**: Falco container pulls plugins from a private S3 bucket on startup.
- **Local Testing**: A complete local testing environment using Docker Desktop and Minikube.
- **Production Deployment**: A production-ready deployment on AWS EKS using a Jenkins pipeline.
- **Comprehensive Documentation**: Detailed README files for both local and production setups.

## Directory Structure

```
/falco-airgapped-deployment
├── docker/                      # Dockerfiles for custom images
│   ├── base/                    # Falco base image (AlmaLinux 9)
│   └── plugin-loader/           # Plugin loader sidecar image
├── helm/                        # Helm chart for Falco deployment
│   └── falco-airgapped/
├── jenkins/                     # Jenkins pipeline and agent configuration
├── plugins/                     # Falco plugin artifacts
│   ├── extracted/               # Extracted .so plugin files
│   └── source/                  # Source files for plugins (if built from source)
├── scripts/                     # Build and deployment scripts
│   ├── local/                   # Scripts for local testing
│   └── aws/                     # Scripts for AWS deployment
└── docs/                        # Detailed documentation
    ├── README_LOCAL.md          # Guide for local setup and testing
    └── README_PROD.md           # Guide for production deployment on AWS
```

## Getting Started

There are two main ways to use this project:

1.  **Local Testing**: If you want to test the Falco deployment on your local machine (Windows 11 or macOS), please refer to the [Local Setup and Testing Guide](docs/README_LOCAL.md).

2.  **Production Deployment**: If you want to deploy Falco to a production environment on AWS EKS, please refer to the [Production Deployment Guide](docs/README_PROD.md).

## How It Works

This project addresses the challenges of deploying Falco in an air-gapped environment by:

1.  **Extracting Plugin Artifacts**: Instead of building plugins from source (which requires a specific version of `cmake` and other dependencies), we pull the official Falco plugin containers from `ghcr.io` in an environment with internet access and extract the compiled `.so` files. These artifacts are then stored in a private Git repository or an S3 bucket.

2.  **Building Custom Images**: We build custom Falco container images on `almalinux:9`. These images are configured to use the extracted plugin artifacts from either a sidecar container or an S3 bucket, rather than trying to download them from the internet.

3.  **Using a Private Registry**: All container images are pushed to a private ECR registry. The Helm chart is configured to pull images from this private registry.

4.  **Flexible Helm Chart**: The provided Helm chart is designed to be flexible and supports both the `sidecar` and `s3` plugin loading strategies. You can switch between these strategies by changing a single value in the `values.yaml` file.

5.  **Automated Jenkins Pipeline**: A `Jenkinsfile` is provided to automate the entire build and deployment process, from extracting plugins and building images to deploying Falco on an EKS cluster.

## Prerequisites

- **For Local Testing**:
  - Docker Desktop
  - Minikube
  - `kubectl`
  - `helm`

- **For Production Deployment**:
  - An AWS account
  - An EKS cluster
  - An ECR registry
  - An S3 bucket (if using the S3 plugin strategy)
  - A Jenkins server with the necessary plugins and a configured agent.

For detailed instructions, please refer to the respective README files in the `docs` directory.
