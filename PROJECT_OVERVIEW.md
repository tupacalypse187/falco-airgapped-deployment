# Falco Air-Gapped Deployment - Project Overview

## Executive Summary

This project delivers a complete, production-ready solution for deploying Falco security monitoring in air-gapped environments where internet access is restricted or unavailable. The solution addresses the unique challenges of deploying cloud-native security tools in isolated networks by providing pre-extracted plugin artifacts, custom AlmaLinux 9-based container images, and flexible deployment strategies for both local testing and production AWS EKS environments.

## Architecture Overview

The solution is built around three core components that work together to enable Falco deployment without external network dependencies:

**Custom Container Images**: All container images are built on AlmaLinux 9 as the base operating system. The project includes three primary images: the Falco base image containing the core Falco runtime, the Falco S3-loader image with integrated AWS CLI for plugin retrieval, and the plugin-loader sidecar image that serves as an init container for plugin installation.

**Plugin Management System**: Rather than building Falco plugins from source (which requires specific cmake versions and build toolchains), the solution extracts pre-compiled plugin shared object files from official Falco containers. This approach eliminates build complexity while maintaining compatibility with official Falco releases. The extracted plugins are then distributed through either a sidecar init container pattern or via private S3 bucket storage.

**Deployment Flexibility**: The Helm chart provides a unified deployment interface that supports both local Minikube testing and production EKS deployments. Configuration values control the plugin loading strategy, allowing teams to choose between sidecar-based plugin injection or S3-based dynamic loading based on their operational requirements.

## Plugin Loading Strategies

### Sidecar Strategy

The sidecar strategy uses a Kubernetes init container pattern to provide plugins to the main Falco container. During pod initialization, the plugin-loader container copies pre-packaged plugin files to a shared volume that is then mounted by the Falco container. This approach offers several advantages: plugins are versioned alongside container images, no runtime network access is required, and the deployment is completely self-contained. The sidecar strategy is particularly well-suited for environments where container image management is already well-established and teams prefer to version all dependencies together.

### S3 Strategy

The S3 strategy leverages AWS infrastructure to centralize plugin management. When a Falco pod starts, it executes a pre-startup script that downloads required plugins from a private S3 bucket before launching the Falco process. This approach enables centralized plugin updates across multiple clusters without rebuilding container images, supports easy rollback to previous plugin versions, and allows different clusters to use different plugin versions simultaneously. The S3 strategy is ideal for organizations managing multiple Kubernetes clusters that need flexibility in plugin version management.

## Local Testing Environment

The local testing environment is designed to work on both Windows 11 and macOS systems using Docker Desktop and Minikube. The workflow begins with extracting plugins from official Falco containers in an internet-connected environment, then building custom images and pushing them to a local Docker registry running at localhost:5000. Minikube is configured to access this local registry, enabling complete offline testing of the deployment before moving to production.

The local testing scripts automate the entire process: `extract-plugins.sh` pulls official plugin containers and extracts the compiled shared objects, `build-local.sh` builds all three custom images and pushes them to the local registry, and `deploy-minikube.sh` deploys Falco to Minikube using the Helm chart with appropriate local configuration.

## Production Deployment Pipeline

The production deployment pipeline is implemented as a Jenkins pipeline that orchestrates the complete build and deployment workflow. The pipeline is parameterized to support multiple environments (dev, staging, production) and both plugin loading strategies. Key pipeline stages include parameter validation, plugin extraction, optional S3 upload for the S3 strategy, parallel image building for all three container types, ECR authentication and image pushing, kubectl configuration for the target EKS cluster, namespace creation, Helm-based deployment, and post-deployment verification.

The pipeline is designed to be idempotent and can be run multiple times safely. It supports partial execution through boolean parameters that control whether to build images or deploy to EKS, allowing teams to separate build and deployment concerns if needed.

## Security Considerations

The solution implements several security best practices for air-gapped deployments. All container images are pulled from a private ECR registry with appropriate IAM-based authentication. When using the S3 strategy, plugins are stored in a private S3 bucket with access controlled through IAM roles and policies. The Falco deployment uses Kubernetes RBAC to limit permissions to only what is necessary for runtime security monitoring. Container security contexts are configured to provide Falco with the necessary privileges for system call monitoring while minimizing the attack surface.

## File Structure and Components

The project is organized into clearly defined directories that separate concerns:

