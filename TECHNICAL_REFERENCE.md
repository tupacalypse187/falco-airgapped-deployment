# Technical Reference

This document provides detailed technical information about the Falco air-gapped deployment project.

## Container Images

### Falco Base Image

**Image Name**: `falcosecurity/falco:0.41.0-almalinux9`

**Base OS**: AlmaLinux 9

**Key Components**:
- Falco binary version 0.41.0
- falcoctl CLI tool version 0.11.1
- Modern BPF probe support
- Configuration files in `/etc/falco`
- Plugin directory at `/usr/share/falco/plugins`

**Exposed Ports**:
- 5060: gRPC API
- 8765: Metrics and health check endpoint

**Health Check**: HTTP GET on `/healthz` endpoint at port 8765

### Falco S3 Loader Image

**Image Name**: `falcosecurity/falco:0.41.0-s3-almalinux9`

**Additional Components**:
- AWS CLI v2
- S3 plugin loader script
- Falco wrapper script for pre-startup plugin download

**Environment Variables**:
- `S3_BUCKET`: S3 bucket containing plugins
- `S3_PREFIX`: Prefix/folder path in S3 (default: `falco-plugins/`)
- `AWS_REGION`: AWS region (default: `us-east-1`)
- `REQUIRED_PLUGINS`: Space-separated list of plugin filenames
- `PLUGIN_DOWNLOAD_TIMEOUT`: Download timeout in seconds (default: 300)
- `FAIL_ON_PLUGIN_ERROR`: Whether to fail if plugin download fails (default: true)

### Plugin Loader Sidecar Image

**Image Name**: `falcosecurity/falco-plugin-loader:1.0.0`

**Purpose**: Init container that copies plugins to shared volume

**Contents**:
- Pre-extracted plugin `.so` files in `/plugins`
- Installation script at `/usr/local/bin/install-plugins.sh`
- Manifest file tracking included plugins

**Volume Mount**: Expects target directory at `/usr/share/falco/plugins` (configurable via `FALCO_PLUGINS_DIR`)

### Falcosidekick Images

**Images**:
- `falcosecurity/falcosidekick:2.28.0`: Forwards events
- `falcosecurity/falcosidekick-ui:2.2.0`: Web Dashboard
- `redis:alpine`: Backend for UI

**Air-Gapped Handling**:
These images are pulled during the "Full Build" phase and pushed to the local registry to ensure 100% offline compatibility during deployment.

## Falco Plugins

### k8saudit Plugin (Local/Generic)
**Version**: 0.10.0
**Event Source**: `k8s_audit`
**Purpose**: Generic Kubernetes audit log support (used for Minikube/local testing)

### k8saudit-eks Plugin (AWS)

**Version**: 0.10.0

**Plugin ID**: 9

**Event Source**: `k8s_audit`

**Capabilities**: Event Sourcing, Field Extraction

**Purpose**: Reads Kubernetes audit events from AWS EKS clusters

**Configuration Parameters**:
- `s3_bucket`: S3 bucket containing EKS audit logs
- `s3_prefix`: Prefix for audit log files
- `aws_region`: AWS region

**File Location**: `/usr/share/falco/plugins/k8saudit-eks-0.10.0.so`

### container Plugin

**Version**: 0.4.1

**Event Source**: `syscall`

**Capabilities**: Field Extraction

**Purpose**: Enriches Falco syscall events with container metadata

**Configuration**: No configuration required

**File Location**: `/usr/share/falco/plugins/container-0.4.1.so`

## Helm Chart Configuration

### Key Values

**Image Configuration**:
```yaml
image:
  registry: "your-private-registry.com"
  repository: "falcosecurity/falco"
  tag: "0.41.0-almalinux9"
  pullPolicy: IfNotPresent
```

**Plugin Loading Strategy**:
```yaml
pluginLoadingStrategy: "sidecar"  # or "s3"
```

**Sidecar Configuration**:
```yaml
pluginLoader:
  enabled: true
  image:
    registry: "your-private-registry.com"
    repository: "falcosecurity/falco-plugin-loader"
    tag: "1.0.0"
```

**S3 Configuration**:
```yaml
s3PluginLoader:
  enabled: true
  bucket: "my-falco-plugins"
  prefix: "falco-plugins/"
  region: "us-east-1"
  requiredPlugins: "k8saudit-eks-0.10.0.so container-0.4.1.so"
```

**Driver Configuration**:
```yaml
driver:
  enabled: true
  kind: modern_bpf  # Options: module, ebpf, modern_bpf
```

