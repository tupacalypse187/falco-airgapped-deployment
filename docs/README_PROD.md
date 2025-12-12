# Production Deployment Guide for AWS EKS

This guide provides instructions for deploying Falco to a production environment on AWS EKS using the provided Jenkins pipeline.

## Prerequisites

- An AWS account with the necessary permissions to create and manage EKS clusters, ECR repositories, and S3 buckets.
- An EKS cluster.
- An ECR registry.
- An S3 bucket (if you plan to use the S3 plugin loading strategy).
- A Jenkins server with the following:
  - The Docker plugin.
  - The Kubernetes plugin.
  - A configured agent with `docker`, `kubectl`, `helm`, and `aws-cli` installed. A `Dockerfile` for a custom Jenkins agent is provided in the `jenkins` directory.
  - AWS credentials configured in Jenkins.

## Step 1: Set Up the Jenkins Pipeline

1.  Create a new pipeline job in Jenkins.
2.  In the pipeline configuration, select "Pipeline script from SCM".
3.  Choose "Git" as the SCM and provide the URL to your Git repository.
4.  The script path should be `jenkins/Jenkinsfile`.

## Step 2: Configure Pipeline Parameters

The Jenkins pipeline is parameterized to allow for flexible deployments. Here are the available parameters:

- `DEPLOYMENT_ENV`: The target deployment environment (e.g., `dev`, `staging`, `prod`). This is used to create a unique namespace for each environment.
- `PLUGIN_STRATEGY`: The plugin loading strategy (`sidecar` or `s3`).
- `FALCO_VERSION`: The version of Falco to build.
- `ECR_REGISTRY`: The URL of your ECR registry.
- `EKS_CLUSTER_NAME`: The name of your EKS cluster.
- `AWS_REGION`: The AWS region where your EKS cluster and ECR registry are located.
- `S3_BUCKET`: The name of the S3 bucket where the plugins are stored (required if using the `s3` strategy).
- `BUILD_IMAGES`: A boolean to control whether to build and push the container images.
- `DEPLOY_TO_EKS`: A boolean to control whether to deploy Falco to the EKS cluster.

## Step 3: Run the Jenkins Pipeline

1.  Start the Jenkins pipeline by clicking "Build with Parameters".
2.  Fill in the parameters according to your environment and desired configuration.
3.  The pipeline will then execute the following stages:
    1.  **Validate Parameters**: Checks that all required parameters are provided.
    2.  **Checkout**: Checks out the code from your Git repository.
    3.  **Extract Plugins**: Runs the `extract-plugins.sh` script to get the plugin `.so` files.
    4.  **Upload Plugins to S3**: If using the `s3` strategy, uploads the plugins to the specified S3 bucket.
    5.  **Build Container Images**: Builds the Falco base image, the Falco S3 loader image, and the plugin loader sidecar image.
    6.  **Login to ECR**: Logs in to your ECR registry.
    7.  **Push Images to ECR**: Pushes the newly built images to your ECR registry.
    8.  **Configure kubectl**: Configures `kubectl` to connect to your EKS cluster.
    9.  **Create Namespace**: Creates a namespace for the Falco deployment.
    10. **Deploy Falco with Helm**: Deploys Falco to your EKS cluster using the Helm chart.
    11. **Verify Deployment**: Checks the status of the Falco pods and displays recent logs.

## Manual Deployment

If you prefer to deploy manually without using the Jenkins pipeline, you can use the `deploy-eks.sh` script in the `scripts/aws` directory.

1.  Make sure you have the AWS CLI, Docker, kubectl, and Helm installed and configured on your machine.
2.  Set the required environment variables:

    ```bash
    export ECR_REGISTRY="<your-ecr-registry>"
    export EKS_CLUSTER_NAME="<your-eks-cluster-name>"
    ```

3.  Run the script with the `--build` option to build and push the images and then deploy:

    ```bash
    bash scripts/aws/deploy-eks.sh --build
    ```

    You can also use the `PLUGIN_STRATEGY` and `S3_BUCKET` environment variables to control the plugin loading strategy.

## Verifying the Deployment

After the deployment is complete, you can verify it by:

- Checking the status of the Falco pods:

  ```bash
  kubectl get pods -n falco-<your-env>
  ```

- Viewing the Falco logs:

  ```bash
  kubectl logs -n falco-<your-env> -l app.kubernetes.io/name=falco-airgapped -f
  ```

## Conclusion

This project provides a robust and flexible solution for deploying Falco in air-gapped environments. By using pre-built plugin artifacts and custom container images, you can ensure that your Falco deployment is secure and self-contained, with no reliance on external resources.