The `docker` directory contains all Dockerfiles and associated scripts. The `base` subdirectory includes the main Falco Dockerfile, the S3-loader variant, configuration files, and startup scripts. The `plugin-loader` subdirectory contains the sidecar image definition and plugin installation script.

The `helm` directory contains the complete Helm chart for Falco deployment. The chart includes templates for all Kubernetes resources (DaemonSet, ConfigMap, RBAC, Service, ServiceMonitor) and a comprehensive values.yaml file that exposes all configuration options.

The `scripts` directory is divided into `local` and `aws` subdirectories. Local scripts handle plugin extraction, image building, and Minikube deployment. AWS scripts provide manual deployment capabilities for EKS environments.

The `jenkins` directory contains the Jenkinsfile for automated CI/CD and a Dockerfile for building a custom Jenkins agent with all required tools.

The `plugins` directory serves as the workspace for plugin management, with `extracted` containing the .so files and `source` preserving the full container filesystem for reference.

## Deployment Workflow

### Local Testing Workflow

The local testing workflow follows a straightforward sequence. First, ensure Docker Desktop is running and Minikube is installed. Execute the plugin extraction script to obtain the required .so files from official Falco containers. Run the build script and select the full build option to create all images and push them to the local registry. Start Minikube with appropriate resource allocation and enable the registry addon. Execute the deployment script and select the sidecar strategy for local testing. Verify the deployment by checking pod status and reviewing Falco logs.

### Production Deployment Workflow

The production deployment workflow can be executed through Jenkins or manually. For Jenkins-based deployment, configure the pipeline job to point to your Git repository, set up AWS credentials in Jenkins, create and configure the custom Jenkins agent, and trigger the pipeline with appropriate parameters for your environment. For manual deployment, configure AWS CLI with appropriate credentials, set required environment variables for ECR registry and EKS cluster, execute the deployment script with the build flag, and verify the deployment through kubectl commands.

## Customization and Extension

The solution is designed to be easily customizable for specific organizational needs. Plugin versions can be updated by modifying the plugins-manifest.yaml file and re-running the extraction script. Additional Falco rules can be added through the customRules section in the Helm values file. Resource limits and requests can be adjusted in the values file to match your cluster capacity. The Helm chart can be extended with additional Kubernetes resources as needed. Environment-specific configurations can be managed through separate values files for each deployment environment.

## Troubleshooting Guide

Common issues and their solutions are documented to help teams quickly resolve problems:

If plugins fail to extract, verify Docker is running and you have internet access to ghcr.io. Check the extraction script output for specific error messages and ensure sufficient disk space for container filesystem extraction.

If images fail to build, verify all required files are present in the build context. Check Docker daemon logs for detailed error messages and ensure the base AlmaLinux image can be pulled.

If Minikube deployment fails, verify Minikube has sufficient resources allocated. Check that the registry addon is enabled and functioning. Ensure images were successfully pushed to localhost:5000.

If EKS deployment fails, verify AWS credentials have necessary permissions. Check that the EKS cluster is accessible from your deployment environment. Ensure the ECR registry URL is correct and images exist. For S3 strategy, verify the S3 bucket exists and IAM roles are properly configured.

If Falco pods fail to start, check pod events for specific error messages. Review init container logs for plugin loading issues. Verify the Falco configuration is valid. Check node kernel version compatibility with the selected driver type.

## Maintenance and Updates

Ongoing maintenance of the deployment involves several key activities. Plugin updates should be performed by extracting new plugin versions and rebuilding the plugin-loader image or updating the S3 bucket. Falco version updates require updating the FALCO_VERSION parameter, rebuilding base images, and redeploying through Helm. Security patches for AlmaLinux base images necessitate rebuilding all images with the latest AlmaLinux base. Helm chart updates can be applied through helm upgrade commands with updated values files.

## Performance Considerations

The solution is designed with performance in mind. The modern_bpf driver is used by default as it provides the best performance and compatibility. Resource requests and limits are set conservatively and should be adjusted based on actual workload. The DaemonSet ensures Falco runs on every node for complete cluster coverage. Metrics are exposed through a Prometheus-compatible endpoint for monitoring and alerting.

## Conclusion

This project provides a comprehensive, production-ready solution for deploying Falco in air-gapped environments. By addressing the challenges of plugin management, providing flexible deployment strategies, and including complete automation through Jenkins, the solution enables organizations to implement runtime security monitoring in isolated networks without compromising on functionality or operational efficiency. The clear separation between local testing and production deployment workflows ensures teams can validate changes before applying them to production environments.
