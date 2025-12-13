# Local Setup and Testing Guide

This guide provides step-by-step instructions for setting up and testing the Falco air-gapped deployment on your local machine (Windows 11 or macOS) using Docker Desktop and Minikube.

## Prerequisites

Before you begin, make sure you have the following tools installed:

- **Docker Desktop**: [Installation Guide](https://www.docker.com/products/docker-desktop)
- **Minikube**: [Installation Guide](https://minikube.sigs.k8s.io/docs/start/)
- **kubectl**: [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm**: [Installation Guide](https://helm.sh/docs/intro/install/)
- **Git**: [Installation Guide](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

## Step 1: Clone the Project

First, clone this project to your local machine:

```bash
git clone https://github.com/your-org/falco-airgapped-deployment.git
cd falco-airgapped-deployment
```

## Step 2: Build the Container Images

This project includes a script to automate the process of extracting the Falco plugins and building the necessary container images. This script needs to be run in an environment with internet access to pull the official Falco plugin containers.

1.  Navigate to the `scripts/local` directory:

    ```bash
    cd scripts/local
    ```

2.  Run the `build-local.sh` script:

    ```bash
    bash build-local.sh
    ```

3.  The script will prompt you to choose what you want to build. For the initial setup, choose option `6` to perform a full build (extract plugins and build all images).

    This will:
    - Start a local Docker registry at `localhost:5000`.
    - Pull the official Falco plugin containers from `ghcr.io`.
    - Extract the `.so` plugin files and place them in the `plugins/extracted` directory.
    - Build the following container images and push them to your local registry:
      - `localhost:5000/falcosecurity/falco:0.42.1-almalinux9` (Base)
      - `localhost:5000/falcosecurity/falco:0.42.1-s3-almalinux9` (S3 Loader)
      - `localhost:5000/falcosecurity/falco-plugin-loader:1.0.0` (Plugin Loader)
      - `localhost:5000/falcosecurity/falcosidekick:2.28.0` (Sidekick)
      - `localhost:5000/falcosecurity/falcosidekick-ui:2.2.0` (Sidekick UI)
      - `localhost:5000/redis:alpine` (Redis for UI)

## Step 3: Start and Configure Minikube

1.  Start Minikube:

    ```bash
    minikube start -p falcosecurity --driver=docker --cpus=4 --memory=8192
    ```

2.  Enable the registry addon in Minikube. This will allow Minikube to pull images from your local registry.

    ```bash
    minikube addons enable registry -p falcosecurity
    ```

## Step 4: Deploy Falco to Minikube

Now that you have your images built and Minikube running, you can deploy Falco.

1.  Navigate to the `scripts/local` directory:

    ```bash
    cd scripts/local
    ```

2.  Run the `deploy-minikube.sh` script:

    ```bash
    bash deploy-minikube.sh
    ```

3.  The script will prompt you for configuration:
    - **Plugin Loading Strategy**: Choose `1` (Sidecar) for local testing.
    - **Falcosidekick UI**: Choose `1` (Yes) to enable the Web UI dashboard.
    - **Load Images**: Choose `1` (Yes) if this is your first deploy or if you rebuilt images.

4.  The script will then deploy Falco (and Sidekick components if enabled) to your Minikube cluster using the Helm chart.

## Step 5: Verify the Deployment

Once the deployment is complete, the script will display the status of the Falco pods and recent logs. You can also manually verify the deployment:

1.  Check the status of the Falco pods:

    ```bash
    kubectl get pods -n falco
    ```

    You should see a Falco pod running on each Minikube node.

2.  View the Falco logs:

    ```bash
    kubectl logs -n falco -l app.kubernetes.io/name=falco-airgapped -f
    ```

    You should see Falco's output, including any security events it detects.

3.  Access the Falcosidekick UI (if enabled):

    ```bash
    kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802
    ```

    Open your browser to [http://localhost:2802](http://localhost:2802).
    Default credentials: `admin` / `admin`.

## Cleaning Up

    helm uninstall falco -n falco
    # Verify resources are gone
    kubectl get all -n falco
    # Or delete the minikube profile entirely
    minikube delete -p falcosecurity

```bash
helm uninstall falco -n falco
```

    minikube stop -p falcosecurity

```bash
minikube stop
```

To stop the local Docker registry:

```bash
docker stop registry
```