**Resource Limits**:
```yaml
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

**Falcosidekick Configuration**:
```yaml
falcosidekick:
  enabled: true
  image:
    registry: "localhost:5000"
  webui:
    enabled: true
    image:
      registry: "localhost:5000"
  redis:
    image:
      registry: "localhost:5000"
```

### Kubernetes Resources Created

The Helm chart creates the following Kubernetes resources:

1. **ServiceAccount**: For Falco pods with optional IAM role annotations
2. **ClusterRole**: Grants read access to cluster resources for enrichment
3. **ClusterRoleBinding**: Binds the ClusterRole to the ServiceAccount
4. **ConfigMap**: Contains Falco configuration and custom rules
5. **DaemonSet**: Deploys Falco on every node
6. **Service**: Exposes gRPC and metrics ports
7. **ServiceMonitor** (optional): For Prometheus Operator integration

## Script Reference

### extract-plugins.sh

**Location**: `scripts/local/extract-plugins.sh`

**Purpose**: Extracts plugin `.so` files from official Falco containers

**Requirements**: Docker with internet access to ghcr.io

**Output**: Plugin files in `plugins/extracted/` directory

**Process**:
1. Pulls official plugin containers from ghcr.io
2. Creates temporary containers without running them
3. Exports container filesystem as tarball
4. Searches for `.so` files in the filesystem
5. Copies found plugins to extracted directory
6. Cleans up temporary containers and files

### build-local.sh

**Location**: `scripts/local/build-local.sh`

**Purpose**: Builds container images for local testing

**Requirements**: Docker Desktop

**Features**:
- Starts local Docker registry at localhost:5000
- Interactive menu for selective building
- Builds and tags all images
- Pushes images to local registry

**Options**:
1. Extract plugins only
2. Build all images
3. Build Falco base image only
4. Build Falco S3 loader image only
5. Build plugin loader image only
6. Full build (extract + build all)

### deploy-minikube.sh

**Location**: `scripts/local/deploy-minikube.sh`

**Purpose**: Deploys Falco to Minikube cluster

**Requirements**: Minikube, kubectl, Helm

**Features**:
- Checks and starts Minikube if needed
- Configures registry access
- Creates namespace
- Generates values file for local deployment
- Deploys using Helm
- Verifies deployment and shows logs

### deploy-eks.sh

**Location**: `scripts/aws/deploy-eks.sh`

**Purpose**: Deploys Falco to AWS EKS cluster

**Requirements**: AWS CLI, Docker, kubectl, Helm

**Environment Variables**:
- `ECR_REGISTRY`: ECR registry URL (required)
- `EKS_CLUSTER_NAME`: EKS cluster name (required)
- `DEPLOYMENT_ENV`: Environment name (default: dev)
- `PLUGIN_STRATEGY`: sidecar or s3 (default: sidecar)
- `FALCO_VERSION`: Falco version (default: 0.41.0)
- `AWS_REGION`: AWS region (default: us-east-1)
- `S3_BUCKET`: S3 bucket for plugins (required if using s3 strategy)

**Options**:
- `--build`: Build and push images before deploying
- `--deploy-only`: Deploy only without building

## Jenkins Pipeline

### Pipeline Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| DEPLOYMENT_ENV | Choice | Target environment | dev |
| PLUGIN_STRATEGY | Choice | Plugin loading method | sidecar |
| FALCO_VERSION | String | Falco version to build | 0.41.0 |
| ECR_REGISTRY | String | ECR registry URL | (empty) |
| EKS_CLUSTER_NAME | String | EKS cluster name | (empty) |
| AWS_REGION | String | AWS region | us-east-1 |
| S3_BUCKET | String | S3 bucket for plugins | (empty) |
| BUILD_IMAGES | Boolean | Build and push images | true |
| DEPLOY_TO_EKS | Boolean | Deploy to EKS | true |

### Pipeline Stages

1. **Validate Parameters**: Ensures all required parameters are provided
2. **Checkout**: Checks out code from SCM
3. **Extract Plugins**: Runs plugin extraction script
4. **Upload Plugins to S3**: Uploads plugins if using S3 strategy
5. **Build Container Images**: Builds all three images in parallel
6. **Login to ECR**: Authenticates with ECR registry
7. **Push Images to ECR**: Pushes images in parallel
8. **Configure kubectl**: Sets up kubectl for EKS access
9. **Create Namespace**: Creates deployment namespace
10. **Deploy Falco with Helm**: Deploys using Helm chart
11. **Verify Deployment**: Checks pod status and logs

### Custom Jenkins Agent

**Dockerfile**: `jenkins/Dockerfile.jenkins-agent`

**Base Image**: jenkins/inbound-agent:latest-jdk17

**Installed Tools**:
- Docker CLI
- kubectl
- Helm
- AWS CLI v2

**Purpose**: Provides all necessary tools for running the pipeline

## Network Requirements

### Local Testing

**Outbound Access Required** (during build phase only):
- ghcr.io: For pulling official Falco plugin containers
- download.falco.org: For downloading Falco binaries
- github.com: For downloading falcoctl and other tools

**No Outbound Access Required** (during deployment):
- All images pulled from localhost:5000
- No external network dependencies

### Production Deployment

**Outbound Access Required** (during build phase only):
- ghcr.io: For pulling official Falco plugin containers
- download.falco.org: For downloading Falco binaries

**Outbound Access Required** (during runtime with S3 strategy):
- S3 endpoint in your AWS region (can use VPC endpoint for private access)

**No Outbound Access Required** (during runtime with sidecar strategy):
- All plugins pre-loaded in init container
- No external network dependencies

## Security Best Practices

### IAM Permissions

**For S3 Plugin Strategy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-falco-plugins",
        "arn:aws:s3:::my-falco-plugins/*"
      ]
    }
  ]
}
```

