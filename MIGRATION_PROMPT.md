# Project Context: Falco Air-Gapped Deployment
**Objective:** Deploy Falco with Falcosidekick and UI in a strictly air-gapped Minikube environment.

## Current Status
- **Scripts**: [scripts/local/build-local.sh](file:///Users/cyantorno/programming/github/tupacalypse187/falcoproject/falco-airgapped-deployment/scripts/local/build-local.sh) and [deploy-minikube.sh](file:///Users/cyantorno/programming/github/tupacalypse187/falcoproject/falco-airgapped-deployment/scripts/local/deploy-minikube.sh) are fully updated.
    - They support building all images locally.
    - They handle air-gapped Helm deployment using local registry images.
    - They include interactive prompts for Falcosidekick UI and Plugin/Driver strategies.
- **Components**:
    - Falco v0.42.1 (Modern eBPF by default).
    - Falcosidekick & UI (Enabled via prompt).
    - Custom Rules (Injected via [deploy-minikube.sh](file:///Users/cyantorno/programming/github/tupacalypse187/falcoproject/falco-airgapped-deployment/scripts/local/deploy-minikube.sh)).
- **Blocker on macOS**: The Docker Desktop LinuxKit kernel (`6.12.54-linuxkit`) lacks `sys_enter_execve` tracepoints, preventing Falco from detecting process spawns (no alerts).

## Instructions for New Session (Ubuntu 24.04)
I have migrated to an Ubuntu 24.04 host to resolve the kernel issue. Please help me verify the deployment here.

1.  **Verify Prerequisites**: Ensure Docker, Minikube, Helm, and kubectl are installed.
2.  **Build Images**: Run `bash scripts/local/build-local.sh` (Option 6: Full Build) to prepare the local registry.
3.  **Deploy**: Run `bash scripts/local/deploy-minikube.sh`.
    - Select **Sidecar** for plugins.
    - Select **Yes** for Falcosidekick UI.
    - Select **Yes** to Load Images.
    - Select **Modern eBPF** (Default) for driver.
4.  **Verify Alerts**:
    - Run the "Terminal Shell" test to trigger the custom rule:
      ```bash
      kubectl exec -it -n falco $(kubectl get pods -n falco -l app.kubernetes.io/name=falco-airgapped -o jsonpath='{.items[0].metadata.name}') -- sh -c "echo 'Alert Test'; exit"
      ```
    - Check logs: `kubectl logs -n falco -l app.kubernetes.io/name=falco-airgapped`
    - You should see: `Shell spawned in a container...`

**Goal**: Confirm that Falco running on this Ubuntu host correctly detects the shell spawn and logs the alert, verifying the air-gapped stack is fully functional.
