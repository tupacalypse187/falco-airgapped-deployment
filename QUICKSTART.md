# Quick Start Guide

Get Falco running in your air-gapped environment in under 30 minutes.

## For Local Testing (Windows 11 / macOS)

### Prerequisites Check
```bash
# Verify installations
docker --version
minikube version
kubectl version --client
helm version
```

### Three-Step Deployment

**Step 1: Extract Plugins and Build Images**
```bash
cd scripts/local
bash build-local.sh
# Select option 6 for full build
```

**Step 2: Start Minikube**
```bash
minikube start -p falcosecurity --driver=docker --cpus=4 --memory=8192
minikube addons enable registry -p falcosecurity
```

**Step 3: Deploy Falco**
```bash
bash deploy-minikube.sh
# Select option 1 (Sidecar)
# Select option 1 (Enable UI)
# Select option 1 (Load Images)
```

### Verify Deployment
```bash
kubectl get pods -n falco
# Access UI
kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802
```

## For AWS EKS Production

### Prerequisites
- AWS account with EKS cluster
- ECR registry created
- AWS CLI configured

### Quick Deploy
```bash
# Set environment variables
export ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"
export EKS_CLUSTER_NAME="my-eks-cluster"
export AWS_REGION="us-east-1"
export PLUGIN_STRATEGY="sidecar"  # or "s3"

# For S3 strategy, also set:
# export S3_BUCKET="my-falco-plugins"

# Deploy
cd scripts/aws
bash deploy-eks.sh --build
```

### Verify Deployment
```bash
kubectl get pods -n falco-dev
kubectl logs -n falco-dev -l app.kubernetes.io/name=falco-airgapped -f
```
## Download Release Binaries

### Step 1: Retrieve Metadata and Download Assets

Set variables for the source repository details
```
ORIGINAL_REPO="falcosecurity/falcoctl"
TAG="v0.11.4"
DOWNLOAD_DIR="./falcoctl_assets"
```

1a. Store the original title and body in shell variables
```
TITLE=$(gh release view $TAG --repo $ORIGINAL_REPO --json name --template '{{.name}}')
BODY=$(gh release view $TAG --repo $ORIGINAL_REPO --json body --template '{{.body}}')
```

1b. Create the download directory if it doesn't exist
```
mkdir -p $DOWNLOAD_DIR
```

1c. Download all assets from the original release into the directory
```
gh release download $TAG --repo $ORIGINAL_REPO -D $DOWNLOAD_DIR
```

### Step 2: Create a New Release on Your Fork

Replace <YOUR_USERNAME> and <YOUR_FORK_NAME> with your details before running this command.
```
gh release create $TAG $DOWNLOAD_DIR/* \
  --repo <YOUR_USERNAME>/<YOUR_FORK_NAME> \
  --title "$TITLE" \
  --notes "$BODY"
```

## Next Steps

- Review the [Local Setup Guide](docs/README_LOCAL.md) for detailed local testing instructions
- Review the [Production Deployment Guide](docs/README_PROD.md) for AWS deployment details
- Review the [Project Overview](PROJECT_OVERVIEW.md) for architecture and design details

## Common Issues

**Issue**: Plugins not extracting
**Solution**: Ensure Docker is running and you have internet access

**Issue**: Minikube pods not starting
**Solution**: Check Minikube resources: `minikube config set -p falcosecurity memory 8192`

**Issue**: EKS deployment fails
**Solution**: Verify AWS credentials: `aws sts get-caller-identity`

## Support

For detailed troubleshooting, refer to the PROJECT_OVERVIEW.md file.