**For ECR Access**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
```

### RBAC Configuration

The Helm chart creates a ClusterRole with minimal required permissions:
- Read access to pods, nodes, namespaces, services, events
- Read access to deployments, daemonsets, replicasets, statefulsets
- Read access to jobs and cronjobs
- Read access to pod logs (for container plugin)
- Read access to configmaps (for k8s audit plugin)

### Pod Security

**Security Context**:
- Runs as root (required for system call monitoring)
- Privileged mode enabled (required for BPF programs)
- Host PID namespace access (required for process monitoring)
- Host network access (required for network monitoring)

**Capabilities**:
- SYS_ADMIN: For loading BPF programs
- SYS_RESOURCE: For resource limit adjustments
- SYS_PTRACE: For process tracing

## Performance Tuning

### Resource Allocation

**Minimum Requirements**:
- CPU: 200m (0.2 cores)
- Memory: 512Mi

**Recommended for Production**:
- CPU: 500m-1000m (0.5-1 cores)
- Memory: 1-2Gi

### Driver Selection

**modern_bpf** (Recommended):
- Best performance
- No kernel module compilation required
- Requires kernel 5.8+

**ebpf**:
- Good performance
- Requires kernel headers
- Requires BPF compilation

**module**:
- Legacy option
- Requires kernel module compilation
- Best compatibility with older kernels

### Buffer Sizing

**Default**: 4 (syscall_buf_size_preset)

**For High-Volume Environments**: Increase to 8 or 16

**Trade-off**: Higher buffer size increases memory usage but reduces dropped events

## Monitoring and Observability

### Metrics Endpoint

**URL**: `http://pod-ip:8765/metrics`

**Format**: Prometheus-compatible

**Key Metrics**:
- `falco_events_total`: Total events processed
- `falco_drops_total`: Total dropped events
- `falco_outputs_total`: Total outputs generated
- `falco_rules_matched_total`: Total rules matched

### Health Check Endpoint

**URL**: `http://pod-ip:8765/healthz`

**Response**: 200 OK when healthy

### Logging

**Default Output**: stdout (captured by Kubernetes)

**File Output**: `/var/log/falco/events.log` (optional)

**Log Levels**: debug, info, warning, error, critical

## Troubleshooting

### Plugin Loading Issues

**Symptom**: Falco fails to start with plugin-related errors

**Diagnosis**:
```bash
kubectl logs -n falco <pod-name> -c plugin-loader
kubectl logs -n falco <pod-name> -c falco
```

**Common Causes**:
- Plugin files not present in expected location
- Incorrect plugin file permissions
- Plugin version mismatch with Falco version

### Driver Loading Issues

**Symptom**: Falco cannot load BPF program

**Diagnosis**:
```bash
kubectl describe pod -n falco <pod-name>
kubectl logs -n falco <pod-name>
```

**Common Causes**:
- Kernel version too old for modern_bpf
- Missing kernel headers for ebpf/module
- Insufficient permissions

### Performance Issues

**Symptom**: High CPU usage or dropped events

**Diagnosis**:
```bash
kubectl top pod -n falco
curl http://pod-ip:8765/metrics | grep drops
```

**Solutions**:
- Increase buffer size
- Increase resource limits
- Filter out noisy rules
- Reduce syscall capture scope
