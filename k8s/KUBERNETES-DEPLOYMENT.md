# Kubernetes Deployment Guide for AMD Inference Microservice (AIM) with KServe

This comprehensive guide walks you through deploying AMD Inference Microservice (AIM) to a Kubernetes cluster using **KServe**, the official Kubernetes-native framework for serving ML models. This guide follows the [official AMD AIM deployment approach](https://rocm.blogs.amd.com/artificial-intelligence/enterprise-ai-aims/README.html) and includes observability, scalability, and production-ready features.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Cluster Requirements](#cluster-requirements)
3. [Quick Start](#quick-start)
4. [Step 1: Get the Deployment Repository](#step-1-get-the-deployment-repository)
5. [Step 2: Install KServe Infrastructure](#step-2-install-kserve-infrastructure)
6. [Step 3: Deploy Basic AIM Inference Service](#step-3-deploy-basic-aim-inference-service)
7. [Step 4: Test the Inference Endpoint](#step-4-test-the-inference-endpoint)
8. [Step 5: Deploy Monitored Inference Service (Optional)](#step-5-deploy-monitored-inference-service-optional)
9. [Step 6: Access Grafana Dashboard (Optional)](#step-6-access-grafana-dashboard-optional)
10. [Step 7: Generate Inference Requests for Metrics (Optional)](#step-7-generate-inference-requests-for-metrics-optional)
11. [Testing and Validation](#testing-and-validation)
12. [Troubleshooting](#troubleshooting)
13. [Production Considerations](#production-considerations)
14. [Cleanup](#cleanup)

## Kubernetes Cluster Setup

**Before proceeding with AIM deployment, you must have a Kubernetes cluster with AMD GPU support properly configured.**

### Setup Kubernetes Cluster with AMD GPUs

This guide assumes you have a Kubernetes cluster already set up with AMD Instinct MI300X GPUs. If you need to set up a Kubernetes cluster from scratch, please follow the comprehensive guide in the **[Kubernetes-MI300X repository](https://github.com/Yu-amd/Kubernetes-MI300X)**.

**Quick Setup Steps (from Kubernetes-MI300X):**

1. **System Check and Preparation:**
   ```bash
   sudo ./check-system-enhanced.sh
   ```

2. **Install Kubernetes:**
   ```bash
   sudo ./install-kubernetes.sh
   ```
   This installs vanilla Kubernetes 1.28+ with containerd, Calico CNI, and configures a single-node cluster.

3. **Install AMD GPU Operator:**
   ```bash
   ./install-amd-gpu-operator.sh
   ```
   This installs Helm, cert-manager, AMD GPU Operator, and configures device settings for GPU access.

**For detailed instructions, troubleshooting, and architecture overview, refer to the [Kubernetes-MI300X repository](https://github.com/Yu-amd/Kubernetes-MI300X).**

**After completing the cluster setup, verify your cluster is ready:**

```bash
# Verify Kubernetes is running
kubectl cluster-info

# Verify GPU nodes are available
kubectl get nodes

# Verify AMD GPU Operator is installed
kubectl get pods -n amd-gpu-operator
```

**Once your cluster is set up and verified, proceed with the prerequisites section below.**

---

## Prerequisites

**Note:** The following prerequisites assume you have already completed the Kubernetes cluster setup using the [Kubernetes-MI300X repository](https://github.com/Yu-amd/Kubernetes-MI300X).

### Required Tools

- `kubectl` (v1.24+) - Kubernetes command-line tool (installed in cluster setup)
- `Helm 3.8+` - Package manager for Kubernetes (installed with AMD GPU Operator)
- Access to a Kubernetes cluster with GPU nodes (configured in cluster setup)
- **Cluster admin privileges** - Required for installing KServe
- **Internet access** - For pulling charts and manifests
- `curl` - For testing the service
- `git` - For cloning the deployment repository
- `jq` (optional) - For JSON processing

### Verify Prerequisites

**Automated Prerequisites Check (Recommended):**

Run the automated validation script to check all prerequisites at once:

```bash
cd k8s/scripts
bash ./validate-k8s-prerequisites.sh
```

This script automates all prerequisite checks and provides a summary. It checks:
- Required tools (kubectl, Helm, curl, git, jq)
- Kubernetes cluster access
- GPU operator and device plugin
- GPU resources availability
- Storage class configuration
- Cluster admin privileges
- Internet access

**Manual Prerequisites Check (Alternative):**

If you prefer to check manually, follow the steps below:

**Verify Kubernetes Cluster:**
```bash
# Check kubectl version
kubectl version --client

# Check cluster access
kubectl cluster-info
```

**Expected Output:**
```
Kubernetes control plane is running at https://<cluster-endpoint>:<port>
```

**Verify GPU Nodes:**
```bash
# List all nodes
kubectl get nodes

# Check node labels (if labeled during cluster setup)
kubectl get nodes --show-labels
```

**Verify AMD GPU Operator:**
```bash
# Check GPU operator pods (primary namespace)
kubectl get pods -n amd-gpu-operator

# Verify GPU device plugin (should be in amd-gpu-operator namespace)
kubectl get pods -n amd-gpu-operator | grep device-plugin

# Alternative: Check all namespaces for GPU components
kubectl get pods --all-namespaces | grep -E "gpu|device-plugin"
```

**Expected Output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
amd-gpu-device-plugin-xxxxx               1/1     Running   0          5m
```

**Verify GPU Resources:**
```bash
# Check GPU resources on nodes
kubectl describe node <node-name> | grep -i gpu
```

**What to Check:**
- Kubernetes cluster is accessible
- GPU operator pods are running
- GPU device plugin is active
- GPU resources are available on nodes

**If any of these checks fail, refer back to the [Kubernetes-MI300X setup guide](https://github.com/Yu-amd/Kubernetes-MI300X) to resolve issues before proceeding.**

### Remote Access Setup (SSH Port Forwarding)

**If you are accessing the Kubernetes cluster remotely via SSH**, you'll need to set up SSH port forwarding to access services that are port-forwarded on the remote node.

**On your local machine, establish SSH connection with port forwarding:**

```bash
# SSH to the remote MI300X node with port forwarding for common services
ssh -L 8000:localhost:8000 -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 user@remote-mi300x-node

# Or if you need to forward additional ports later, you can add them:
# ssh -L 8000:localhost:8000 -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 user@remote-mi300x-node
```

**Port Forwarding Reference:**
- **Port 8000**: AIM inference service (Step 4)
- **Port 8080**: Scalable AIM inference service (Step 7)
- **Port 3000**: Grafana dashboard (Step 6)
- **Port 9090**: Prometheus (optional, for direct Prometheus access)

**Note:** 
- Keep the SSH session open while using port-forwarded services
- You can add more port forwards to the SSH command as needed
- If you're already connected via SSH, you can use `kubectl port-forward` directly on the remote node

**Alternative: Use SSH config for persistent port forwarding:**

Add to your `~/.ssh/config`:
```
Host mi300x-cluster
    HostName <remote-node-ip-or-hostname>
    User <your-username>
    LocalForward 8000 localhost:8000
    LocalForward 8080 localhost:8080
    LocalForward 3000 localhost:3000
    LocalForward 9090 localhost:9090
```

Then connect with:
```bash
ssh mi300x-cluster
```

### Cluster Components

The following components should already be installed if you followed the [Kubernetes-MI300X setup guide](https://github.com/Yu-amd/Kubernetes-MI300X):

- **Kubernetes**: v1.28+ (installed via `install-kubernetes.sh`)
- **Container Runtime**: containerd with GPU support (configured during cluster setup)
- **CNI**: Calico networking (installed during cluster setup)
- **AMD GPU Operator**: Installed via `install-amd-gpu-operator.sh`
- **GPU Device Plugin**: AMD GPU device plugin (installed with GPU operator)
- **Helm**: 3.8+ (installed with AMD GPU operator)
- **cert-manager**: Installed with AMD GPU operator (required for KServe)
- **Default Storage Class**: **Required for observability components** - Must be configured before installing observability stack (Step 2.3). If not configured, pods will be Pending with "unbound immediate PersistentVolumeClaims" error.

**If any components are missing, refer to the [Kubernetes-MI300X repository](https://github.com/Yu-amd/Kubernetes-MI300X) for installation instructions.**

## Cluster Requirements

### GPU Node Configuration

Your Kubernetes cluster should already be configured with AMD Instinct MI300X GPUs if you followed the [Kubernetes-MI300X setup guide](https://github.com/Yu-amd/Kubernetes-MI300X). The following should already be in place:

1. **GPU Nodes**: Nodes with AMD Instinct MI300X GPUs
   - Verified during cluster setup
   - GPU operator automatically detects and configures GPUs

2. **GPU Device Plugin**: AMD GPU device plugin installed
   - Installed automatically with AMD GPU operator
   - Verify with: `kubectl get pods -n amd-gpu-operator` or `kubectl get pods --all-namespaces | grep device-plugin`

3. **ROCm Support**: ROCm drivers installed and accessible
   - Configured during cluster setup
   - GPU operator manages ROCm integration

**If you need to label nodes for specific scheduling (optional):**
```bash
kubectl label nodes <node-name> accelerator=amd-instinct-mi300x
```

**Verify GPU availability:**
```bash
# Check GPU resources
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

**Expected Output:**
```
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  amd.com/gpu        0            0
```

**If GPU resources are not visible, refer to the [Kubernetes-MI300X troubleshooting guide](https://github.com/Yu-amd/Kubernetes-MI300X) to resolve GPU operator issues.**

### Resource Requirements

- **Per Pod**:
  - GPU: 1x AMD Instinct MI300X
  - Memory: 64Gi (request) / 200Gi (limit)
  - CPU: 8 cores (request) / 32 cores (limit)

- **Cluster Minimum**:
  - 1 GPU node with MI300X
  - Sufficient cluster resources for monitoring stack (if enabled)

## Quick Start

This guide follows the [official AMD AIM deployment approach using KServe](https://rocm.blogs.amd.com/artificial-intelligence/enterprise-ai-aims/README.html). KServe provides a Kubernetes-native framework for serving ML models with built-in support for autoscaling, canary deployments, and observability.

**Before starting, validate prerequisites:**
```bash
cd k8s/scripts
bash ./validate-k8s-prerequisites.sh
```

This automated script checks all prerequisites and provides a summary. See the [Prerequisites](#prerequisites) section for manual verification steps.

### Quick Deployment Overview

```bash
# 1. Clone the AIM deployment repository
git clone https://github.com/amd-enterprise-ai/aim-deploy.git
cd aim-deploy/kserve/kserve-install

# 2. Install KServe infrastructure with full monitoring and observability
bash ./install-deps.sh --enable=full

# 3. Deploy AIM inference service
cd ../sample-minimal-aims-deployment
kubectl apply -f servingruntime-aim-qwen3-32b.yaml
kubectl apply -f aim-qwen3-32b.yaml

# 3.5. Check model endpoint status and wait for ready
kubectl get inferenceservice aim-qwen3-32b
# Wait until READY column shows "True" (may take 5-10 minutes for model to load)
# Or watch the status: kubectl get inferenceservice aim-qwen3-32b -w

# 4. Test the service
# First, verify the service exists: kubectl get svc aim-qwen3-32b-predictor
# If not found, check InferenceService: kubectl get inferenceservice aim-qwen3-32b
# For remote access: Set up SSH port forwarding first (on local machine)
# ssh -L 8000:localhost:8000 user@remote-mi300x-node
# Keep SSH session open!

# Port forward AIM service (on remote node)
kubectl port-forward service/aim-qwen3-32b-predictor 8000:80
# Keep this terminal open!
# Note: If you get "service not found", you may have already deleted it in Step 4.5. Use scalable service instead.

# In another terminal (or if using SSH, on your local machine):
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# 4.5. Deploy scalable service for metrics (optional)
# Check GPU availability: kubectl describe node <node-name> | grep -A 5 "amd.com/gpu"
# If single GPU: Stop basic service first: kubectl delete inferenceservice aim-qwen3-32b
# If multiple GPUs (e.g., 8x MI300X): Skip stopping basic service, deploy scalable service alongside it
# Wait for scalable service to start: kubectl wait --for=condition=ready inferenceservice aim-qwen3-32b-scalable --timeout=600s
# Test scalable service (port 8080)
# For remote access: ssh -L 8080:localhost:8080 user@remote-mi300x-node (or add to existing SSH)
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
# Test: curl -X POST http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' --no-buffer | sed 's/^data: //' | grep -v '^\[DONE\]$' | jq -r '.choices[0].delta.content // empty' | tr -d '\n' && echo

# 5. Deploy monitored inference service with autoscaling (optional - requires observability setup)
# Note: If you completed Step 4.5, the scalable service is already deployed. You can skip to Step 6.
# Check if serving runtime from step 3 is already applied
kubectl get clusterservingruntime aim-qwen3-32b-runtime
# If not found, apply it (from the sample-minimal-aims-deployment directory)
cd ../sample-minimal-aims-deployment
kubectl apply -f servingruntime-aim-qwen3-32b.yaml
cd ../kserve-install

# Create the monitored inference service manifest
cat <<'EOF' > aim-qwen3-32b-scalable.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: aim-qwen3-32b-scalable
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    serving.kserve.io/autoscalerClass: "keda"
    sidecar.opentelemetry.io/inject: "otel-lgtm-stack/vllm-sidecar-collector"
spec:
  predictor:
    model:
      runtime: aim-qwen3-32b-runtime
      modelFormat:
        name: aim-qwen3-32b
      env:
        - name: VLLM_ENABLE_METRICS
          value: "true"
      resources:
        limits:
          memory: "128Gi"
          cpu: "8"
          amd.com/gpu: "1"
        requests:
          memory: "64Gi"
          cpu: "4"
          amd.com/gpu: "1"
    minReplicas: 1
    maxReplicas: 3
    autoScaling:
      metrics:
        - type: External
          external:
            metric:
              backend: "prometheus"
              serverAddress: "http://lgtm-stack.otel-lgtm-stack.svc:9090"
              query: 'sum(vllm:num_requests_running{service="isvc.aim-qwen3-32b-scalable-predictor"})'
            target:
              type: Value
              value: "1"
EOF

# Apply the monitored inference service
kubectl apply -f aim-qwen3-32b-scalable.yaml

# 6. Access Grafana dashboard (optional - requires observability setup)
# First, verify LGTM/Grafana pod is Running and Ready
kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana"
# If no pods found, verify observability stack is installed: kubectl get pods -n otel-lgtm-stack
# If pod is Pending (e.g., 0/2 Pending), wait for it: LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1) && kubectl wait --for=condition=ready pod -n otel-lgtm-stack $LGTM_POD --timeout=600s

# For remote access: Set up SSH port forwarding first (on local machine)
# ssh -L 3000:localhost:3000 user@remote-mi300x-node
# Keep SSH session open!

# Port forward Grafana service (on remote node)
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000
# Keep this terminal open!

# Open http://localhost:3000 in browser (on local machine if remote, or on remote node if local)
# Default credentials: admin/admin

# 7. Generate inference requests to view metrics and autoscaling (optional)
# For remote access: Set up SSH port forwarding for port 8080 (on local machine)
# ssh -L 8080:localhost:8080 user@remote-mi300x-node
# Or add to existing SSH: ssh -L 8000:localhost:8000 -L 3000:localhost:3000 -L 8080:localhost:8080 user@remote-mi300x-node
# Keep SSH session open!

# Port-forward the scalable service (on remote node)
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
# Keep this terminal open!

# In a new terminal (or if using SSH, on your local machine), send inference requests
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Monitor autoscaling
kubectl get deployment aim-qwen3-32b-scalable-predictor-00001-deployment -w
```

For detailed step-by-step instructions, continue reading the sections below.

## Step 1: Get the Deployment Repository

This step downloads the official AIM deployment repository from AMD, which contains all necessary KServe manifests and installation scripts.

### Step 1.1: Clone the Repository

**Command:**
```bash
git clone https://github.com/amd-enterprise-ai/aim-deploy.git
```

**Expected Output:**
```
Cloning into 'aim-deploy'...
remote: Enumerating objects: XXX, done.
remote: Counting objects: 100% (XXX/XXX), done.
remote: Compressing objects: 100% (XXX/XXX), done.
remote: Total XXX (delta XXX), reused XXX (delta XXX), pack-reused XXX
Receiving objects: 100% (XXX/XXX), XXX MiB | XXX.XX MiB/s, done.
Resolving deltas: 100% (XXX/XXX), done.
```

**What to Check:**
- Repository cloned successfully
- No network errors
- Directory `aim-deploy` created

**Verify Repository Structure:**
```bash
ls -la aim-deploy/
```

**Expected Output:**
```
total XX
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 .
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 ..
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 kserve
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 docker
...
```

**What to Check:**
- `kserve` directory exists
- Repository structure is correct

### Step 1.2: Navigate to KServe Installation Directory

**Command:**
```bash
cd aim-deploy/kserve/kserve-install
```

**Expected Output:**
```bash
# No output, just changes directory
```

**Verify Current Directory:**
```bash
pwd
```

**Expected Output:**
```
/path/to/aim-deploy/kserve/kserve-install
```

**List Installation Files:**
```bash
ls -la
```

**Expected Output:**
```
total XX
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 .
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 ..
-rwxr-xr-x  XX root root  XXXX Nov 27 15:00 install-deps.sh
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 post-helm
...
```

**What to Check:**
- `install-deps.sh` script exists
- `post-helm` directory exists (for observability components)

**Troubleshooting:**
- If directory not found: Verify repository structure with `find aim-deploy -name "kserve-install"`
- If permission denied: Check file permissions with `ls -l install-deps.sh`

---

## Step 2: Install KServe Infrastructure

This step installs the core KServe components including cert-manager, Gateway API CRDs, KServe CRDs, and the KServe controller for model serving.

### Step 2.1: Verify Prerequisites

**Check Helm Installation:**

**Command:**
```bash
helm version
```

**Expected Output:**
```
version.BuildInfo{Version:"v3.12.0", GitCommit:"...", GitTreeState:"clean", GoVersion:"go1.20.5"}
```

**What to Check:**
- Helm version is 3.8 or higher
- Helm is properly installed

**Check Cluster Admin Access:**

**Command:**
```bash
kubectl auth can-i '*' '*' --all-namespaces
```

**Expected Output:**
```
yes
```

**What to Check:**
- You have cluster admin privileges
- Can create cluster-wide resources

**Check Default Storage Class (for observability):**

**Command:**
```bash
kubectl get storageclass
```

**Expected Output (with default):**
```
NAME            PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-storage   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer   false                  83m   (default)
```

**Or:**
```
NAME                 PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard (default)   kubernetes.io/... Delete          Immediate           true                   5d
```

**What to Check:**
- At least one storage class exists
- One is marked as `(default)` in the output (either as `(default)` column or `(default)` in the name)
- If no `(default)` marker appears, you need to set one as default

**If no storage class is marked as default:**
```bash
# Set existing storage class as default (replace local-storage with your storage class name)
kubectl patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify it's now default
kubectl get storageclass
```

**Expected Output (after setting as default):**
```
NAME            PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-storage   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer   false                  83m   (default)
```

**Note:** The `(default)` marker will appear in the output when a storage class is set as default. This is **required** for observability components to work properly.

**Important:** If your storage class uses `kubernetes.io/no-provisioner` (like `local-storage`), it requires manual PersistentVolume (PV) creation. PVCs will remain Pending until matching PVs are created. See troubleshooting in Step 6.1 for solutions (create PVs manually, switch to a provisioner-based storage class, or use local-path-provisioner).

**Troubleshooting:**
- If no default storage class: Create one or specify storage class in observability config
- If Helm not found: Install Helm: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`

### Step 2.2: Install Basic KServe Infrastructure

**Command:**
```bash
bash ./install-deps.sh --enable=full
```

**This installs:**
- **cert-manager**: For TLS certificate management
- **Gateway API CRDs**: For ingress and routing
- **KServe CRDs**: Custom Resource Definitions for InferenceService and ServingRuntime
- **KServe controller**: The controller that manages inference services
- **OpenTelemetry LGTM stack**: Loki (logs), Grafana (visualization), Tempo (traces), Mimir (metrics)
- **OpenTelemetry Collectors**: Configured for vLLM metrics scraping
- **KEDA (Kubernetes Event-driven Autoscaling)**: For custom metrics-based autoscaling

**Expected Output:**
```
Installing cert-manager...
cert-manager installed successfully
Installing Gateway API CRDs...
Gateway API CRDs installed successfully
Installing KServe CRDs...
KServe CRDs installed successfully
Installing KServe controller...
KServe controller installed successfully
Installing OpenTelemetry LGTM stack...
OpenTelemetry LGTM stack installed successfully
Installing KEDA...
KEDA installed successfully
Installation complete!
```

**What to Check:**
- No error messages
- All components installed successfully
- Installation script completes

**This installs:**
- **cert-manager**: For TLS certificate management
- **Gateway API CRDs**: For ingress and routing
- **KServe CRDs**: Custom Resource Definitions for InferenceService and ServingRuntime
- **KServe controller**: The controller that manages inference services

**Verify Installation:**

**Check cert-manager:**
```bash
kubectl get pods -n cert-manager
```

**Expected Output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-xxxxx                       1/1     Running   0          2m
cert-manager-cainjector-xxxxx           1/1     Running   0          2m
cert-manager-webhook-xxxxx               1/1     Running   0          2m
```

**What to Check:**
- All cert-manager pods are Running
- Status is Ready (1/1)

**Check KServe:**
```bash
kubectl get pods -n kserve
```

**Expected Output:**
```
NAME                              READY   STATUS    RESTARTS   AGE
kserve-controller-manager-xxxxx   1/1     Running   0          2m
```

**What to Check:**
- KServe controller is Running
- Status is Ready (1/1)

**Check KServe CRDs:**
```bash
kubectl get crd | grep kserve
```

**Expected Output:**
```
clusterservingruntimes.serving.kserve.io          2024-11-27T15:00:00Z
inferenceservices.serving.kserve.io               2024-11-27T15:00:00Z
servingruntimes.serving.kserve.io                 2024-11-27T15:00:00Z
trafficsplits.serving.kserve.io                   2024-11-27T15:00:00Z
```

**What to Check:**
- All KServe CRDs are present
- CRDs include InferenceService and ServingRuntime

**Troubleshooting:**
- If pods not starting: Check cluster resources: `kubectl describe pod -n kserve`
- If CRDs not found: Wait a few minutes for CRDs to be registered
- If installation fails: Check logs: `kubectl logs -n kserve deployment/kserve-controller-manager`

### Step 2.3: Install Observability and Autoscaling (Optional)

**For deployment with observability and autoscaling:**

**Command:**
```bash
bash ./install-deps.sh --enable=otel-lgtm-stack-standalone,keda
```

**Expected Output:**
```
Installing cert-manager...
...
Installing OpenTelemetry LGTM stack...
OpenTelemetry LGTM stack installed successfully
Installing KEDA...
KEDA installed successfully
Installation complete!
```

**What to Check:**
- No error messages
- All components installed successfully

**This additionally installs:**
- **OpenTelemetry LGTM Stack**: Loki (logs), Grafana (visualization), Tempo (traces), Mimir (metrics)
- **OpenTelemetry Collectors**: Configured for vLLM metrics scraping
- **KEDA (Kubernetes Event-driven Autoscaling)**: For custom metrics-based autoscaling

**Verify Observability Stack:**

**Check OpenTelemetry namespace:**
```bash
kubectl get pods -n otel-lgtm-stack
```

**Expected Output:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
lgtm-stack-xxxxx                       1/1     Running   0          3m
grafana-xxxxx                          1/1     Running   0          3m
...
```

**What to Check:**
- Observability pods are Running
- Status is Ready

**Verify KEDA:**
```bash
kubectl get pods -n keda
```

**Expected Output:**
```
NAME                              READY   STATUS    RESTARTS   AGE
keda-operator-xxxxx              1/1     Running   0          3m
keda-metrics-apiserver-xxxxx      1/1     Running   0          3m
```

**What to Check:**
- KEDA pods are Running
- Status is Ready

**Note:** If you don't have a default storage class, you may need to configure storage in `./post-helm/base/otel-lgtm-stack-standalone/otel-lgtm.yaml` before running the installation.

**Troubleshooting:**
- If storage class issues: Edit the observability YAML to specify a storage class
- If pods pending: Check PVC creation: `kubectl get pvc -n otel-lgtm-stack`
- If installation fails: Review installation logs for specific errors

---

## Step 3: Deploy Basic AIM Inference Service

This step deploys a ClusterServingRuntime (container specification) and InferenceService (compute resources and endpoint) for Qwen3-32B.

### Step 3.1: Navigate to Sample Deployment Directory

**Command:**
```bash
cd ../sample-minimal-aims-deployment
```

**Expected Output:**
```bash
# No output, just changes directory
```

**List Available Manifests:**
```bash
ls -la
```

**Expected Output:**
```
total XX
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 .
drwxr-xr-x  XX root root  XXXX Nov 27 15:00 ..
-rw-r--r--  XX root root  XXXX Nov 27 15:00 servingruntime-aim-qwen3-32b.yaml
-rw-r--r--  XX root root  XXXX Nov 27 15:00 aim-qwen3-32b.yaml
...
```

**What to Check:**
- `servingruntime-aim-qwen3-32b.yaml` exists
- `aim-qwen3-32b.yaml` exists

### Step 3.2: Review ServingRuntime Configuration

**Command:**
```bash
cat servingruntime-aim-qwen3-32b.yaml
```

**Expected Content:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: ClusterServingRuntime
metadata:
  name: aim-qwen3-32b-runtime
spec:
  supportedModelFormats:
    - name: aim-qwen3-32b
      version: "1"
      autoSelect: true
  multiModel: false
  grpcDataEndpoint: port:8085
  containers:
    - name: kserve-container
      image: amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
      env:
        - name: STORAGE_URI
          value: ""
```

**What to Check:**
- Image name is correct: `amdenterpriseai/aim-qwen-qwen3-32b:0.8.4`
- Model format name matches
- Container configuration looks correct

**This defines:**
- **ClusterServingRuntime**: A cluster-wide runtime specification that can be reused
- **Container image**: The AIM image to use
- **Model format**: How KServe identifies this model type

### Step 3.3: Deploy ServingRuntime

**Command:**
```bash
kubectl apply -f servingruntime-aim-qwen3-32b.yaml
```

**Expected Output:**
```
clusterservingruntime.serving.kserve.io/aim-qwen3-32b-runtime created
```

**What to Check:**
- ServingRuntime created successfully
- No error messages

**Verify ServingRuntime:**
```bash
kubectl get clusterservingruntime
```

**Expected Output:**
```
NAME                    AGE
aim-qwen3-32b-runtime   10s
```

**What to Check:**
- ServingRuntime exists
- Name matches

**View ServingRuntime Details:**
```bash
kubectl describe clusterservingruntime aim-qwen3-32b-runtime
```

**Expected Output:**
```
Name:         aim-qwen3-32b-runtime
Namespace:    
Labels:       <none>
Annotations:  <none>
API Version:  serving.kserve.io/v1beta1
Kind:         ClusterServingRuntime
Spec:
  Containers:
    Image:  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
    Name:   kserve-container
  ...
```

**What to Check:**
- Image is correct
- Configuration looks correct

**Troubleshooting:**
- If "not found" error: Verify KServe CRDs are installed (Step 2.2)
- If permission denied: Check cluster admin access

### Step 3.4: Review InferenceService Configuration

**Command:**
```bash
cat aim-qwen3-32b.yaml
```

**Expected Content:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: aim-qwen3-32b
spec:
  predictor:
    model:
      runtime: aim-qwen3-32b-runtime
      modelFormat:
        name: aim-qwen3-32b
      resources:
        limits:
          memory: "128Gi"
          cpu: "8"
          amd.com/gpu: "1"
        requests:
          memory: "64Gi"
          cpu: "4"
          amd.com/gpu: "1"
```

**What to Check:**
- Runtime name matches ServingRuntime: `aim-qwen3-32b-runtime`
- Model format matches: `aim-qwen3-32b`
- Resource limits are appropriate for your cluster
- GPU resource is specified: `amd.com/gpu: "1"`

**This defines:**
- **InferenceService**: The actual inference service instance
- **Predictor**: The model serving component
- **Resources**: CPU, memory, and GPU requirements

### Step 3.5: Deploy InferenceService

**Command:**
```bash
kubectl apply -f aim-qwen3-32b.yaml
```

**Expected Output:**
```
inferenceservice.serving.kserve.io/aim-qwen3-32b created
```

**What to Check:**
- InferenceService created successfully
- No error messages

**Monitor InferenceService Status:**
```bash
kubectl get inferenceservice aim-qwen3-32b -w
```

**Expected Output (Initial):**
```
NAME            URL   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b         False                                                                   5s
```

**Expected Output (Creating):**
```
NAME            URL   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b         False   True   aim-qwen3-32b-predictor-00001                         10s
```

**Expected Output (Ready):**
```
NAME            URL                                                                  READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b   http://aim-qwen3-32b.default.example.com   True    True   aim-qwen3-32b-predictor-00001   aim-qwen3-32b-predictor-00001   2m
```

**Press `Ctrl+C` to stop watching.**

**What to Check:**
- `READY` changes from `False` to `True`
- `LATESTREADYREVISION` appears
- URL is generated

**Check InferenceService Details:**
```bash
kubectl describe inferenceservice aim-qwen3-32b
```

**Expected Output:**
```
Name:         aim-qwen3-32b
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  serving.kserve.io/v1beta1
Kind:         InferenceService
Status:
  Address:
    URL:  http://aim-qwen3-32b.default.example.com
  Conditions:
    Type     Status  Reason
    ----     ------  ------
    Ready    True    InferenceserviceReady
  Latest Created Revision:   aim-qwen3-32b-predictor-00001
  Latest Ready Revision:     aim-qwen3-32b-predictor-00001
  URL:                        http://aim-qwen3-32b.default.example.com
```

**What to Check:**
- Status shows `Ready: True`
- URL is available
- Latest revision is ready

**Check Pods:**
```bash
kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b
```

**Expected Output:**
```
NAME                                          READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-predictor-00001-deployment-xxxxx   2/2     Running   0          3m
```

**What to Check:**
- Pod is Running
- READY shows 2/2 (main container + queue-proxy sidecar)
- Status is stable

**View Pod Logs:**
```bash
kubectl logs -l serving.kserve.io/inferenceservice=aim-qwen3-32b -c kserve-container --tail=50
```

**Expected Output:**
```
[INFO] Starting AIM inference service...
[INFO] Loading model: qwen3-32b
[INFO] Model loaded successfully
[INFO] Service ready on port 8080
```

**What to Check:**
- No error messages
- Model loaded successfully
- Service is ready

**Troubleshooting:**
- If pod not starting: Check resource availability: `kubectl describe pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b`
- If image pull errors: Verify image name and registry access
- If GPU not available: Check node labels and GPU device plugin

---

## Step 4: Test the Inference Endpoint

This step checks the deployment status, port-forwards the service to your local machine, and sends a test inference request to verify the service is working correctly.

### Step 4.1: Check Deployment Status

**Command:**
```bash
kubectl get inferenceservice
```

**Expected Output:**
```
NAME            URL                                                                  READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b   http://aim-qwen3-32b.default.example.com   True    True   aim-qwen3-32b-predictor-00001   aim-qwen3-32b-predictor-00001   5m
```

**What to Check:**
- `READY` is `True`
- URL is available
- Latest revision is ready

**KServe automatically creates a service with the name `<inferenceservice-name>-predictor` (in this case `aim-qwen3-32b-predictor`) that exposes port 80 by default.**

**Check Service:**
```bash
kubectl get svc aim-qwen3-32b-predictor
```

**Expected Output:**
```
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
aim-qwen3-32b-predictor   ClusterIP   10.96.123.45    <none>        80/TCP    5m
```

**What to Check:**
- Service exists
- Port 80 is exposed
- ClusterIP is assigned

### Step 4.2: Port Forward to Service

**If accessing remotely via SSH**, you need to set up SSH port forwarding first.

#### Step 4.2.1: Set Up SSH Port Forwarding (For Remote Access)

**On your local machine, establish SSH connection with port forwarding:**

```bash
# SSH to the remote MI300X node with port forwarding for AIM service (port 8000)
ssh -L 8000:localhost:8000 user@remote-mi300x-node

# Keep this SSH session open!
```

**Or add to existing SSH connection:**
```bash
# If you already have SSH with other ports, add port 8000
ssh -L 8000:localhost:8000 -L 3000:localhost:3000 user@remote-mi300x-node
```

**Alternative: Use SSH config (see Step 6.2.1 for details)**

#### Step 4.2.2: Port Forward AIM Service (On Remote Node)

**On the remote node (in your SSH session or directly if local), first verify the service exists:**

```bash
# Check if the basic InferenceService exists
kubectl get inferenceservice aim-qwen3-32b

# Check if the service exists
kubectl get svc aim-qwen3-32b-predictor
```

**Expected Output:**
```
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
aim-qwen3-32b-predictor   ClusterIP   10.96.123.45    <none>        80/TCP    10m
```

**If service not found:**
- Check if InferenceService exists: `kubectl get inferenceservice`
- If you completed Step 4.5, the basic service was deleted. Use the scalable service instead (port 8080)
- Or the service may still be creating - wait a few minutes and check again

**If service exists, proceed with port-forward:**

**Command:**
```bash
kubectl port-forward service/aim-qwen3-32b-predictor 8000:80
```

**Expected Output:**
```
Forwarding from 127.0.0.1:8000 -> 80
Forwarding from [::1]:8000 -> 80
```

**What to Check:**
- Port forwarding started successfully
- No connection errors
- Keep this terminal open (don't close it)

**For Remote Access:**
- If you're accessing via SSH, the port-forwarded service will be available on your local machine at `http://localhost:8000`
- Make sure your SSH connection with port forwarding is active (Step 4.2.1)
- Make sure kubectl port-forward is running on the remote node (Step 4.2.2)
- Both connections must stay open for the tunnel to work

**Connection Chain for Remote Access:**
```
Your Browser/curl (local machine) 
  -> http://localhost:8000 (local machine)
  -> SSH tunnel (port 8000 forward)
  -> localhost:8000 (remote node)
  -> kubectl port-forward
  -> AIM service (port 80 in cluster)
```

**For Local Access:**
- If you're running kubectl directly on the node, the service is available at `http://localhost:8000`
- Only the kubectl port-forward needs to stay open

**In Another Terminal, Test Connection:**
```bash
curl http://localhost:8000/v1/models
```

**Expected Output:**
```json
{
  "models": [
    {
      "name": "aim-qwen3-32b",
      "ready": true
    }
  ]
}
```

**What to Check:**
- Connection successful
- Model is listed
- Model status is ready

### Step 4.3: Send Test Inference Request

**Command:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}'
```

**Expected Output (raw streaming - not recommended for readability):**
```
data: {"id":"chatcmpl-1234567890","object":"chat.completion.chunk",...}
data: {"id":"chatcmpl-1234567890","object":"chat.completion.chunk",...}
data: [DONE]
```

**Better: Use formatted streaming output:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo
```

**Expected Output (formatted):**
```
Hello! How can I help you today?
```

**Or for real-time token-by-token display:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     while IFS= read -r line; do
       if [[ $line == data:* ]]; then
         content=$(echo "$line" | sed 's/^data: //' | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
         if [[ -n "$content" ]]; then
           echo -n "$content"
         fi
       elif [[ $line == "[DONE]" ]]; then
         echo
         break
       fi
     done
```

**Expected Output (real-time streaming):**
```
Hello! How can I help you today?
```

**Note:** The formatted commands extract only the content tokens and display them cleanly, making the streaming output much more readable.

**What to Check:**
- Response is valid JSON
- Chat completion is generated
- Token usage is reported
- Response time is reasonable (may take 10-30 seconds for first request)

**Formatted Streaming Output (recommended):**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo
```

**Expected Output:**
```
Hello! How can I help you today?
```

**Alternative: Real-time Token Display:**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     while IFS= read -r line; do
       if [[ $line == data:* ]]; then
         content=$(echo "$line" | sed 's/^data: //' | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
         [[ -n "$content" ]] && echo -n "$content"
       elif [[ $line == "[DONE]" ]]; then
         echo && break
       fi
     done
```

**Expected Output (tokens appear in real-time):**
```
Hello! How can I help you today?
```

**Note:** The formatted commands extract only the content tokens and display them as a clean, readable response. The `--no-buffer` flag ensures real-time streaming.

**What to Check:**
- JSON is properly formatted
- All expected fields are present
- Response makes sense

**Troubleshooting:**
- **If error "services 'aim-qwen3-32b-predictor' not found"**:
  - Check if InferenceService exists: `kubectl get inferenceservice aim-qwen3-32b`
  - If you completed Step 4.5, the basic service was deleted. Use the scalable service instead:
    ```bash
    kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8000:80
    ```
  - Or if service is still creating, wait a few minutes: `kubectl get inferenceservice aim-qwen3-32b -w`
  
- If connection refused: Verify port-forward is still running
- If timeout: Model may still be loading, wait and retry
- If 500 error: Check pod logs: `kubectl logs -l serving.kserve.io/inferenceservice=aim-qwen3-32b -c kserve-container`

---

## Step 4.5: Deploy Scalable Service for Metrics (Optional)

**Note:** The scalable service (`aim-qwen3-32b-scalable`) has `VLLM_ENABLE_METRICS=true` which enables metrics collection for Grafana. The basic service does not export metrics.

**GPU Resource Requirements:**
- **Single GPU node**: You need to stop the basic service first to free the GPU (see Step 4.5.1)
- **Multiple GPU node (e.g., 8x MI300X)**: You can run both services simultaneously - skip Step 4.5.1 and proceed directly to Step 4.5.2

**Check your GPU availability:**
```bash
# Check how many GPUs are available
kubectl describe node $(kubectl get nodes -o name | head -1) | grep -A 5 "amd.com/gpu"
```

**If you have multiple GPUs (e.g., 8x MI300X):**
- You can keep the basic service running
- Deploy the scalable service alongside it
- Both services will run simultaneously
- Proceed directly to Step 4.5.2 (skip Step 4.5.1)

### Step 4.5.1: Stop the Basic Service (Single GPU Only)

**⚠️ Only needed if you have a single GPU node.**

**If you have multiple GPUs (e.g., 8x MI300X):**
- **Skip this step** - You can run both services simultaneously
- Proceed directly to Step 4.5.2

**If you only have one GPU:**

**Delete the basic InferenceService to free the GPU:**
```bash
kubectl delete inferenceservice aim-qwen3-32b
```

**Expected Output:**
```
inferenceservice.serving.kserve.io "aim-qwen3-32b" deleted
```

**Verify the basic service is removed:**
```bash
kubectl get inferenceservice
```

**Expected Output:**
```
NAME                     URL   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable                                                                               51m
```

**What to Check:**
- Basic service (`aim-qwen3-32b`) is no longer listed
- Scalable service exists (may show as not READY yet)

### Step 4.5.2: Deploy and Wait for Scalable Service to Start

**If you skipped Step 4.5.1 (multiple GPUs):**
- The scalable service should already be deployed from Step 5
- Check if it exists: `kubectl get inferenceservice aim-qwen3-32b-scalable`
- If it exists, proceed to check status below
- If it doesn't exist, deploy it following Step 5 instructions

**If you completed Step 4.5.1 (single GPU):**
- The scalable service should start now that the GPU is free
- Proceed to check status below

**Check scalable service status:**
```bash
kubectl get inferenceservice aim-qwen3-32b-scalable -w
```

**Expected Output (Initial):**
```
NAME                     URL   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable                                                                               51m
```

**Expected Output (Creating):**
```
NAME                     URL   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable           False   True   aim-qwen3-32b-scalable-predictor-00001                         52m
```

**Expected Output (Ready):**
```
NAME                     URL                                                              READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable   http://aim-qwen3-32b-scalable.default.example.com   True    True   aim-qwen3-32b-scalable-predictor-00001   aim-qwen3-32b-scalable-predictor-00001   53m
```

**Press `Ctrl+C` to stop watching once READY shows `True`.**

**Or wait automatically:**
```bash
kubectl wait --for=condition=ready inferenceservice aim-qwen3-32b-scalable --timeout=600s
```

**While waiting, monitor progress in another terminal:**

**Check InferenceService status:**
```bash
kubectl get inferenceservice aim-qwen3-32b-scalable
```

**Watch InferenceService status (updates every 2 seconds):**
```bash
watch -n 2 kubectl get inferenceservice aim-qwen3-32b-scalable
```

**Check pod status:**
```bash
kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
```

**Watch pod status:**
```bash
watch -n 2 kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
```

**Check pod events (if pod is Pending or not starting):**
```bash
SCALABLE_POD=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$SCALABLE_POD" ]; then
  kubectl describe pod $SCALABLE_POD | grep -A 20 "Events:"
fi
```

**Check pod logs (if container is running):**
```bash
SCALABLE_POD=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$SCALABLE_POD" ]; then
  kubectl logs $SCALABLE_POD -c kserve-container --tail=50 -f
fi
```

**Expected progression:**
- InferenceService: No URL → URL appears → READY becomes True
- Pod: Pending → ContainerCreating → Running (0/3 → 1/3 → 2/3 → 3/3)

**Check pod status:**
```bash
kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
```

**Expected Output (Ready):**
```
NAME                                                      READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment-xxxxx   3/3     Running   0          5m
```

**If pod shows Pending or not Ready after a long time:**

**1. Check pod status and events:**
```bash
SCALABLE_POD=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$SCALABLE_POD" ]; then
  echo "Pod: $SCALABLE_POD"
  kubectl get pod $SCALABLE_POD
  echo ""
  echo "Pod events:"
  kubectl describe pod $SCALABLE_POD | grep -A 30 "Events:"
else
  echo "No pod found. Check deployment:"
  kubectl get deployment -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
fi
```

**If pod is Running (3/3) but InferenceService shows no URL/READY:**

This can happen if the KServe controller hasn't updated the InferenceService status yet, or there's a status sync issue.

**1. Check InferenceService details:**
```bash
kubectl describe inferenceservice aim-qwen3-32b-scalable | grep -A 20 "Status:"
```

**2. Check if the service exists:**
```bash
kubectl get svc aim-qwen3-32b-scalable-predictor
```

**3. If service exists and pod is Running, you can use it even if InferenceService status shows empty:**
```bash
# Port-forward directly to the service
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80

# Test the service
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo
```

**4. Check KServe controller logs (if status doesn't update):**
```bash
kubectl logs -n kserve -l control-plane=kserve-controller-manager --tail=50 | grep -i "aim-qwen3-32b-scalable"
```

**5. Force status refresh (optional):**
```bash
# Annotate the InferenceService to trigger reconciliation
kubectl annotate inferenceservice aim-qwen3-32b-scalable kubectl.kubernetes.io/last-applied-configuration- --overwrite
```

**Note:** If the pod is Running and the service exists, the InferenceService is functionally ready even if the status field is empty. You can proceed with testing.

**2. Check if GPU is available:**
```bash
# Check node GPU resources
kubectl describe node $(kubectl get nodes -o name | head -1) | grep -A 5 "amd.com/gpu"

# Check which pods are using GPUs
kubectl get pods --all-namespaces -o wide | grep -E "aim-qwen3-32b|NAME"
```

**3. Check deployment status:**
```bash
kubectl get deployment -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
kubectl describe deployment -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable | grep -A 10 "Events:"
```

**4. If pod is Pending due to GPU unavailability:**
- Verify the basic service was deleted: `kubectl get inferenceservice`
- Check if any other pods are using the GPU
- Wait a few more minutes for the GPU to be released

**What to Check:**
- Pod STATUS is `Running` (not `Pending`)
- READY shows `3/3` (main container + queue-proxy + OpenTelemetry sidecar)
- InferenceService READY is `True`

**Note:** The scalable service has 3 containers:
1. `kserve-container` - The main vLLM inference container
2. `queue-proxy` - KServe queue proxy
3. `vllm-sidecar-collector` - OpenTelemetry sidecar for metrics collection

### Step 4.5.3: Test the Scalable Service

**Port-forward to the scalable service:**
```bash
# For remote access: Set up SSH port forwarding for port 8080 first
# ssh -L 8080:localhost:8080 user@remote-mi300x-node

# Port-forward the scalable service (on remote node)
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
```

**In another terminal (or on local machine if remote), test the service:**
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo
```

**Expected Output:**
```
Hello! How can I help you today?
```

**What to Check:**
- Request succeeds
- Response is received
- Service is working correctly

**Benefits of Scalable Service:**
- ✅ Metrics enabled (`VLLM_ENABLE_METRICS=true`)
- ✅ OpenTelemetry sidecar for metrics collection
- ✅ KEDA autoscaling support
- ✅ Metrics visible in Grafana (after Step 7)

**Note on GPU Requirements:**
- **Single GPU**: You can only run one service at a time. Stop the basic service to use the scalable service.
- **Multiple GPUs (e.g., 8x MI300X)**: You can run both services simultaneously. Each service uses 1 GPU, so with 8 GPUs you have plenty of capacity for both services plus room for autoscaling.

---

## Step 5: Deploy Monitored Inference Service (Optional)

**Note:** 
- **If you completed Step 4.5 (switched to scalable service)**: The scalable InferenceService is already deployed with metrics enabled. You can skip Step 5.1 and 5.2, and proceed directly to Step 6 to view metrics in Grafana.
- **If you have multiple GPUs (e.g., 8x MI300X)**: You can deploy the scalable service alongside the basic service without stopping it. Both services will run simultaneously.

This step creates an InferenceService with OpenTelemetry sidecar injection enabled, the VLLM_ENABLE_METRICS environment variable set to true, and KEDA-based autoscaling configured to scale based on the number of running inference requests.

**Prerequisites:**
- Observability stack installed (Step 2.3)
- KEDA installed (Step 2.3)
- **GPU availability**: 
  - Single GPU: Basic service must be stopped (Step 4.5.1)
  - Multiple GPUs: Can deploy alongside basic service (no need to stop it)

### Step 5.1: Verify ServingRuntime is Applied

**Command:**
```bash
kubectl get clusterservingruntime aim-qwen3-32b-runtime
```

**Expected Output (if already applied):**
```
NAME                    AGE
aim-qwen3-32b-runtime   10m
```

**What to Check:**
- ServingRuntime exists
- No error messages

**If not found, apply it:**
```bash
# Navigate to the sample-minimal-aims-deployment directory
cd ../sample-minimal-aims-deployment
kubectl apply -f servingruntime-aim-qwen3-32b.yaml
```

**Expected Output:**
```
clusterservingruntime.serving.kserve.io/aim-qwen3-32b-runtime created
```

**What to Check:**
- ServingRuntime created successfully
- No error messages

**Note:** If you're already in the `sample-minimal-aims-deployment` directory from Step 3, you can skip the `cd` command.

### Step 5.2: Create Monitored InferenceService Manifest

**Create the inference service manifest with monitoring and autoscaling:**

**Command:**
```bash
cat <<'EOF' > aim-qwen3-32b-scalable.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: aim-qwen3-32b-scalable
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    serving.kserve.io/autoscalerClass: "keda"
    sidecar.opentelemetry.io/inject: "otel-lgtm-stack/vllm-sidecar-collector"
spec:
  predictor:
    model:
      runtime: aim-qwen3-32b-runtime
      modelFormat:
        name: aim-qwen3-32b
      env:
        - name: VLLM_ENABLE_METRICS
          value: "true"
      resources:
        limits:
          memory: "128Gi"
          cpu: "8"
          amd.com/gpu: "1"
        requests:
          memory: "64Gi"
          cpu: "4"
          amd.com/gpu: "1"
    minReplicas: 1
    maxReplicas: 3
    autoScaling:
      metrics:
        - type: External
          external:
            metric:
              backend: "prometheus"
              serverAddress: "http://lgtm-stack.otel-lgtm-stack.svc:9090"
              query: 'sum(vllm:num_requests_running{service="isvc.aim-qwen3-32b-scalable-predictor"})'
            target:
              type: Value
              value: "1"
EOF
```

**Expected Output:**
```bash
# No output, file created successfully
```

**What to Check:**
- File created successfully
- No error messages

**Verify File Contents:**
```bash
cat aim-qwen3-32b-scalable.yaml
```

**Expected Output:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: aim-qwen3-32b-scalable
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    serving.kserve.io/autoscalerClass: "keda"
    sidecar.opentelemetry.io/inject: "otel-lgtm-stack/vllm-sidecar-collector"
...
```

**What to Check:**
- YAML syntax is correct
- Annotations include KEDA autoscaler class
- OpenTelemetry sidecar injection is enabled
- VLLM_ENABLE_METRICS is set to "true"
- Autoscaling metrics query points to Prometheus
- Min/max replicas are configured (1-3)

**Key Configuration Explained:**

1. **`serving.kserve.io/autoscalerClass: "keda"`**: Uses KEDA for autoscaling instead of default HPA
2. **`sidecar.opentelemetry.io/inject: "otel-lgtm-stack/vllm-sidecar-collector"`**: Injects OpenTelemetry sidecar for metrics collection
3. **`VLLM_ENABLE_METRICS: "true"`**: Enables vLLM metrics export
4. **Autoscaling query**: Monitors `vllm:num_requests_running` metric and scales when value exceeds 1

**Troubleshooting:**
- If file creation fails: Check write permissions in current directory
- If YAML syntax error: Verify all quotes and indentation are correct
- If annotation format wrong: Ensure namespace matches observability setup

**Review the Manifest:**
```bash
cat aim-qwen3-32b-scalable.yaml
```

**What to Check:**
- Annotations include KEDA autoscaler class
- OpenTelemetry sidecar injection is enabled
- VLLM_ENABLE_METRICS is set to "true"
- Autoscaling metrics query points to Prometheus
- Min/max replicas are configured (1-3)

**Key Configuration Explained:**

1. **`serving.kserve.io/autoscalerClass: "keda"`**: Uses KEDA for autoscaling instead of default HPA
2. **`sidecar.opentelemetry.io/inject: "otel-lgtm-stack/vllm-sidecar-collector"`**: Injects OpenTelemetry sidecar for metrics collection
3. **`VLLM_ENABLE_METRICS: "true"`**: Enables vLLM metrics export
4. **Autoscaling query**: Monitors `vllm:num_requests_running` metric and scales when value exceeds 1

### Step 5.3: Apply the Monitored InferenceService

**Command:**
```bash
kubectl apply -f aim-qwen3-32b-scalable.yaml
```

**Expected Output:**
```
inferenceservice.serving.kserve.io/aim-qwen3-32b-scalable created
```

**What to Check:**
- InferenceService created successfully
- No error messages

**Monitor InferenceService Status:**
```bash
kubectl get inferenceservice aim-qwen3-32b-scalable -w
```

**Expected Output (Initial):**
```
NAME                        URL   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable           False                                                                   5s
```

**Expected Output (Creating):**
```
NAME                        URL   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable           False   True   aim-qwen3-32b-scalable-predictor-00001                         10s
```

**Expected Output (Ready):**
```
NAME                        URL                                                              READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable      http://aim-qwen3-32b-scalable.default.example.com   True    True   aim-qwen3-32b-scalable-predictor-00001   aim-qwen3-32b-scalable-predictor-00001   2m
```

**Press `Ctrl+C` to stop watching.**

**What to Check:**
- `READY` changes from `False` to `True`
- `LATESTREADYREVISION` appears
- URL is generated

**Check Pods:**
```bash
kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
```

**Expected Output:**
```
NAME                                                      READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment-xxxxx   3/3     Running   0          3m
```

**What to Check:**
- Pod is Running
- READY shows 3/3 (main container + queue-proxy + OpenTelemetry sidecar)
- Status is stable

**Verify Sidecar Injection:**
```bash
kubectl describe pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable | grep -A 5 "Containers:"
```

**Expected Output:**
```
Containers:
  kserve-container:
    ...
  queue-proxy:
    ...
  vllm-sidecar-collector:
    ...
```

**What to Check:**
- Three containers are present
- OpenTelemetry sidecar (`vllm-sidecar-collector`) is injected

**Verify KEDA ScaledObject:**
```bash
kubectl get scaledobject -n default
```

**Expected Output:**
```
NAME                                    SCALETARGETKIND      SCALETARGETNAME                              MIN   MAX   TRIGGERS   AGE
aim-qwen3-32b-scalable-predictor        Deployment           aim-qwen3-32b-scalable-predictor-00001-deployment   1     3    1         2m
```

**What to Check:**
- ScaledObject created automatically
- Min/max replicas match configuration (1-3)
- Trigger is configured

**View ScaledObject Details:**
```bash
kubectl describe scaledobject aim-qwen3-32b-scalable-predictor
```

**Expected Output:**
```
Name:         aim-qwen3-32b-scalable-predictor
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  keda.sh/v1alpha1
Kind:         ScaledObject
Spec:
  Max Replica Count:  3
  Min Replica Count:  1
  Scale Target Ref:
    Kind:  Deployment
    Name:  aim-qwen3-32b-scalable-predictor-00001-deployment
  Triggers:
    Metric Name:  prometheus-vllm-num-requests-running
    Server Address:  http://lgtm-stack.otel-lgtm-stack.svc:9090
    Query:  sum(vllm:num_requests_running{service="isvc.aim-qwen3-32b-scalable-predictor"})
    Threshold:  1
Status:
  Conditions:
    Type           Status  Reason
    ----           ------  ------
    Active         True    ScaledObjectReady
  Current Replicas:  1
  Desired Replicas:  1
```

**What to Check:**
- Prometheus query is configured correctly
- Threshold is set to 1 (scales when metric > 1)
- Server address points to Prometheus in observability namespace
- Status shows `Active: True`

**Check KEDA Operator Logs:**
```bash
kubectl logs -n keda deployment/keda-operator --tail=50
```

**Expected Output:**
```
...
ScaledObject default/aim-qwen3-32b-scalable-predictor is active, scaling Deployment default/aim-qwen3-32b-scalable-predictor-00001-deployment from 1 to 1
```

**What to Check:**
- KEDA operator is running
- ScaledObject is recognized
- No errors in logs

**Troubleshooting:**
- **If sidecar not injected**: 
  - Check annotation format: `sidecar.opentelemetry.io/inject: "otel-lgtm-stack/vllm-sidecar-collector"`
  - Verify namespace matches: `otel-lgtm-stack`
  - Check OpenTelemetry operator is running: `kubectl get pods -n otel-lgtm-stack | grep operator`
  
- **If KEDA not creating ScaledObject**:
  - Verify KEDA is installed: `kubectl get pods -n keda`
  - Check KEDA operator logs: `kubectl logs -n keda deployment/keda-operator`
  - Verify autoscaler class annotation: `serving.kserve.io/autoscalerClass: "keda"`
  
- **If metrics not appearing**:
  - Check OpenTelemetry collector logs: `kubectl logs -l app=vllm-sidecar-collector -n default`
  - Verify VLLM_ENABLE_METRICS is set: `kubectl get pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o yaml | grep VLLM_ENABLE_METRICS`
  - Check Prometheus can scrape metrics: `kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090` then query in Prometheus UI

---

## Step 6: Access Grafana Dashboard (Optional)

This step forwards the Grafana service port to your local machine, enabling access to the monitoring dashboard where you can view metrics, logs, and traces.

**Prerequisites:**
- Observability stack installed (Step 2.3)

### Step 6.1: Verify Grafana is Running

**First, verify the observability stack namespace exists:**
```bash
kubectl get namespace otel-lgtm-stack
```

**Expected Output:**
```
NAME              STATUS   AGE
otel-lgtm-stack   Active   10m
```

**If namespace doesn't exist**, the observability stack may not be installed. Refer to Step 2.3 to install it.

**Check Grafana Pod Status:**
```bash
# Try with specific label first
kubectl get pods -n otel-lgtm-stack -l app.kubernetes.io/name=grafana
```

**If no resources found, try alternative methods:**

**Method 1: Check all pods in namespace and filter for Grafana:**
```bash
kubectl get pods -n otel-lgtm-stack | grep -i grafana
```

**Method 2: Check all pods in namespace:**
```bash
kubectl get pods -n otel-lgtm-stack
```

**Method 3: Check for LGTM stack pods (Grafana may be part of a larger stack):**
```bash
kubectl get pods -n otel-lgtm-stack -l app=lgtm-stack
```

**Method 4: Search by service name:**
```bash
kubectl get pods -n otel-lgtm-stack -l app.kubernetes.io/instance=lgtm-stack
```

**Method 5: Check for pods with "lgtm" in the name (common deployment pattern):**
```bash
kubectl get pods -n otel-lgtm-stack | grep lgtm
```

**Expected Output (Ready):**
```
NAME                     READY   STATUS    RESTARTS   AGE
lgtm-xxxxx               2/2     Running   0          10m
```

**Or if Grafana is separate:**
```
NAME                     READY   STATUS    RESTARTS   AGE
lgtm-stack-grafana-xxxxx   1/1     Running   0          10m
```

**What to Check:**
- LGTM/Grafana pod is Running (not Pending)
- Status shows all containers Ready (e.g., `2/2` or `1/1`)
- Pod name contains "grafana" or "lgtm"

**Note:** The LGTM stack pod may have multiple containers (e.g., `2/2` means 2 containers, both ready). Wait until READY shows all containers ready before proceeding.

**If No Resources Found:**

**Verify observability stack is installed:**
```bash
# Check if observability components exist
kubectl get pods -n otel-lgtm-stack

# Check if Helm release exists
helm list -n otel-lgtm-stack
```

**If observability stack is not installed**, install it first:
```bash
cd aim-deploy/kserve/kserve-install
bash ./install-deps.sh --enable=full
```

**If Pod is Pending or Not Ready:**

**Find the LGTM/Grafana pod name first:**
```bash
# Get the actual pod name (try lgtm first, then grafana)
LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
echo $LGTM_POD

# Check pod status
kubectl get pod -n otel-lgtm-stack $LGTM_POD

# Then describe it to see why it's Pending
kubectl describe pod -n otel-lgtm-stack $LGTM_POD
```

**Check pod events for Pending reasons:**
```bash
kubectl describe pod -n otel-lgtm-stack $LGTM_POD | grep -A 20 "Events:"
```

**Common reasons for Pending status:**
- **Insufficient resources** (CPU/memory)
- **Storage issues** (PVC not bound) - **Most common issue**
- **Node selector/affinity** issues
- **Image pull** problems

**If you see "pod has unbound immediate PersistentVolumeClaims":**

This means the PersistentVolumeClaim (PVC) is not bound to a PersistentVolume (PV). Check and fix:

```bash
# Check PVC status
kubectl get pvc -n otel-lgtm-stack

# Check if PVC is Pending
kubectl describe pvc -n otel-lgtm-stack
```

**Common causes and solutions:**

1. **No default storage class:**
   ```bash
   # Check for default storage class
   kubectl get storageclass
   ```
   
   **Expected Output (with default):**
   ```
   NAME            PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
   local-storage   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer   false                  83m
   ```
   
   **Check if any storage class is marked as default:**
   ```bash
   kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
   ```
   
   **Or check annotations:**
   ```bash
   kubectl get storageclass -o yaml | grep -A 2 "is-default-class"
   ```
   
   **Solution:** If no storage class shows `true` for `is-default-class`, you need to set one as default:
   
   ```bash
   # Set existing storage class as default (replace local-storage with your storage class name)
   kubectl patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   
   # Verify it's now default
   kubectl get storageclass
   ```
   
   **Expected Output (after setting as default):**
   ```
   NAME            PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
   local-storage   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer   false                  83m   (default)
   ```
   
   **Note:** The `(default)` marker will appear in the output when a storage class is set as default.

2. **Storage class doesn't exist:**
   ```bash
   # Check what storage class the PVC is requesting
   kubectl get pvc -n otel-lgtm-stack -o yaml | grep storageClassName
   ```
   **Solution:** Ensure the storage class exists: `kubectl get storageclass`

3. **Insufficient storage capacity or no-provisioner storage class:**
   ```bash
   # Check available PVs
   kubectl get pv
   
   # Check PVC status
   kubectl get pvc -n otel-lgtm-stack
   ```
   
   **If using `kubernetes.io/no-provisioner` storage class:**
   
   This storage class requires manual PersistentVolume (PV) creation. PVCs will remain Pending until matching PVs are created.
   
   **Option A: Create PVs manually for each PVC:**
   ```bash
   # Check what PVCs need volumes
   kubectl get pvc -n otel-lgtm-stack
   
   # Check PVC requirements (size, access mode)
   kubectl describe pvc -n otel-lgtm-stack grafana-pvc
   ```
   
   **Example: Create a local PV for grafana-pvc (adjust path and size as needed):**
   ```bash
   # Create a directory on a node (SSH to the node first)
   sudo mkdir -p /mnt/local-storage/grafana
   sudo chmod 777 /mnt/local-storage/grafana
   
   # Create PV manifest (adjust node name, path, and size)
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolume
   metadata:
     name: grafana-pv
   spec:
     capacity:
       storage: 10Gi
     accessModes:
       - ReadWriteOnce
     persistentVolumeReclaimPolicy: Retain
     storageClassName: local-storage
     local:
       path: /mnt/local-storage/grafana
     nodeAffinity:
       required:
         nodeSelectorTerms:
         - matchExpressions:
           - key: kubernetes.io/hostname
             operator: In
             values:
             - <your-node-name>
   EOF
   ```
   
   **Repeat for each PVC** (loki-data-pvc, loki-storage-pvc, p8s-pvc, tempo-pvc).
   
   **Option B: Switch to a storage class with a provisioner (recommended for easier setup):**
   
   Install local-path-provisioner or use your cloud provider's provisioner:
   ```bash
   # Example: Install local-path-provisioner (creates PVs automatically)
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
   
   # Wait for it to be ready
   kubectl wait --for=condition=ready pod -n local-path-storage -l app=local-path-provisioner --timeout=60s
   
   # Set it as default
   kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   
   # Remove default from old storage class
   kubectl patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
   
   # Delete old PVCs and let them recreate with new storage class
   kubectl delete pvc -n otel-lgtm-stack --all
   
   # Delete the pending pod to force recreation (find pod name first)
   LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
   if [ ! -z "$LGTM_POD" ]; then
     kubectl delete pod -n otel-lgtm-stack $LGTM_POD
   fi
   
   # Or delete by deployment name
   LGTM_DEPLOYMENT=$(kubectl get deployment -n otel-lgtm-stack | grep lgtm | awk '{print $1}' | head -1)
   if [ ! -z "$LGTM_DEPLOYMENT" ]; then
     kubectl delete deployment -n otel-lgtm-stack $LGTM_DEPLOYMENT
   fi
   
   # Wait a few seconds for resources to be recreated
   sleep 10
   
   # Check PVC status - they should now be Bound automatically
   kubectl get pvc -n otel-lgtm-stack
   
   # If PVCs show STORAGECLASS as "default" instead of "local-path", check what "default" points to
   # The PVCs might be using an explicit "default" storage class name
   kubectl get storageclass
   kubectl get pvc -n otel-lgtm-stack -o yaml | grep storageClassName
   
   # If PVCs are using "default" but you want them to use "local-path", you can patch them:
   # kubectl patch pvc grafana-pvc -n otel-lgtm-stack -p '{"spec":{"storageClassName":"local-path"}}'
   # (Repeat for each PVC: loki-data-pvc, loki-storage-pvc, p8s-pvc, tempo-pvc)
   
   # Or check if "default" storage class exists and what it is
   kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
   
   # If PVCs are not recreated automatically, you need to recreate them or reinstall
   # The PVCs are created during the initial installation, not by the deployment
   if [ -z "$(kubectl get pvc -n otel-lgtm-stack 2>/dev/null)" ]; then
     echo "PVCs not found. Need to recreate them or reinstall observability stack."
     echo ""
     echo "Option 1: Delete namespace and reinstall (cleanest - recommended):"
     echo "  kubectl delete namespace otel-lgtm-stack"
     echo "  # Wait for namespace to be fully deleted"
     echo "  kubectl get namespace otel-lgtm-stack  # Should show NotFound"
     echo "  cd aim-deploy/kserve/kserve-install"
     echo "  bash ./install-deps.sh --enable=full"
     echo ""
     echo "Option 2: Check deployment to see what PVCs it expects, then recreate them:"
     echo "  kubectl get deployment lgtm -n otel-lgtm-stack -o yaml | grep -A 10 -i volume"
     echo "  # Then create PVCs manually based on what the deployment expects"
     echo ""
     echo "Option 3: Restart the deployment (may trigger PVC recreation if configured):"
     echo "  kubectl rollout restart deployment lgtm -n otel-lgtm-stack"
   fi
   
   # Check pod status - it should start now that PVCs are Bound
   kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana"
   
   # Wait for pod to be ready
   LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
   if [ ! -z "$LGTM_POD" ]; then
     # First check why it's Pending
     echo "Checking pod events..."
     kubectl describe pod -n otel-lgtm-stack $LGTM_POD | grep -A 20 "Events:"
     
     # Check PVC status
     echo "Checking PVC status..."
     kubectl get pvc -n otel-lgtm-stack
     
     # Wait for pod to be ready
     kubectl wait --for=condition=ready pod -n otel-lgtm-stack $LGTM_POD --timeout=600s
   fi
   ```
   
   **Option C: Disable persistent storage in observability config (for testing only):**
   
   Edit the observability configuration to use emptyDir volumes instead of PVCs. This is not recommended for production.

4. **Fix: Set a default storage class (if none exists):**
   ```bash
   # List storage classes
   kubectl get storageclass
   
   # Check if any is already default (look for "(default)" in output or check annotations)
   kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
   ```
   
   **If no storage class is marked as default:**
   
   ```bash
   # Option 1: Set existing storage class as default (replace local-storage with your storage class name)
   kubectl patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   
   # Verify it's now default
   kubectl get storageclass
   ```
   
   **Expected Output:**
   ```
   NAME            PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
   local-storage   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer   false                  83m   (default)
   ```
   
   **Option 2: If no storage class exists, create a basic local storage class:**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: local-storage
     annotations:
       storageclass.kubernetes.io/is-default-class: "true"
   provisioner: kubernetes.io/no-provisioner
   volumeBindingMode: WaitForFirstConsumer
   EOF
   ```
   
   **Note:** `kubernetes.io/no-provisioner` requires manual PV creation. For dynamic provisioning, use a provisioner like `local-path-provisioner` or your cloud provider's provisioner.

5. **After fixing storage, delete and recreate the pod:**
   ```bash
   # If you created PVs manually, check if PVCs are now bound
   kubectl get pvc -n otel-lgtm-stack
   
   # Once PVCs are Bound, delete the pending pod (it will be recreated automatically)
   # First, find the pod name
   LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
   echo "Deleting pod: $LGTM_POD"
   kubectl delete pod -n otel-lgtm-stack $LGTM_POD
   
   # Or delete by deployment name
   LGTM_DEPLOYMENT=$(kubectl get deployment -n otel-lgtm-stack | grep lgtm | awk '{print $1}' | head -1)
   if [ ! -z "$LGTM_DEPLOYMENT" ]; then
     echo "Deleting deployment: $LGTM_DEPLOYMENT"
     kubectl delete deployment -n otel-lgtm-stack $LGTM_DEPLOYMENT
   fi
   
   # Or delete all pods in namespace (more aggressive)
   # kubectl delete pods -n otel-lgtm-stack --all
   ```
   
   **Verify PVCs are Bound:**
   ```bash
   kubectl get pvc -n otel-lgtm-stack
   ```
   
   **Expected Output (after PVs are created):**
   ```
   NAME               STATUS   VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE
   grafana-pvc        Bound    grafana-pv    10Gi       RWO            local-storage  82m
   loki-data-pvc      Bound    loki-data-pv  10Gi       RWO            local-storage  82m
   loki-storage-pvc   Bound    loki-storage  10Gi       RWO            local-storage  82m
   p8s-pvc            Bound    p8s-pv        10Gi       RWO            local-storage  82m
   tempo-pvc          Bound    tempo-pv      10Gi       RWO            local-storage  82m
   ```
   
   **What to Check:**
   - STATUS shows `Bound` (not `Pending`)
   - VOLUME column shows a volume name
   - CAPACITY shows the allocated size

**Common Issues and Solutions:**

1. **Pod is Pending - Insufficient Resources:**
   ```bash
   # Check node resources
   kubectl describe node <node-name> | grep -A 10 "Allocated resources"
   
   # Check pod events for resource issues
   kubectl describe pod -n otel-lgtm-stack -l app.kubernetes.io/name=grafana | grep -A 5 "Events:"
   ```
   **Solution:** Wait for resources to become available, or scale down other workloads

2. **Pod is Pending - Image Pull Issues:**
   ```bash
   # Check pod events for image pull errors
   kubectl describe pod -n otel-lgtm-stack -l app.kubernetes.io/name=grafana | grep -i "image\|pull"
   ```
   **Solution:** Verify image registry access, check network connectivity

3. **Pod is Pending - Storage Issues:**
   ```bash
   # Check for PVC issues
   kubectl get pvc -n otel-lgtm-stack
   kubectl describe pvc -n otel-lgtm-stack
   ```
   **Solution:** Ensure default storage class is configured, or check PVC status

**Wait for Pod to be Ready:**
```bash
# First, find the LGTM/Grafana pod
LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
echo "Waiting for pod: $LGTM_POD"

# Watch pod status until it's Running and all containers are Ready
kubectl get pods -n otel-lgtm-stack $LGTM_POD -w
```

**Or wait for pod to be ready automatically:**
```bash
# Find pod name
LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)

# Wait for all containers in pod to be ready (timeout 10 minutes)
kubectl wait --for=condition=ready pod -n otel-lgtm-stack $LGTM_POD --timeout=600s
```

**Or watch all pods in namespace:**
```bash
kubectl get pods -n otel-lgtm-stack -w
```

**Expected Output (as pod starts):**
```
NAME                     READY   STATUS    RESTARTS   AGE
lgtm-xxxxx               0/2     Pending   0          10s
lgtm-xxxxx               0/2     ContainerCreating   0          15s
lgtm-xxxxx               1/2     Running   0          30s
lgtm-xxxxx               2/2     Running   0          45s
```

**Press `Ctrl+C` to stop watching once pod shows all containers Ready (e.g., `2/2`).**

**Expected Output (as pod starts):**
```
NAME                     READY   STATUS    RESTARTS   AGE
grafana-xxxxx            0/1     Pending   0          10s
grafana-xxxxx            0/1     ContainerCreating   0          15s
grafana-xxxxx            0/1     Running   0          30s
grafana-xxxxx            1/1     Running   0          45s
```

**Press `Ctrl+C` to stop watching once pod is Running and Ready (1/1).**

**Check Grafana Service:**
```bash
kubectl get svc -n otel-lgtm-stack | grep grafana
```

**Expected Output:**
```
lgtm-stack   ClusterIP   10.96.123.46   <none>   3000/TCP   10m
```

**What to Check:**
- Service exists
- Port 3000 is exposed

**Verify Service Endpoints:**
```bash
kubectl get endpoints -n otel-lgtm-stack lgtm-stack
```

**Expected Output:**
```
NAME         ENDPOINTS              AGE
lgtm-stack   10.244.x.x:3000        10m
```

**What to Check:**
- Endpoints are populated (not empty)
- Endpoint IP matches a Running Grafana pod

### Step 6.2: Port Forward to Grafana

**Important:** Before port-forwarding, ensure the Grafana pod is Running and Ready (see Step 6.1). If the pod is Pending, wait for it to become Ready before proceeding.

**If accessing remotely via SSH**, you need to set up SSH port forwarding first. See Step 6.2.1 below.

#### Step 6.2.1: Set Up SSH Port Forwarding (For Remote Access)

**On your local machine, establish SSH connection with port forwarding:**

```bash
# SSH to the remote MI300X node with port forwarding for Grafana (port 3000)
ssh -L 3000:localhost:3000 user@remote-mi300x-node

# Keep this SSH session open!
```

**Alternative: If you already have an SSH connection, you can add port forwarding using SSH config:**

Add to your `~/.ssh/config` on your local machine:
```
Host mi300x-cluster
    HostName <remote-node-ip-or-hostname>
    User <your-username>
    LocalForward 3000 localhost:3000
```

Then connect with:
```bash
ssh mi300x-cluster
```

**Important Notes:**
- Keep the SSH session open while using port-forwarded services
- The SSH port forward creates a tunnel: `localhost:3000 (local) -> localhost:3000 (remote)`
- You can add more ports to the SSH command if needed: `-L 8000:localhost:8000 -L 3000:localhost:3000`

#### Step 6.2.2: Port Forward Grafana Service (On Remote Node)

**On the remote node (in your SSH session or directly if local), run:**

**Verify Pod is Ready (if not already checked):**
```bash
# Check for LGTM/Grafana pods
kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana"
```

**Expected Output:**
```
NAME                     READY   STATUS    RESTARTS   AGE
lgtm-xxxxx               2/2     Running   0          10m
```

**What to Check:**
- Pod STATUS is `Running` (not `Pending` or `ContainerCreating`)
- READY shows all containers ready (e.g., `2/2` or `1/1`, not `0/2` or `0/1`)
- Pod name contains "lgtm" or "grafana"

**If no pods found**, verify observability stack is installed (see Step 6.1 troubleshooting).

**If pod is Pending (e.g., `0/2 Pending`), check why:**
```bash
# Find pod name
LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)

# Check pod details
kubectl describe pod -n otel-lgtm-stack $LGTM_POD | grep -A 10 "Events:"
```

**Common issues:**
- **Insufficient resources**: Check node resources: `kubectl describe node <node-name> | grep -A 10 "Allocated resources"`
- **Storage issues (unbound PVC)**: 
  - Check PVC status: `kubectl get pvc -n otel-lgtm-stack`
  - Check PVC details: `kubectl describe pvc -n otel-lgtm-stack`
  - Check for default storage class: `kubectl get storageclass`
  - If PVC is Pending, see detailed troubleshooting in Step 6.1
- **Image pull issues**: Check events for "ImagePull" errors

**If pod is not Ready, wait for it to become Ready:**
```bash
# Find LGTM pod name
LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)

# Wait for all containers in pod to be ready (timeout 10 minutes)
kubectl wait --for=condition=ready pod -n otel-lgtm-stack $LGTM_POD --timeout=600s
```

**Expected Output:**
```
pod/lgtm-xxxxx condition met
```

**Expected Output:**
```
pod/grafana-xxxxx condition met
```

**Now proceed with port-forward:**

**Command (run on remote node):**
```bash
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000
```

**Expected Output:**
```
Forwarding from 127.0.0.1:3000 -> 3000
Forwarding from [::1]:3000 -> 3000
```

**What to Check:**
- Port forwarding started successfully
- No error messages
- Keep this terminal open (don't close it)

**For Remote Access:**
- If you're accessing via SSH, Grafana will be available on your local machine at `http://localhost:3000`
- Make sure your SSH connection with port forwarding is active (Step 6.2.1)
- Make sure kubectl port-forward is running on the remote node (Step 6.2.2)
- Both connections must stay open for the tunnel to work

**Connection Chain for Remote Access:**
```
Your Browser (local machine) 
  -> http://localhost:3000 (local machine)
  -> SSH tunnel (port 3000 forward)
  -> localhost:3000 (remote node)
  -> kubectl port-forward
  -> Grafana service (port 3000 in cluster)
```

**For Local Access:**
- If you're running kubectl directly on the node, Grafana is available at `http://localhost:3000`
- Only the kubectl port-forward needs to stay open (Step 6.2.1)
- Make sure kubectl port-forward is running on the remote node (Step 6.2.2)
- Both connections must stay open for the tunnel to work

**Connection Chain:**
```
Your Browser (local) 
  -> localhost:3000 (local machine)
  -> SSH tunnel (port 3000)
  -> localhost:3000 (remote node)
  -> kubectl port-forward
  -> Grafana service (port 3000)
```

**Troubleshooting:**
- **If error "pod is not running. Current status=Pending"**:
  - Find LGTM pod: `LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)`
  - Check current status: `kubectl get pod -n otel-lgtm-stack $LGTM_POD`
  - Check why it's Pending: `kubectl describe pod -n otel-lgtm-stack $LGTM_POD | grep -A 20 "Events:"`
  - **If you see "pod has unbound immediate PersistentVolumeClaims"**:
    - Check PVC status: `kubectl get pvc -n otel-lgtm-stack`
    - Check for default storage class: `kubectl get storageclass`
    - See detailed PVC troubleshooting in Step 6.1
  - Wait for pod to become Ready: `kubectl wait --for=condition=ready pod -n otel-lgtm-stack $LGTM_POD --timeout=600s`
  - Other common issues: insufficient resources, image pull problems
  
- **If "No resources found"**:
  - Verify observability stack is installed: `kubectl get pods -n otel-lgtm-stack`
  - Check if namespace exists: `kubectl get namespace otel-lgtm-stack`
  - If not installed, install it: `cd aim-deploy/kserve/kserve-install && bash ./install-deps.sh --enable=full`
  - Check all pods in namespace: `kubectl get pods -n otel-lgtm-stack` to see what's actually deployed
  
- **If port already in use**: Use different local port: `kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3001:3000` (and update SSH forward to 3001:localhost:3001)
  
- **If connection refused**: 
  - Verify Grafana pod is running: `kubectl get pods -n otel-lgtm-stack | grep grafana`
  - Check service endpoints: `kubectl get endpoints -n otel-lgtm-stack lgtm-stack`
  - Verify pod is ready: `kubectl get pods -n otel-lgtm-stack -l app.kubernetes.io/name=grafana`

### Step 6.3: Access Grafana UI

**Open Browser:**
- Navigate to: http://localhost:3000

**Expected Behavior:**
- Browser loads Grafana login page
- No connection errors

**Login:**
- Default username: `admin`
- Default password: `admin`
- **Important:** Change password on first login (Grafana will prompt you)

**What to Check:**
- Grafana UI loads successfully
- Login page appears
- Login works with default credentials

**After Login:**
- You may be prompted to change the password
- Home dashboard appears
- Navigation menu is visible

**Troubleshooting:**
- If page doesn't load: Verify port-forward is still running
- If connection refused: Check Grafana pod status: `kubectl get pods -n otel-lgtm-stack | grep grafana`
- If login fails: Verify you're using the correct credentials (admin/admin)

### Step 6.4: Verify Data Source

**Navigate to Configuration > Data Sources**

**In Grafana UI:**
1. Click the gear icon (⚙️) in the left sidebar
2. Select "Data sources"
3. Look for "Prometheus" data source

**Expected Output:**
- Prometheus data source is listed
- Status shows "Working" or green checkmark
- URL shows: `http://lgtm-stack.otel-lgtm-stack.svc:9090`

**Test Data Source:**
1. Click on the Prometheus data source
2. Click "Test" or "Save & Test" button

**Expected Output:**
```
Data source is working
```

**If you get "We're having trouble finding that site" or connection error:**

**Important:** The URL `http://lgtm-stack.otel-lgtm-stack.svc:9090` is a Kubernetes service URL that only works from within the cluster, not from your browser. Grafana (running in the cluster) should be able to reach it, but the browser test might fail.

**1. Verify Prometheus service exists and is running:**
```bash
# Check if Prometheus service exists
kubectl get svc -n otel-lgtm-stack | grep prometheus

# Or check lgtm-stack service (which includes Prometheus)
kubectl get svc -n otel-lgtm-stack lgtm-stack
```

**Expected Output:**
```
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                                   AGE
lgtm-stack   ClusterIP   10.106.212.140   <none>        3000/TCP,4317/TCP,4318/TCP,9090/TCP,3100/TCP              93m
```

**2. Check if Prometheus is accessible from within the cluster:**
```bash
# Port-forward to Prometheus to test
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090

# In another terminal, test from the cluster
kubectl run -it --rm test-prometheus --image=curlimages/curl --restart=Never -- \
  curl http://lgtm-stack.otel-lgtm-stack.svc:9090/api/v1/status/config
```

**3. Verify the URL format is correct:**
- Service name: `lgtm-stack`
- Namespace: `otel-lgtm-stack`
- Port: `9090`
- Full URL: `http://lgtm-stack.otel-lgtm-stack.svc:9090`

**4. If the test fails in Grafana but Prometheus is running:**

**Option A: Try accessing Prometheus directly to verify it works:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090

# Access in browser: http://localhost:9090
# (Make sure SSH port forwarding for 9090 is set up if remote)
```

**Option B: Check Grafana pod can reach Prometheus:**
```bash
# Get Grafana pod name
GRAFANA_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)

# Test connectivity from Grafana pod
kubectl exec -n otel-lgtm-stack $GRAFANA_POD -c grafana -- \
  wget -qO- http://lgtm-stack.otel-lgtm-stack.svc:9090/api/v1/status/config | head -20
```

**5. If Prometheus is not accessible, check Prometheus pod:**
```bash
# Check if Prometheus is part of lgtm-stack pod
kubectl get pods -n otel-lgtm-stack | grep lgtm

# Check pod logs
kubectl logs -n otel-lgtm-stack -l app=lgtm-stack --tail=50 | grep -i prometheus
```

**6. Alternative: Use the service ClusterIP directly:**
```bash
# Get the ClusterIP
CLUSTER_IP=$(kubectl get svc -n otel-lgtm-stack lgtm-stack -o jsonpath='{.spec.clusterIP}')
echo "Use this URL in Grafana: http://${CLUSTER_IP}:9090"
```

**Note:** The ClusterIP approach works but is less stable (IP may change). The service name approach is preferred.

**What to Check:**
- Prometheus connection works from within the cluster
- URL format is correct: `http://lgtm-stack.otel-lgtm-stack.svc:9090`
- Service exists and has endpoints
- Grafana pod can reach Prometheus service

**Troubleshooting:**
- If data source not found: It may need to be configured manually
- If test fails: Check Prometheus is accessible: `kubectl get svc -n otel-lgtm-stack | grep prometheus`
- If URL is wrong: Update data source URL to match your Prometheus service

### Step 6.5: View vLLM Metrics Dashboard

**Grafana has two ways to view metrics:**
1. **Explore** - For ad-hoc queries and exploration
2. **Dashboards** - For pre-configured visualizations

#### Step 6.5.1: Use Grafana Explore to Query Metrics

**Navigate to Explore:**

1. Click the compass icon (🧭) or "Explore" in the left sidebar
2. Select "Prometheus" as the data source (top of the page)
3. You should see a query editor

**If Explore page is empty:**

**1. Verify Prometheus data source is configured:**
- Click the gear icon (⚙️) in the left sidebar
- Go to "Data sources"
- Click on "Prometheus"
- Verify URL is: `http://lgtm-stack.otel-lgtm-stack.svc:9090`
- Click "Test" to verify connection

**2. Try a simple query to test:**
```
up
```

**Expected:** You should see metrics for all targets that Prometheus is scraping.

**3. Query vLLM metrics (after sending inference requests):**

**Check if vLLM metrics are available:**
```
vllm_num_requests_total
```

**Or check running requests:**
```
vllm_num_requests_running
```

**Or check request rate:**
```
rate(vllm_num_requests_total[5m])
```

**4. If no metrics appear:**
- Make sure you've sent some inference requests (Step 7)
- Wait a few minutes for metrics to be scraped
- Check Prometheus directly: Port-forward to Prometheus and query there (see troubleshooting)

**If vLLM queries return empty in Grafana:**

**1. Verify you've sent inference requests:**
- Make sure you've completed Step 7 and sent requests to the AIM service
- Wait 2-3 minutes for metrics to be scraped and aggregated

**2. Check if vLLM metrics exist in Prometheus:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090

# In browser (or with curl), go to: http://localhost:9090
# Try query: vllm_num_requests_total
# Or check what metrics are available: Go to Status > Targets and see if vLLM is being scraped
```

**3. Check if OpenTelemetry sidecar is collecting metrics:**
```bash
# Check if the scalable service has the sidecar (it should have VLLM_ENABLE_METRICS=true)
kubectl get pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o yaml | grep -A 5 VLLM_ENABLE_METRICS

# Check sidecar collector logs
kubectl logs -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -c vllm-sidecar-collector --tail=50
```

**4. Check Prometheus targets:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090

# In browser: http://localhost:9090/targets
# Look for vLLM-related targets
# Check if targets are "UP" (green) or "DOWN" (red)
```

**5. Verify service name in queries matches your InferenceService:**
```bash
# Get your InferenceService name
kubectl get inferenceservice

# The service name in metrics should match: isvc.<inferenceservice-name>-predictor
# For example: isvc.aim-qwen3-32b-scalable-predictor
```

**6. Try querying with service label:**
```
vllm_num_requests_total{service="isvc.aim-qwen3-32b-scalable-predictor"}
```

**Or if using basic service (which may not have metrics enabled):**
```
vllm_num_requests_total{service="isvc.aim-qwen3-32b-predictor"}
```

**7. Important: Only scalable service exports metrics:**
- The basic service (`aim-qwen3-32b`) does NOT have `VLLM_ENABLE_METRICS=true`
- Only the scalable service (`aim-qwen3-32b-scalable`) has metrics enabled
- If you only have one GPU and the scalable service is Pending, metrics won't be available

**8. List all available metrics in Prometheus:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090

# In browser: http://localhost:9090
# Go to Status > Targets or use the query: {__name__=~"vllm.*"}
# This will show all metrics starting with "vllm"
```

#### Step 6.5.2: Create or Import Dashboards

**Navigate to Dashboards:**

**In Grafana UI:**
1. Click the dashboard icon (📊) in the left sidebar
2. Select "Browse" or "Dashboards"
3. Look for vLLM or AIM-related dashboards

**Expected Dashboards:**
- vLLM metrics dashboard
- AIM inference metrics
- Request rate and latency graphs
- GPU utilization graphs

**If Dashboards Are Pre-configured:**
- Dashboards should appear in the list
- Click to open and view metrics

**If No Dashboards Found - Create a Custom Dashboard:**

**Option 1: Create a New Dashboard Manually**

1. Click "+" icon → "Create" → "Dashboard"
2. Click "Add visualization" or "Add panel"
3. Select "Prometheus" as data source
4. Add panels with these queries:

**Panel 1: Request Rate**
- Query: `rate(vllm_num_requests_total[5m])`
- Visualization: Graph
- Title: "Request Rate"

**Panel 2: Running Requests**
- Query: `vllm_num_requests_running`
- Visualization: Graph
- Title: "Running Requests"

**Panel 3: Request Latency (p95)**
- Query: `histogram_quantile(0.95, rate(vllm_request_duration_seconds_bucket[5m]))`
- Visualization: Graph
- Title: "Request Latency (p95)"

**Panel 4: Replica Count**
- Query: `count(kube_pod_status_phase{pod=~"aim-qwen3-32b.*", phase="Running"})`
- Visualization: Stat
- Title: "Pod Replicas"

5. Click "Save dashboard" (top right)
6. Give it a name like "AIM vLLM Metrics"

**Option 2: Import a Dashboard JSON**

You can create a dashboard JSON file or find one online. To import:

1. Click "+" icon → "Import"
2. Paste dashboard JSON or upload file
3. Select Prometheus as data source
4. Click "Import"

**Option 3: Use Grafana Explore for Quick Queries**

If you just want to explore metrics without creating dashboards:
1. Use Explore (Step 6.5.1) to run queries
2. Click "Add to dashboard" if you want to save a query as a panel

**Expected Output (when viewing dashboard):**
- Dashboard displays graphs and panels
- Metrics show data (after sending requests in Step 7)
- No "No data" messages
- Graphs update in real-time

**What to Check:**
- Request rate graph shows data
- Latency graphs show data (p50, p95, p99)
- Resource usage graphs show data (CPU, memory, GPU)
- Time range is correct
- Metrics update when new requests arrive

**Common Metrics to Query in Explore or Dashboards:**

**Basic vLLM Metrics:**
- **Request Rate**: `rate(vllm_num_requests_total[5m])`
- **Running Requests**: `vllm_num_requests_running`
- **Request Latency (p50)**: `histogram_quantile(0.50, rate(vllm_request_duration_seconds_bucket[5m]))`
- **Request Latency (p95)**: `histogram_quantile(0.95, rate(vllm_request_duration_seconds_bucket[5m]))`
- **Request Latency (p99)**: `histogram_quantile(0.99, rate(vllm_request_duration_seconds_bucket[5m]))`

**Resource Metrics:**
- **GPU Utilization**: `gpu_utilization_percent` or `DCGM_FI_DEV_GPU_UTIL`
- **Memory Usage**: `container_memory_usage_bytes{pod=~"aim-qwen3-32b.*"}`
- **CPU Usage**: `rate(container_cpu_usage_seconds_total{pod=~"aim-qwen3-32b.*"}[5m])`

**Scaling Metrics:**
- **Pod Replica Count**: `count(kube_pod_status_phase{pod=~"aim-qwen3-32b.*", phase="Running"})`
- **KEDA ScaledObject Status**: Check KEDA metrics if autoscaling is enabled

**How to Use These Queries:**

**In Grafana Explore:**
1. Go to Explore (🧭 icon)
2. Select Prometheus data source
3. Paste the query in the query editor
4. Click "Run query" or press Shift+Enter
5. Adjust time range (top right) to see historical data

**In Dashboard Panels:**
1. Create a new panel
2. Select Prometheus data source
3. Paste the query
4. Choose visualization type (Graph, Stat, etc.)
5. Customize as needed

**Troubleshooting:**
- **If dashboard not found**: 
  - Check if dashboards are pre-configured in observability setup
  - May need to import dashboards manually
  - Or create custom dashboards using Prometheus queries
  
- **If no data**: 
  - Send some inference requests first (Step 7)
  - Wait a few minutes for metrics to be scraped
  - Check Prometheus is scraping: Query `up{job="vllm"}` in Prometheus
  
- **If graphs are empty**: 
  - Verify metrics are being collected: Check Prometheus targets
  - Check time range is correct (last 15 minutes, 1 hour, etc.)
  - Verify service name in queries matches your InferenceService
  
- **If connection refused**: 
  - Verify port-forward is still running
  - Check Grafana pod is running: `kubectl get pods -n otel-lgtm-stack | grep grafana`

---

## Step 7: Generate Inference Requests for Metrics (Optional)

This step sends inference requests to generate vLLM metrics that are collected by the OpenTelemetry sidecar and displayed through Grafana. These metrics allow you to observe how the system behaves under load, including how KEDA automatically scales service replicas as request volume increases.

**Prerequisites:**
- Monitored InferenceService deployed (Step 5)
- Grafana accessible (Step 6)

### Step 7.1: Port Forward the Scalable Service

**If accessing remotely via SSH**, you need to set up SSH port forwarding first.

#### Step 7.1.1: Set Up SSH Port Forwarding (For Remote Access)

**On your local machine, establish SSH connection with port forwarding:**

```bash
# SSH to the remote MI300X node with port forwarding for scalable AIM service (port 8080)
ssh -L 8080:localhost:8080 user@remote-mi300x-node

# Or add to existing SSH connection with other ports
ssh -L 8000:localhost:8000 -L 3000:localhost:3000 -L 8080:localhost:8080 user@remote-mi300x-node

# Keep this SSH session open!
```

**Alternative: Use SSH config (see Step 6.2.1 for details)**

#### Step 7.1.2: Port Forward Scalable Service (On Remote Node)

**On the remote node (in your SSH session or directly if local), run:**

**Command:**
```bash
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
```

**Expected Output:**
```
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

**If you get error "unable to forward port because pod is not running. Current status=Pending":**

This means the scalable InferenceService pod is not ready. Check and fix:

**1. Verify the scalable InferenceService exists:**
```bash
kubectl get inferenceservice aim-qwen3-32b-scalable
```

**Expected Output (if ready):**
```
NAME                     URL                                                              READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b-scalable   http://aim-qwen3-32b-scalable.default.example.com   True    True   aim-qwen3-32b-scalable-predictor-00001   aim-qwen3-32b-scalable-predictor-00001   10m
```

**If READY is empty or False, the pod is not ready. Check pod status:**

**2. Check pod status:**
```bash
kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
```

**Expected Output (if ready):**
```
NAME                                                      READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment-xxxxx   3/3     Running   0          10m
```

**If pod shows Pending or not Running:**

**3. If pod is Pending or InferenceService is not READY, check why:**
```bash
# Get the pod name
SCALABLE_POD=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# If pod exists, check events
if [ ! -z "$SCALABLE_POD" ]; then
  echo "Pod: $SCALABLE_POD"
  kubectl describe pod $SCALABLE_POD | grep -A 20 "Events:"
else
  echo "No pod found. Check if deployment exists:"
  kubectl get deployment -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable
fi
```

**Common causes:**
- **Insufficient GPU resources**: If you only have one GPU and it's being used by the basic service (`aim-qwen3-32b`), the scalable service cannot start. You need at least 2 GPUs to run both services simultaneously, or stop the basic service first.
- **Storage/PVC issues**: Similar to Grafana, check PVC status if the service requires storage
- **Resource constraints**: Check node resources: `kubectl describe node <node-name> | grep -A 10 "Allocated resources"`
- **Image pull issues**: Check events for "ImagePull" errors
- **Service not fully deployed**: Wait a few minutes for the service to initialize

**4. Check GPU allocation:**
```bash
# See which pods are using GPUs
kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[]?.resources.requests."amd.com/gpu") | "\(.metadata.namespace)/\(.metadata.name): \(.spec.containers[]?.resources.requests."amd.com/gpu") GPU"' 2>/dev/null

# Or check node GPU resources
kubectl describe node <node-name> | grep -A 5 "amd.com/gpu"
```

**4. If you only have one GPU:**

**Option A: Stop the basic service to free up the GPU:**
```bash
# Scale down the basic service
kubectl scale deployment --replicas=0 -l serving.kserve.io/inferenceservice=aim-qwen3-32b

# Or delete the basic InferenceService
kubectl delete inferenceservice aim-qwen3-32b

# Wait for scalable service to start
kubectl wait --for=condition=ready pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable --timeout=600s
```

**Option B: Use the basic service instead (port 8000):**
```bash
# Port-forward the basic service instead
kubectl port-forward service/aim-qwen3-32b-predictor 8080:80
```

**5. Once pod is Running, retry port-forward:**
```bash
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
```

**What to Check:**
- Port forwarding started successfully
- No error messages
- Keep this terminal open

**For Remote Access:**
- If you're accessing via SSH, the service will be available on your local machine at `http://localhost:8080`
- Make sure your SSH connection with port forwarding is active (Step 7.1.1)
- Make sure kubectl port-forward is running on the remote node (Step 7.1.2)
- Both connections must stay open for the tunnel to work

**Connection Chain for Remote Access:**
```
Your Browser/curl (local machine) 
  -> http://localhost:8080 (local machine)
  -> SSH tunnel (port 8080 forward)
  -> localhost:8080 (remote node)
  -> kubectl port-forward
  -> Scalable AIM service (port 80 in cluster)
```

**For Local Access:**
- If you're running kubectl directly on the node, the service is available at `http://localhost:8080`
- Only the kubectl port-forward needs to stay open

### Step 7.2: Send Inference Requests

**In a new terminal, send inference requests:**

**Single Request (with formatted streaming output):**
```bash
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo
```

**Expected Output:**
```
Hello! How can I help you today?
```

**What to Check:**
- Request succeeds
- Response is received
- Streaming output is formatted cleanly

**Multiple Requests (to trigger scaling):**
```bash
for i in {1..10}; do
  curl -X POST http://localhost:8080/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Request $i\"}], \"stream\": true, \"max_tokens\": 50}" \
       --no-buffer | \
       sed 's/^data: //' | \
       grep -v '^\[DONE\]$' | \
       jq -r '.choices[0].delta.content // empty' | \
       tr -d '\n' && echo &
done
wait
```

**Expected Output:**
```
Request 1 response...
Request 2 response...
Request 3 response...
...
Request 10 response...
```

**What to Check:**
- Multiple requests are sent concurrently
- All requests complete
- No errors occur
- Responses are received

**Monitor Request Status:**
```bash
# In another terminal, watch pod logs
kubectl logs -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -c kserve-container -f
```

**Expected Output:**
```
[INFO] Processing request...
[INFO] Request completed
[INFO] Processing request...
...
```

**What to Check:**
- Requests are being processed
- No errors in logs
- Multiple requests are handled

### Step 7.3: Monitor Autoscaling

**Watch Pod Replicas:**
```bash
kubectl get deployment aim-qwen3-32b-scalable-predictor-00001-deployment -w
```

**What the `-w` (watch) flag does:**
- Shows the current deployment status
- Continuously monitors and displays updates in real-time
- Updates the display when the deployment changes (replicas, pod status, etc.)
- Press `Ctrl+C` to stop watching

**Expected Output (on a single GPU node):**
```
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment   1/1     1            1           10m
```

**What you'll see:**
- **READY**: `1/1` - One pod is ready (limited by single GPU)
- **UP-TO-DATE**: `1` - One replica matches the desired state
- **AVAILABLE**: `1` - One replica is available
- The display will update if any changes occur (pod restarts, scaling attempts, etc.)

**Note on Single GPU Limitation:**
- With only one GPU, the deployment cannot scale beyond 1 replica
- KEDA may attempt to scale, but new pods will remain Pending due to insufficient GPU resources
- You'll see the deployment try to scale (UP-TO-DATE may increase), but READY will stay at 1/1
- This is expected behavior with limited GPU resources

**What You'll See on a Node with 8x MI300X GPUs (Autoscaling Enabled):**

**Initial State (low load):**
```
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment   1/3     1            1           10m
```

**As Load Increases (KEDA detects metrics and scales up):**
```
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment   1/3     1            1           10m
aim-qwen3-32b-scalable-predictor-00001-deployment   1/3     2            1           11m
aim-qwen3-32b-scalable-predictor-00001-deployment   2/3     2            2           11m
aim-qwen3-32b-scalable-predictor-00001-deployment   2/3     3            2           12m
aim-qwen3-32b-scalable-predictor-00001-deployment   3/3     3            3           12m
```

**What to Observe:**
- **UP-TO-DATE** increases from 1 → 2 → 3 as KEDA scales up
- **READY** increases from 1/3 → 2/3 → 3/3 as new pods become ready
- **AVAILABLE** increases as pods become available
- Each pod uses 1 GPU, so with 8 GPUs you can run up to 8 pods (but maxReplicas is set to 3 in the configuration)

**When Load Decreases (KEDA scales down):**
```
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment   3/3     3            3           15m
aim-qwen3-32b-scalable-predictor-00001-deployment   3/3     2            3           16m
aim-qwen3-32b-scalable-predictor-00001-deployment   2/2     2            2           16m
aim-qwen3-32b-scalable-predictor-00001-deployment   2/2     1            2           17m
aim-qwen3-32b-scalable-predictor-00001-deployment   1/1     1            1           17m
```

**Key Differences with Multiple GPUs:**
- ✅ Autoscaling actually works (pods can start, not stuck in Pending)
- ✅ Multiple replicas can run simultaneously
- ✅ READY count matches UP-TO-DATE (pods successfully start)
- ✅ You'll see scaling up and down based on load
- ✅ Better resource utilization with multiple GPUs

**To Trigger Autoscaling:**
- Send multiple concurrent inference requests (Step 7.2)
- KEDA monitors `vllm_num_requests_running` metric
- When metric exceeds threshold (1), it scales up
- When load decreases, it scales down (respecting minReplicas: 1)

**Expected Output (Initial - 1 replica):**
```
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment   1/1     1            1           5m
```

**Expected Output (Scaling Up - as requests increase):**
```
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment   1/2     2            1           5m
aim-qwen3-32b-scalable-predictor-00001-deployment   2/2     2            2           5m
aim-qwen3-32b-scalable-predictor-00001-deployment   2/3     3            2           6m
aim-qwen3-32b-scalable-predictor-00001-deployment   3/3     3            3           6m
```

**Press `Ctrl+C` to stop watching.**

**What to Check:**
- Replicas increase as load increases
- Scaling happens automatically (may take 30-60 seconds)
- Max replicas (3) is respected
- New pods become ready

**Check Current Replica Count:**
```bash
kubectl get deployment aim-qwen3-32b-scalable-predictor-00001-deployment
```

**Expected Output (after scaling):**
```
NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b-scalable-predictor-00001-deployment   3/3     3            3           10m
```

**What to Check:**
- READY shows increased replicas (up to max of 3)
- All replicas are available
- Scaling occurred based on load

**Check KEDA ScaledObject Status:**
```bash
kubectl get scaledobject aim-qwen3-32b-scalable-predictor
```

**Expected Output:**
```
NAME                                    SCALETARGETKIND      SCALETARGETNAME                              MIN   MAX   TRIGGERS   AGE
aim-qwen3-32b-scalable-predictor        Deployment           aim-qwen3-32b-scalable-predictor-00001-deployment   1     3    1         5m
```

**View ScaledObject Status Details:**
```bash
kubectl describe scaledobject aim-qwen3-32b-scalable-predictor
```

**Expected Output:**
```
...
Status:
  Conditions:
    Type           Status  Reason
    ----           ------  ------
    Active         True    ScaledObjectReady
  Current Replicas:  3
  Desired Replicas:  3
  External Metric Names:
    prometheus-vllm-num-requests-running:  2
```

**What to Check:**
- Status shows `Active: True`
- Current Replicas matches desired (scaling occurred)
- External metric value shows number of running requests
- Desired replicas increased based on metric

**View KEDA Operator Logs:**
```bash
kubectl logs -n keda deployment/keda-operator --tail=100 | grep aim-qwen3-32b-scalable
```

**Expected Output:**
```
...
ScaledObject default/aim-qwen3-32b-scalable-predictor is active, scaling Deployment default/aim-qwen3-32b-scalable-predictor-00001-deployment from 1 to 2
ScaledObject default/aim-qwen3-32b-scalable-predictor is active, scaling Deployment default/aim-qwen3-32b-scalable-predictor-00001-deployment from 2 to 3
```

**What to Check:**
- KEDA detects metrics from Prometheus
- Scaling decisions are logged
- Scaling happens incrementally (1 -> 2 -> 3)
- Scaling is based on vLLM metrics

**Check Prometheus Metrics (verify metric is available):**
```bash
# Port forward to Prometheus
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090
```

**In browser, navigate to:** http://localhost:9090

**Query the metric:**
```
sum(vllm:num_requests_running{service="isvc.aim-qwen3-32b-scalable-predictor"})
```

**Expected Output:**
- Metric value shows number of running requests
- Value increases as you send more requests
- Value decreases as requests complete

**What to Check:**
- Metric is available in Prometheus
- Metric value reflects actual running requests
- Metric updates in real-time

**Troubleshooting:**
- **If scaling doesn't happen**:
  - Wait 1-2 minutes (KEDA polls metrics periodically)
  - Verify metric value exceeds threshold (1): Check in Prometheus
  - Check KEDA logs for errors: `kubectl logs -n keda deployment/keda-operator`
  - Verify ScaledObject is active: `kubectl describe scaledobject aim-qwen3-32b-scalable-predictor`
  
- **If metric not found in Prometheus**:
  - Check OpenTelemetry sidecar is running: `kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable`
  - Verify VLLM_ENABLE_METRICS is set: `kubectl get pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o yaml | grep VLLM_ENABLE_METRICS`
  - Check sidecar collector logs: `kubectl logs -l app=vllm-sidecar-collector -n default`
  
- **If scaling happens but pods don't start**:
  - Check pod events: `kubectl describe pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable`
  - Verify GPU resources are available: `kubectl describe node <gpu-node> | grep -i gpu`
  - Check resource limits aren't too restrictive

### Step 7.4: View Metrics in Grafana

**In Grafana UI:**

1. Navigate to the vLLM metrics dashboard (or create a custom dashboard)
2. Observe the following metrics as you send requests:

**Key Metrics to Monitor:**

**Request Rate:**
- Query: `rate(vllm_num_requests_total[5m])`
- **Expected Behavior**: Increases as you send more requests
- **What to Check**: Graph shows spikes corresponding to request bursts

**Request Latency:**
- Query: `histogram_quantile(0.95, rate(vllm_request_duration_seconds_bucket[5m]))`
- **Expected Behavior**: May increase slightly under load, then stabilize
- **What to Check**: p95 latency remains reasonable (< 30 seconds for typical requests)

**Running Requests:**
- Query: `vllm_num_requests_running`
- **Expected Behavior**: Increases as concurrent requests are sent, matches scaling behavior
- **What to Check**: Value correlates with number of active requests

**GPU Utilization:**
- Query: `gpu_utilization_percent` or container GPU metrics
- **Expected Behavior**: Increases during inference, higher with more replicas
- **What to Check**: GPU is being utilized effectively

**Memory Usage:**
- Query: `container_memory_usage_bytes{pod=~"aim-qwen3-32b-scalable.*"}`
- **Expected Behavior**: Relatively stable per pod, increases with more replicas
- **What to Check**: Memory usage is within limits

**Pod Count (Replicas):**
- Query: `count(kube_pod_status_phase{pod=~"aim-qwen3-32b-scalable.*", phase="Running"})`
- **Expected Behavior**: Increases from 1 to 3 as load increases
- **What to Check**: Replica count matches KEDA scaling decisions

**Expected Output:**
- Graphs show data points updating in real-time
- Metrics correlate with request activity
- Request rate spikes when sending multiple requests
- Running requests count matches active requests
- Pod count increases as autoscaling triggers

**What to Check:**
- Metrics are being collected and displayed
- Graphs update in real-time (refresh every 10-30 seconds)
- Data makes sense (request rate correlates with requests sent)
- Autoscaling is visible (pod count increases under load)

**Create Custom Dashboard (if needed):**

If pre-configured dashboards aren't available, create a custom dashboard:

1. Click "+" icon → "Create" → "Dashboard"
2. Add panels with Prometheus queries:
   - **Request Rate Panel**: `rate(vllm_num_requests_total[5m])`
   - **Latency Panel**: `histogram_quantile(0.95, rate(vllm_request_duration_seconds_bucket[5m]))`
   - **Running Requests Panel**: `vllm_num_requests_running`
   - **Replica Count Panel**: `count(kube_pod_status_phase{pod=~"aim-qwen3-32b-scalable.*", phase="Running"})`

**Troubleshooting:**
- **If metrics not appearing**: 
  - Wait 2-3 minutes for metrics to be scraped and aggregated
  - Verify Prometheus is scraping: Check Prometheus targets in UI
  - Check time range is correct (last 15 minutes or 1 hour)
  
- **If graphs are empty**: 
  - Send more requests to generate metrics
  - Verify service name in queries matches your InferenceService name
  - Check Prometheus has data: Query `vllm_num_requests_total` directly
  
- **If scaling not visible in metrics**: 
  - Check KEDA logs: `kubectl logs -n keda deployment/keda-operator`
  - Verify ScaledObject status: `kubectl describe scaledobject aim-qwen3-32b-scalable-predictor`
  - Check Prometheus metric value: Query the metric used in autoscaling
  
- **If metrics don't update**: 
  - Check Grafana refresh interval (should be 10-30 seconds)
  - Verify Prometheus is scraping metrics: Check targets in Prometheus UI
  - Check OpenTelemetry sidecar is running: `kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable`

## Additional Cluster Setup (Before Step 1)

Before starting the KServe deployment, ensure your cluster is properly configured. If you followed the [Kubernetes-MI300X setup guide](https://github.com/Yu-amd/Kubernetes-MI300X), most of these should already be in place. The following steps verify your cluster setup and address any additional requirements.

**Command:**
```bash
kubectl cluster-info
```

**Expected Output:**
```
Kubernetes control plane is running at https://<cluster-endpoint>:<port>
CoreDNS is running at https://<cluster-endpoint>:<port>/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

**What to Check:**
- Cluster endpoint is accessible
- No connection errors
- Control plane is running

**Example Output:**
```
Kubernetes control plane is running at https://10.0.0.1:6443
CoreDNS is running at https://10.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

**Troubleshooting:**
- If connection fails, verify `kubeconfig` is set correctly: `echo $KUBECONFIG`
- Check network connectivity to cluster
- Verify cluster credentials: `kubectl config view`

---

#### Step 1.2: List and Identify GPU Nodes

**Command:**
```bash
kubectl get nodes
```

**Expected Output:**
```
NAME           STATUS   ROLES           AGE   VERSION
gpu-node-1     Ready    worker          5d    v1.28.0
cpu-node-1     Ready    worker          5d    v1.28.0
```

**What to Check:**
- Nodes are in `Ready` status
- Identify which nodes have GPUs
- Note the node names for labeling

**Example Output:**
```
NAME              STATUS   ROLES           AGE   VERSION
mi300x-worker-1   Ready    worker          2d    v1.28.0
mi300x-worker-2   Ready    worker          2d    v1.28.0
```

**Additional Check - Node Details:**
```bash
kubectl get nodes -o wide
```

This shows additional information including internal IPs and OS images.

---

#### Step 1.3: Label GPU Nodes

**Command:**
```bash
kubectl label nodes <gpu-node-name> accelerator=amd-instinct-mi300x
```

**Replace `<gpu-node-name>` with your actual GPU node name from Step 1.2.**

**Expected Output:**
```
node/<gpu-node-name> labeled
```

**What to Check:**
- Label applied successfully
- No error messages

**Example:**
```bash
kubectl label nodes mi300x-worker-1 accelerator=amd-instinct-mi300x
# Output: node/mi300x-worker-1 labeled
```

**Verify Labels:**
```bash
kubectl get nodes --show-labels | grep accelerator
```

**Expected Output:**
```
mi300x-worker-1   Ready    worker   2d    v1.28.0   accelerator=amd-instinct-mi300x,...
```

**Troubleshooting:**
- If node not found, verify node name: `kubectl get nodes`
- If permission denied, check RBAC permissions
- To remove a label: `kubectl label nodes <node-name> accelerator-`

**Label Multiple Nodes:**
If you have multiple GPU nodes, label each one:
```bash
kubectl label nodes mi300x-worker-1 accelerator=amd-instinct-mi300x
kubectl label nodes mi300x-worker-2 accelerator=amd-instinct-mi300x
```

---

#### Step 1.4: Verify GPU Device Plugin

**Command:**
```bash
kubectl get pods -n amd-gpu-operator
```

**Expected Output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
amd-gpu-device-plugin-xxxxx               1/1     Running   0          5d
amd-gpu-node-labeller-xxxxx               1/1     Running   0          5d
```

**Alternative Check (if using different namespace):**
```bash
# Check all namespaces for GPU-related pods
kubectl get pods --all-namespaces | grep -E "gpu|device-plugin"

# Or check kube-system (some setups use this namespace)
kubectl get pods -n kube-system | grep gpu
```

**What to Check:**
- GPU device plugin pod is running
- Status is `Running` (not `Pending` or `Error`)
- Pod is in `amd-gpu-operator` namespace (or `kube-system` depending on installation)

**Example Output:**
```
NAME                          READY   STATUS    RESTARTS   AGE
amd-gpu-device-plugin-abc123  1/1     Running   0          5d
```

**If No GPU Device Plugin Found:**

You may need to install the AMD GPU device plugin. Check your cluster documentation or install using:

```bash
# Example: Install AMD GPU Operator (adjust based on your cluster)
kubectl apply -f https://github.com/RadeonOpenCompute/rocm-k8s-operator/releases/latest/download/amd-gpu-operator.yaml
```

**Verify GPU Resources Available:**
```bash
kubectl describe node <gpu-node-name> | grep -A 10 "Allocated resources"
```

**Expected Output:**
```
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  amd.com/gpu        0            0
  cpu                500m         2
  memory             1Gi          4Gi
```

**What to Check:**
- `amd.com/gpu` resource is listed (or `nvidia.com/gpu` if using NVIDIA naming)
- GPU count matches your hardware

**Alternative Check:**
```bash
kubectl get nodes <gpu-node-name> -o jsonpath='{.status.capacity}' | jq
```

---

#### Step 1.5: Install Metrics Server (for HPA)

**Check if Metrics Server Already Installed:**
```bash
kubectl get deployment metrics-server -n kube-system
```

**If Not Found, Install Metrics Server:**

**Command:**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Expected Output:**
```
serviceaccount/metrics-server created
clusterrole.rbac.authorization.k8s.io/system:aggregated-metrics-reader created
clusterrolebinding.rbac.authorization.k8s.io/metrics-server:system:auth-delegator created
rolebinding.rbac.authorization.k8s.io/metrics-server-auth-reader created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
service/metrics-server created
deployment.apps/metrics-server created
```

**Wait for Metrics Server to be Ready:**
```bash
kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system
```

**Verify Installation:**
```bash
kubectl get deployment metrics-server -n kube-system
```

**Expected Output:**
```
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   1/1     1            1           2m
```

**Test Metrics Server:**
```bash
kubectl top nodes
```

**Expected Output:**
```
NAME              CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
mi300x-worker-1   500m         5%     8Gi            25%
```

**What to Check:**
- Metrics server deployment shows `1/1` ready
- `kubectl top` commands work without errors
- CPU and memory metrics are displayed

**Troubleshooting:**
- If metrics-server fails to start, check logs: `kubectl logs -n kube-system deployment/metrics-server`
- Some clusters require additional configuration (e.g., `--kubelet-insecure-tls` flag)
- Check if your cluster uses a different metrics solution (e.g., Prometheus Adapter)

### Step 2: Configure Deployment Files

Before deploying, review and customize the configuration files to match your environment.

#### Step 2.1: Review ConfigMap Configuration

**File:** `kubernetes/configmap.yaml`

**Command to View:**
```bash
cat kubernetes/configmap.yaml
```

**Expected Content:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aim-config
  namespace: aim
data:
  AIM_PORT: "8000"
  AIM_HOST: "0.0.0.0"
  LOG_LEVEL: "INFO"
  MODEL_NAME: "qwen3-32b"
  HEALTH_CHECK_INTERVAL: "30"
  MAX_CONCURRENT_REQUESTS: "10"
  REQUEST_TIMEOUT: "300"
```

**Configuration Options:**

1. **AIM_PORT**: Service port (default: 8000)
   - Change if port conflicts with other services
   - Must match service port configuration

2. **LOG_LEVEL**: Logging verbosity (default: INFO)
   - Options: DEBUG, INFO, WARNING, ERROR
   - Use DEBUG for troubleshooting

3. **MAX_CONCURRENT_REQUESTS**: Maximum concurrent requests (default: 10)
   - Adjust based on GPU capacity and model size
   - Higher values may cause OOM errors

4. **REQUEST_TIMEOUT**: Request timeout in seconds (default: 300)
   - Increase for longer inference tasks
   - Decrease for faster failure detection

**To Edit:**
```bash
# Edit with your preferred editor
nano kubernetes/configmap.yaml
# or
vim kubernetes/configmap.yaml
```

**What to Check:**
- Port number matches your requirements
- Log level appropriate for your needs
- Timeout values reasonable for your use case

---

#### Step 2.2: Review and Adjust Resource Requests/Limits

**File:** `kubernetes/deployment.yaml`

**Command to View Resource Section:**
```bash
grep -A 15 "resources:" kubernetes/deployment.yaml
```

**Expected Configuration:**
```yaml
resources:
  requests:
    amd.com/gpu: 1
    memory: "64Gi"
    cpu: "8"
  limits:
    amd.com/gpu: 1
    memory: "200Gi"
    cpu: "32"
```

**Resource Guidelines:**

1. **GPU Requests/Limits:**
   - `amd.com/gpu: 1` - One GPU per pod
   - Adjust if your cluster uses different GPU resource naming
   - For NVIDIA: use `nvidia.com/gpu: 1`

2. **Memory:**
   - **Request (64Gi)**: Minimum memory guaranteed
   - **Limit (200Gi)**: Maximum memory allowed
   - Model size determines minimum (Qwen3-32B needs ~64Gi+)
   - Increase limit if you see OOM errors

3. **CPU:**
   - **Request (8 cores)**: Minimum CPU guaranteed
   - **Limit (32 cores)**: Maximum CPU allowed
   - More CPU can improve throughput
   - Adjust based on node capacity

**Check Node Capacity:**
```bash
kubectl describe node <gpu-node-name> | grep -A 5 "Capacity:"
```

**Expected Output:**
```
Capacity:
  amd.com/gpu:     8
  cpu:             64
  memory:          512Gi
```

**What to Check:**
- Node has sufficient resources
- Requests don't exceed node capacity
- Limits are reasonable (not too restrictive)

**To Edit:**
```bash
nano kubernetes/deployment.yaml
```

**Common Adjustments:**
- **Smaller model**: Reduce memory requests/limits
- **Larger cluster**: Increase CPU limits for better performance
- **Multiple GPUs per node**: Adjust GPU requests if needed

---

#### Step 2.3: Verify Node Selector Configuration

**Command to Check:**
```bash
grep -A 3 "nodeSelector:" kubernetes/deployment.yaml
```

**Expected Configuration:**
```yaml
nodeSelector:
  accelerator: amd-instinct-mi300x
```

**What to Check:**
- Label name matches what you set in Step 1.3
- Label value matches: `amd-instinct-mi300x`

**Verify Node Has Label:**
```bash
kubectl get nodes --show-labels | grep accelerator
```

**Expected Output:**
```
mi300x-worker-1   ...   accelerator=amd-instinct-mi300x,...
```

**If Using Different Label:**
If your cluster uses different node labels, update the deployment:
```yaml
nodeSelector:
  node-role.kubernetes.io/gpu: "true"
  # or
  kubernetes.io/instance-type: "gpu-node"
```

**To Edit:**
```bash
nano kubernetes/deployment.yaml
# Find nodeSelector section and update
```

---

#### Step 2.4: Review Tolerations (if needed)

**Command to Check:**
```bash
grep -A 5 "tolerations:" kubernetes/deployment.yaml
```

**Expected Configuration:**
```yaml
tolerations:
- key: nvidia.com/gpu
  operator: Exists
  effect: NoSchedule
- key: amd.com/gpu
  operator: Exists
  effect: NoSchedule
```

**What This Does:**
- Allows pods to be scheduled on tainted GPU nodes
- Required if your GPU nodes have taints

**Check if Nodes Are Tainted:**
```bash
kubectl describe node <gpu-node-name> | grep Taints
```

**Expected Output (if tainted):**
```
Taints:             amd.com/gpu:NoSchedule
```

**Expected Output (if not tainted):**
```
Taints:             <none>
```

**What to Check:**
- If nodes are tainted, tolerations must match
- If nodes are not tainted, tolerations are optional but harmless

**To Edit (if needed):**
```bash
nano kubernetes/deployment.yaml
# Update tolerations to match your node taints
```

---

#### Step 2.5: Verify Image Configuration

**Command to Check:**
```bash
grep -A 2 "image:" kubernetes/deployment.yaml
```

**Expected Configuration:**
```yaml
image: amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
imagePullPolicy: IfNotPresent
```

**What to Check:**
- Image name is correct
- Image tag/version is appropriate
- Image pull policy matches your needs

**Available Images:**
- `amdenterpriseai/aim-qwen-qwen3-32b:0.8.4` - Qwen3-32B model
- Check [AMD AIM documentation](https://github.com/amd-enterprise-ai/aim-deploy) for other models

**Image Pull Policy Options:**
- `IfNotPresent`: Pull only if not locally available (default)
- `Always`: Always pull latest (for development)
- `Never`: Use only local images

**Test Image Accessibility:**
```bash
# If using Docker on the node
docker pull amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
```

**What to Check:**
- Image is accessible from your cluster
- Image registry credentials configured (if private)
- Image size is reasonable for your network

---

#### Step 2.6: Review Health Check Configuration

**Command to Check:**
```bash
grep -A 10 "livenessProbe:" kubernetes/deployment.yaml
```

**Expected Configuration:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 120
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 180
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Configuration Explanation:**

1. **Liveness Probe:**
   - Checks if container is alive
   - Restarts container if probe fails
   - `initialDelaySeconds: 120` - Wait 2 minutes before first check (model loading time)
   - `periodSeconds: 30` - Check every 30 seconds
   - `failureThreshold: 3` - Restart after 3 consecutive failures

2. **Readiness Probe:**
   - Checks if container is ready to serve traffic
   - Removes pod from service endpoints if not ready
   - `initialDelaySeconds: 180` - Wait 3 minutes (longer than liveness for model initialization)
   - `periodSeconds: 10` - Check every 10 seconds

**What to Check:**
- Initial delays account for model loading time
- Periods are reasonable (not too frequent)
- Failure thresholds prevent unnecessary restarts

**To Adjust (if needed):**
- Increase `initialDelaySeconds` if model takes longer to load
- Decrease `periodSeconds` for faster failure detection
- Adjust `failureThreshold` based on your reliability requirements

### Step 3: Deploy Core Components

Now we'll deploy the AIM components to your Kubernetes cluster. **Perform each step in order and verify success before proceeding.**

#### Step 3.1: Create Namespace

**Command:**
```bash
kubectl apply -f kubernetes/namespace.yaml
```

**Expected Output:**
```
namespace/aim created
```

**What to Check:**
- Namespace created successfully
- No error messages

**Verify Namespace:**
```bash
kubectl get namespace aim
```

**Expected Output:**
```
NAME   STATUS   AGE
aim    Active   5s
```

**What to Check:**
- Status is `Active` (not `Terminating`)
- Namespace exists

**Alternative: Create Namespace Manually**
If the YAML file doesn't work, create namespace directly:
```bash
kubectl create namespace aim
```

**Set Namespace as Default (Optional):**
```bash
kubectl config set-context --current --namespace=aim
```

This allows you to omit `-n aim` from subsequent commands.

**Troubleshooting:**
- If "already exists" error: Namespace may have been created previously. This is fine, continue to next step.
- If permission denied: Check RBAC permissions for namespace creation

---

#### Step 3.2: Deploy ConfigMap

**Command:**
```bash
kubectl apply -f kubernetes/configmap.yaml
```

**Expected Output:**
```
configmap/aim-config created
```

**What to Check:**
- ConfigMap created successfully
- No error messages

**Verify ConfigMap:**
```bash
kubectl get configmap -n aim
```

**Expected Output:**
```
NAME         DATA   AGE
aim-config   7      10s
```

**What to Check:**
- ConfigMap exists
- `DATA` column shows number of configuration keys (should be 7)

**View ConfigMap Contents:**
```bash
kubectl get configmap aim-config -n aim -o yaml
```

**Expected Output:**
```yaml
apiVersion: v1
data:
  AIM_HOST: "0.0.0.0"
  AIM_PORT: "8000"
  HEALTH_CHECK_INTERVAL: "30"
  LOG_LEVEL: "INFO"
  MAX_CONCURRENT_REQUESTS: "10"
  MODEL_NAME: "qwen3-32b"
  REQUEST_TIMEOUT: "300"
kind: ConfigMap
metadata:
  name: aim-config
  namespace: aim
```

**What to Check:**
- All configuration keys are present
- Values match your requirements from Step 2.1

**Troubleshooting:**
- If "already exists" error: ConfigMap was created previously. Update with: `kubectl apply -f kubernetes/configmap.yaml --force`
- If values are wrong: Edit the YAML file and reapply

---

#### Step 3.3: Deploy ServiceAccount and RBAC

**Command:**
```bash
kubectl apply -f kubernetes/serviceaccount.yaml
```

**Expected Output:**
```
serviceaccount/aim-service-account created
role.rbac.authorization.k8s.io/aim-role created
rolebinding.rbac.authorization.k8s.io/aim-role-binding created
```

**What to Check:**
- ServiceAccount created
- Role created
- RoleBinding created
- No error messages

**Verify ServiceAccount:**
```bash
kubectl get serviceaccount -n aim
```

**Expected Output:**
```
NAME                 SECRETS   AGE
aim-service-account  1         15s
default              1         15s
```

**What to Check:**
- ServiceAccount exists
- Has at least 1 secret (for token)

**Verify Role and RoleBinding:**
```bash
kubectl get role,rolebinding -n aim
```

**Expected Output:**
```
NAME                    AGE
role.rbac.authorization.k8s.io/aim-role   15s

NAME                           AGE
rolebinding.rbac.authorization.k8s.io/aim-role-binding   15s
```

**What to Check:**
- Role exists
- RoleBinding exists
- Both are in the `aim` namespace

**View Role Permissions:**
```bash
kubectl describe role aim-role -n aim
```

**Expected Output:**
```
Name:         aim-role
Labels:       <none>
Annotations:  <none>
PolicyRule:
  Resources  Non-Resource URLs  Resource Names  Verbs
  ---------  -----------------  --------------  -----
  configmaps []                 []              [get list watch]
  secrets    []                 []              [get list watch]
```

**What to Check:**
- Permissions are appropriate (read-only for configmaps and secrets)
- No overly permissive rules

**Troubleshooting:**
- If permission errors: Check cluster RBAC policies
- If ServiceAccount not found: Verify namespace is correct

---

#### Step 3.4: Deploy AIM Service Deployment

**Command:**
```bash
kubectl apply -f kubernetes/deployment.yaml
```

**Expected Output:**
```
deployment.apps/aim-qwen3-32b created
```

**What to Check:**
- Deployment created successfully
- No error messages

**Monitor Deployment Progress:**
```bash
kubectl get pods -n aim -w
```

**Expected Output (Initial):**
```
NAME                             READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-7d8f9c4b5d-xxxxx   0/1     Pending   0          5s
```

**Expected Output (Image Pulling):**
```
NAME                             READY   STATUS             RESTARTS   AGE
aim-qwen3-32b-7d8f9c4b5d-xxxxx   0/1     ImagePullBackOff   0          30s
```

**Expected Output (Container Creating):**
```
NAME                             READY   STATUS              RESTARTS   AGE
aim-qwen3-32b-7d8f9c4b5d-xxxxx   0/1     ContainerCreating   0          45s
```

**Expected Output (Running):**
```
NAME                             READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-7d8f9c4b5d-xxxxx   0/1     Running   0          2m
```

**Expected Output (Ready):**
```
NAME                             READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-7d8f9c4b5d-xxxxx   1/1     Running   0          5m
```

**Press `Ctrl+C` to stop watching.**

**What to Check at Each Stage:**
- **Pending**: Pod is being scheduled (check node selector, resources)
- **ImagePullBackOff**: Image pull failed (check image name, registry access)
- **ContainerCreating**: Container is starting (normal, wait)
- **Running**: Container is running but not ready (model may be loading)
- **Ready (1/1)**: Pod is fully ready and serving traffic

**Check Deployment Status:**
```bash
kubectl get deployment -n aim
```

**Expected Output:**
```
NAME            READY   UP-TO-DATE   AVAILABLE   AGE
aim-qwen3-32b   1/1     1            1           5m
```

**What to Check:**
- `READY`: 1/1 means deployment is ready
- `UP-TO-DATE`: Number of pods updated to latest spec
- `AVAILABLE`: Number of pods available to serve traffic

**View Deployment Details:**
```bash
kubectl describe deployment aim-qwen3-32b -n aim
```

**Expected Output:**
```
Name:                   aim-qwen3-32b
Namespace:              aim
CreationTimestamp:      Wed, 27 Nov 2024 15:00:00 +0000
Labels:                 app=aim-qwen3-32b
                        component=inference
Annotations:            deployment.kubernetes.io/revision: 1
Selector:               app=aim-qwen3-32b
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
Pod Template:
  Labels:  app=aim-qwen3-32b
           component=inference
  Containers:
   aim-inference:
    Image:        amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
    Port:         8000/TCP
    Host Port:    0/TCP
    Environment:
      AIM_PORT:  <set to the key 'AIM_PORT' of config map 'aim-config'>
      AIM_HOST:  <set to the key 'AIM_HOST' of config map 'aim-config'>
      LOG_LEVEL: <set to the key 'LOG_LEVEL' of config map 'aim-config'>
    Limits:
      amd.com/gpu:  1
      cpu:          32
      memory:       200Gi
    Requests:
      amd.com/gpu:  1
      cpu:          8
      memory:       64Gi
    Liveness:   http-get http://:http/health delay=120s timeout=10s period=30s #success=1 #failure=3
    Readiness:  http-get http://:http/ready delay=180s timeout=5s period=10s #success=1 #failure=3
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  5m    deployment-controller  Scaled up replica set aim-qwen3-32b-7d8f9c4b5d to 1
```

**What to Check:**
- Replicas: 1 desired, 1 available
- Image is correct
- Environment variables are set from ConfigMap
- Resource limits match your configuration
- Health checks are configured

**Check Pod Status:**
```bash
kubectl get pods -n aim -l app=aim-qwen3-32b
```

**Expected Output:**
```
NAME                             READY   STATUS    RESTARTS   AGE
aim-qwen3-32b-7d8f9c4b5d-xxxxx   1/1     Running   0          5m
```

**What to Check:**
- Status is `Running`
- READY shows `1/1`
- RESTARTS is 0 (or low number)
- AGE shows pod has been running

**View Pod Logs (Initial Startup):**
```bash
kubectl logs -n aim -l app=aim-qwen3-32b --tail=50
```

**Expected Output (Model Loading):**
```
[INFO] Starting AIM inference service...
[INFO] Loading model: qwen3-32b
[INFO] Model loading in progress...
[INFO] GPU memory allocated: 64Gi
```

**Expected Output (Ready):**
```
[INFO] Model loaded successfully
[INFO] AIM service ready on port 8000
[INFO] Health check endpoint: /health
[INFO] Ready endpoint: /ready
```

**What to Check:**
- No error messages
- Model loading messages appear
- Service ready message appears
- GPU memory allocation looks correct

**Troubleshooting Common Issues:**

1. **Pod Stuck in Pending:**
   ```bash
   kubectl describe pod -n aim -l app=aim-qwen3-32b
   ```
   - Check "Events" section for scheduling issues
   - Verify node selector matches labeled nodes
   - Check if node has available resources

2. **ImagePullBackOff:**
   ```bash
   kubectl describe pod -n aim -l app=aim-qwen3-32b | grep -A 5 "Events"
   ```
   - Verify image name is correct
   - Check registry access
   - Verify image pull secrets if using private registry

3. **CrashLoopBackOff:**
   ```bash
   kubectl logs -n aim -l app=aim-qwen3-32b --previous
   ```
   - Check previous container logs for errors
   - Verify resource limits aren't too low
   - Check environment variables

4. **Pod Running but Not Ready:**
   - Model may still be loading (check logs)
   - Readiness probe may be failing (check probe configuration)
   - Wait longer (initial delay is 180 seconds)

**Wait for Deployment to be Ready:**
```bash
kubectl wait --for=condition=available --timeout=600s deployment/aim-qwen3-32b -n aim
```

**Expected Output:**
```
deployment.apps/aim-qwen3-32b condition met
```

This command waits up to 10 minutes for the deployment to become available.

---

#### Step 3.5: Create Service

**Command:**
```bash
kubectl apply -f kubernetes/service.yaml
```

**Expected Output:**
```
service/aim-qwen3-32b created
service/aim-qwen3-32b-lb created
```

**What to Check:**
- Both services created (ClusterIP and LoadBalancer)
- No error messages

**Verify Services:**
```bash
kubectl get svc -n aim
```

**Expected Output:**
```
NAME             TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
aim-qwen3-32b    ClusterIP      10.96.123.45    <none>        8000/TCP         10s
aim-qwen3-32b-lb LoadBalancer   10.96.123.46    <pending>     8000:30080/TCP   10s
```

**What to Check:**
- ClusterIP service has an internal IP
- LoadBalancer service shows `<pending>` (normal if no load balancer configured)
- Port 8000 is configured correctly

**View Service Details:**
```bash
kubectl describe svc aim-qwen3-32b -n aim
```

**Expected Output:**
```
Name:              aim-qwen3-32b
Namespace:         aim
Labels:             app=aim-qwen3-32b
                    component=inference
Annotations:       <none>
Selector:          app=aim-qwen3-32b
Type:              ClusterIP
IP Family:         IPv4
IP:                10.96.123.45
Port:              http  8000/TCP
TargetPort:        http/TCP
Endpoints:         10.244.1.5:8000
Session Affinity:  None
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  EnsuringLoadBalancer  10s  service-controller  Ensuring load balancer
```

**What to Check:**
- Selector matches pod labels (`app=aim-qwen3-32b`)
- Endpoints show pod IP and port (should appear after pod is ready)
- Port mapping is correct (8000 -> 8000)

**Verify Service Endpoints:**
```bash
kubectl get endpoints -n aim
```

**Expected Output:**
```
NAME             ENDPOINTS           AGE
aim-qwen3-32b    10.244.1.5:8000    30s
```

**What to Check:**
- Endpoints show pod IP address
- Port matches service configuration
- Endpoints appear after pod becomes ready

**Troubleshooting:**
- If no endpoints: Pod may not be ready yet. Wait and check pod status.
- If wrong port: Verify service selector matches pod labels
- If service not accessible: Check network policies or firewall rules

---

#### Step 3.6: Create PodDisruptionBudget

**Command:**
```bash
kubectl apply -f kubernetes/pdb.yaml
```

**Expected Output:**
```
poddisruptionbudget.policy/aim-qwen3-32b-pdb created
```

**What to Check:**
- PDB created successfully
- No error messages

**Verify PodDisruptionBudget:**
```bash
kubectl get pdb -n aim
```

**Expected Output:**
```
NAME                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
aim-qwen3-32b-pdb   1               N/A               0                     10s
```

**What to Check:**
- MIN AVAILABLE is 1 (ensures at least 1 pod is always available)
- ALLOWED DISRUPTIONS is 0 (no disruptions allowed with 1 replica)

**View PDB Details:**
```bash
kubectl describe pdb aim-qwen3-32b-pdb -n aim
```

**Expected Output:**
```
Name:           aim-qwen3-32b-pdb
Namespace:      aim
Min available:  1
Selector:       app=aim-qwen3-32b
Status:
  Allowed disruptions:  0
  Current:              1
  Desired:              1
  Total:                1
```

**What to Check:**
- Selector matches deployment labels
- Status shows current pod count
- Allowed disruptions is appropriate

**Troubleshooting:**
- If PDB not working: Verify selector matches pod labels
- If disruptions not prevented: Check if PDB is being respected by cluster

---

### Step 4: Verify Deployment

Now verify that everything is working correctly.

#### Step 4.1: Check Overall Status

**Command:**
```bash
kubectl get all -n aim
```

**Expected Output:**
```
NAME                             READY   STATUS    RESTARTS   AGE
pod/aim-qwen3-32b-7d8f9c4b5d-xxxxx   1/1     Running   0          10m

NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/aim-qwen3-32b   ClusterIP      10.96.123.45    <none>        8000/TCP         10m
service/aim-qwen3-32b-lb LoadBalancer   10.96.123.46    <pending>    8000:30080/TCP   10m

NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/aim-qwen3-32b   1/1     1            1           10m

NAME                                   DESIRED   CURRENT   READY   AGE
replicaset.apps/aim-qwen3-32b-7d8f9c4b5d   1         1         1       10m
```

**What to Check:**
- Pod is Running and Ready (1/1)
- Services are created
- Deployment shows 1/1 ready
- ReplicaSet shows 1/1 ready

#### Step 4.2: Check Pod Logs

**Command:**
```bash
kubectl logs -n aim -l app=aim-qwen3-32b --tail=100
```

**Expected Output:**
```
[INFO] AIM inference service started
[INFO] Model: qwen3-32b loaded successfully
[INFO] GPU: AMD Instinct MI300X
[INFO] Service listening on 0.0.0.0:8000
[INFO] Health endpoint: /health
[INFO] Ready endpoint: /ready
[INFO] Metrics endpoint: /metrics
```

**What to Check:**
- No error messages
- Model loaded successfully
- Service is listening on correct port
- Endpoints are available

#### Step 4.3: Describe Pod for Events

**Command:**
```bash
kubectl describe pod -n aim -l app=aim-qwen3-32b
```

**Review the "Events" section for any warnings or errors.**

**What to Check:**
- No error events
- Successful scheduling
- Successful container creation
- Health checks passing

#### Step 4.4: Test Health Endpoints

**Port Forward to Service:**
```bash
kubectl port-forward -n aim svc/aim-qwen3-32b 8000:8000
```

**In another terminal, test health endpoint:**
```bash
curl http://localhost:8000/health
```

**Expected Output:**
```
{"status": "healthy"}
```

**Test ready endpoint:**
```bash
curl http://localhost:8000/ready
```

**Expected Output:**
```
{"status": "ready"}
```

**What to Check:**
- Health endpoint returns healthy status
- Ready endpoint returns ready status
- No connection errors

**Stop port forwarding:** Press `Ctrl+C` in the port-forward terminal.

---

**Deployment is complete!** Proceed to the Testing and Validation section to perform comprehensive testing.

## Observability Setup

### Prometheus Deployment

Prometheus collects metrics from AIM pods and Kubernetes cluster:

```bash
# Deploy Prometheus
kubectl apply -f observability/prometheus-deployment.yaml

# Check Prometheus status
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Access Prometheus UI
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090
```

### Grafana Deployment

Grafana provides visualization dashboards:

```bash
# Deploy Grafana
kubectl apply -f observability/grafana-deployment.yaml

# Deploy dashboard
kubectl apply -f observability/grafana-dashboard.yaml

# Access Grafana UI
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000
# Login: admin/admin
```

### Metrics Collected

The observability stack collects:

- **Application Metrics**:
  - Request rate
  - Request latency (p50, p95, p99)
  - Error rate
  - Active connections

- **Resource Metrics**:
  - CPU usage
  - Memory usage
  - GPU utilization
  - Network I/O

- **Kubernetes Metrics**:
  - Pod status
  - Container restarts
  - Resource requests/limits

### Custom Metrics (Advanced)

To enable custom metrics for HPA based on request rate:

1. Install Prometheus Adapter
2. Configure custom metrics API
3. Update HPA to use custom metrics

## Scalability Configuration

### Horizontal Pod Autoscaler (HPA)

HPA automatically scales pods based on resource utilization:

```bash
# Deploy HPA
kubectl apply -f kubernetes/hpa.yaml

# Check HPA status
kubectl get hpa -n aim

# Describe HPA for details
kubectl describe hpa aim-qwen3-32b-hpa -n aim
```

#### HPA Configuration

Current HPA settings:
- **Min Replicas**: 1
- **Max Replicas**: 5
- **CPU Threshold**: 70%
- **Memory Threshold**: 80%

To adjust, edit `kubernetes/hpa.yaml`:

```yaml
minReplicas: 1
maxReplicas: 5
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70
```

### Manual Scaling

```bash
# Scale deployment manually
kubectl scale deployment aim-qwen3-32b -n aim --replicas=3

# Check scaling status
kubectl get deployment aim-qwen3-32b -n aim
```

### PodDisruptionBudget

PDB ensures availability during cluster maintenance:

```bash
kubectl apply -f kubernetes/pdb.yaml
kubectl get pdb -n aim
```

## Testing and Validation

This section provides comprehensive testing procedures to validate your AIM deployment.

### Automated Validation

**Check InferenceService Status:**

**Command:**
```bash
kubectl get inferenceservice
```

**Expected Output:**
```
NAME            URL                                                                  READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION   AGE
aim-qwen3-32b   http://aim-qwen3-32b.default.example.com   True    True   aim-qwen3-32b-predictor-00001   aim-qwen3-32b-predictor-00001   5m
```

**What to Check:**
- `READY` is `True`
- URL is available
- Latest revision is ready

**Expected Output:**
```
[INFO] Starting AIM Kubernetes deployment validation...
[INFO] Checking Kubernetes cluster connection...
[INFO] Cluster connection: OK
[INFO] Checking namespace...
[INFO] Namespace exists: OK
[INFO] Checking deployment...
[INFO] Deployment ready: 1/1 replicas
[INFO] Checking pods...
[INFO] Pod aim-qwen3-32b-xxxxx: Running
[INFO] Checking service...
[INFO] Service exists: OK
[INFO] Service ClusterIP: 10.96.123.45
[INFO] Checking health endpoint...
[INFO] Health endpoint: OK
[INFO] Checking ready endpoint...
[INFO] Ready endpoint: OK
[INFO] Validation completed!
```

**What to Check:**
- All checks pass
- No error messages
- Deployment is ready
- Pods are running

**If Validation Fails:**
- Review error messages
- Check pod logs: `kubectl logs -n aim -l app=aim-qwen3-32b`
- Verify pod status: `kubectl get pods -n aim`

---

### Manual Testing

#### Test 1: Port Forward to Service

**Command:**
```bash
kubectl port-forward -n aim svc/aim-qwen3-32b 8000:8000
```

**Expected Output:**
```
Forwarding from 127.0.0.1:8000 -> 8000
Forwarding from [::1]:8000 -> 8000
```

**What to Check:**
- Port forwarding started successfully
- No connection errors
- Keep this terminal open (don't close it)

**In Another Terminal, Test Connection:**
```bash
curl http://localhost:8000/health
```

**Expected Output:**
```
{"status": "healthy"}
```

**What to Check:**
- Connection successful
- JSON response received
- Status is "healthy"

**Troubleshooting:**
- If connection refused: Verify pod is ready and service has endpoints
- If port already in use: Use different local port: `kubectl port-forward -n aim svc/aim-qwen3-32b 8001:8000`

---

#### Test 2: Test Health Endpoints

**Health Check Endpoint:**

**Command:**
```bash
curl http://localhost:8000/health
```

**Expected Output:**
```json
{
  "status": "healthy",
  "timestamp": "2024-11-27T15:00:00Z"
}
```

**What to Check:**
- Status is "healthy"
- Response is valid JSON
- Response time is reasonable (< 1 second)

**Readiness Check Endpoint:**

**Command:**
```bash
curl http://localhost:8000/ready
```

**Expected Output:**
```json
{
  "status": "ready",
  "model_loaded": true,
  "gpu_available": true
}
```

**What to Check:**
- Status is "ready"
- Model is loaded
- GPU is available

**Verbose Output:**
```bash
curl -v http://localhost:8000/health
```

**Expected Output:**
```
*   Trying 127.0.0.1:8000...
* Connected to localhost (127.0.0.1) port 8000
> GET /health HTTP/1.1
> Host: localhost:8000
> User-Agent: curl/7.68.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 45
<
{"status": "healthy", "timestamp": "..."}
```

**What to Check:**
- HTTP status is 200 OK
- Content-Type is application/json
- Response body is valid

**Troubleshooting:**
- If 503 Service Unavailable: Pod may not be ready yet, wait and retry
- If connection refused: Check port-forward is still running
- If 404 Not Found: Verify endpoint path is correct

---

#### Test 3: Test Inference - Simple Request

**Simple Completion Request:**

**Command:**
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Hello, how are you?",
    "max_tokens": 50,
    "temperature": 0.7
  }'
```

**Expected Output:**
```json
{
  "id": "cmpl-1234567890",
  "object": "text_completion",
  "created": 1701100800,
  "model": "qwen3-32b",
  "choices": [
    {
      "text": "Hello! I'm doing well, thank you for asking. How can I help you today?",
      "index": 0,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 5,
    "completion_tokens": 20,
    "total_tokens": 25
  }
}
```

**What to Check:**
- Response is valid JSON
- Text completion is generated
- Token usage is reported
- Response time is reasonable (may take 10-30 seconds for first request)

**With Pretty Print (using jq):**
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Hello, how are you?",
    "max_tokens": 50,
    "temperature": 0.7
  }' | jq
```

**Expected Output (formatted):**
```json
{
  "id": "cmpl-1234567890",
  "object": "text_completion",
  "created": 1701100800,
  "model": "qwen3-32b",
  "choices": [
    {
      "text": "Hello! I'm doing well...",
      "index": 0,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 5,
    "completion_tokens": 20,
    "total_tokens": 25
  }
}
```

**What to Check:**
- JSON is properly formatted
- All expected fields are present
- Text completion makes sense

**Test with Different Parameters:**

**Higher Temperature (more creative):**
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Write a short story about",
    "max_tokens": 100,
    "temperature": 0.9,
    "top_p": 0.9
  }'
```

**Lower Temperature (more deterministic):**
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is the capital of France?",
    "max_tokens": 10,
    "temperature": 0.1
  }'
```

**What to Check:**
- Different temperatures produce different outputs
- Lower temperature gives more consistent results
- Higher temperature gives more varied results

**Troubleshooting:**
- If timeout: Increase timeout or reduce max_tokens
- If 500 error: Check pod logs for errors
- If empty response: Verify model is loaded correctly

---

#### Test 4: Test Inference - Complex Request

**Multi-turn Conversation:**

**Command:**
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "User: What is machine learning?\nAssistant:",
    "max_tokens": 150,
    "temperature": 0.7,
    "stop": ["User:", "Assistant:"]
  }'
```

**Expected Output:**
```json
{
  "choices": [
    {
      "text": "Machine learning is a subset of artificial intelligence that enables systems to learn and improve from experience without being explicitly programmed...",
      "finish_reason": "stop"
    }
  ]
}
```

**What to Check:**
- Response addresses the question
- Stop sequences work correctly
- Response length is appropriate

**Streaming Response:**

**Command:**
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain quantum computing",
    "max_tokens": 200,
    "stream": true
  }'
```

**Expected Output (streaming):**
```
data: {"choices":[{"text":"Quantum","index":0}]}
data: {"choices":[{"text":" computing","index":0}]}
data: {"choices":[{"text":" is","index":0}]}
...
data: [DONE]
```

**What to Check:**
- Tokens arrive incrementally
- Each line starts with "data: "
- Final line is "[DONE]"

---

#### Test 5: Performance Testing

**Measure Response Time:**

**Command:**
```bash
time curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Test prompt",
    "max_tokens": 10
  }' > /dev/null
```

**Expected Output:**
```
real    0m5.234s
user    0m0.012s
sys     0m0.008s
```

**What to Check:**
- First request may be slower (model warmup)
- Subsequent requests should be faster
- Response time is acceptable for your use case

**Concurrent Requests Test:**

**Command:**
```bash
for i in {1..5}; do
  curl -X POST http://localhost:8000/v1/completions \
    -H "Content-Type: application/json" \
    -d "{\"prompt\":\"Test $i\",\"max_tokens\":10}" &
done
wait
```

**What to Check:**
- Multiple requests can be processed
- No errors occur
- All requests complete

---

#### Test 6: Load Testing

**Install Load Testing Tool (hey):**

```bash
# Download hey
wget https://github.com/rakyll/hey/releases/download/v0.1.4/hey_linux_amd64
chmod +x hey_linux_amd64
sudo mv hey_linux_amd64 /usr/local/bin/hey
```

**Light Load Test:**

**Command:**
```bash
hey -n 50 -c 5 -m POST \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Test","max_tokens":10}' \
  http://localhost:8000/v1/completions
```

**Expected Output:**
```
Summary:
  Total:        10.2345 secs
  Slowest:      2.1234 secs
  Fastest:      0.5678 secs
  Average:      1.2345 secs
  Requests/sec: 4.88

Response time histogram:
  0.568 [1]     |
  1.000 [15]    |■■■
  1.500 [25]    |■■■■■
  2.000 [8]     |■■
  2.123 [1]     |

Status code distribution:
  [200] 50 responses
```

**What to Check:**
- All requests return 200 status
- Average response time is acceptable
- No errors or timeouts
- Requests/sec matches your expectations

**Heavy Load Test:**

**Command:**
```bash
hey -n 200 -c 20 -m POST \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Test","max_tokens":10}' \
  http://localhost:8000/v1/completions
```

**What to Check:**
- System handles increased load
- Response times remain reasonable
- Error rate stays low
- Monitor pod resource usage during test

**Monitor During Load Test:**

**In another terminal:**
```bash
# Watch pod resource usage
kubectl top pod -n aim -l app=aim-qwen3-32b --watch

# Watch pod logs
kubectl logs -n aim -l app=aim-qwen3-32b -f
```

**What to Check:**
- CPU and memory usage
- No OOM errors
- No excessive errors in logs
- System remains stable

---

### Validate Observability

#### Validate Prometheus

**Check Prometheus Deployment:**

**Command:**
```bash
kubectl get pods -n monitoring | grep prometheus
```

**Expected Output:**
```
prometheus-xxxxx   1/1     Running   0          10m
```

**What to Check:**
- Prometheus pod is running
- Status is Ready (1/1)

**Port Forward to Prometheus:**

**Command:**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

**Access Prometheus UI:**
- Open browser: http://localhost:9090
- Navigate to Status > Targets

**Expected Output:**
- `aim-inference` target shows as "UP"
- Other Kubernetes targets show as "UP"

**What to Check:**
- AIM target is being scraped
- No failed scrapes
- Scrape interval is correct

**Test Prometheus Query:**

In Prometheus UI, try:
```
up{job="aim-inference"}
```

**Expected Output:**
- Returns `1` (target is up)

**Query AIM Metrics:**
```
http_requests_total{job="aim-inference"}
```

**Expected Output:**
- Shows request count metrics

---

#### Validate Grafana

**Check Grafana Deployment:**

**Command:**
```bash
kubectl get pods -n monitoring | grep grafana
```

**Expected Output:**
```
grafana-xxxxx   1/1     Running   0          10m
```

**What to Check:**
- Grafana pod is running
- Status is Ready (1/1)

**Port Forward to Grafana:**

**Command:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

**Access Grafana UI:**
- Open browser: http://localhost:3000
- Login: admin / admin (change on first login)

**Verify Data Source:**

1. Navigate to Configuration > Data Sources
2. Select "Prometheus"
3. Click "Test" button

**Expected Output:**
```
Data source is working
```

**What to Check:**
- Prometheus connection works
- URL is correct: `http://prometheus.monitoring.svc.cluster.local:9090`

**View Dashboard:**

1. Navigate to Dashboards
2. Find "AIM Inference Service Dashboard"
3. Open dashboard

**Expected Output:**
- Dashboard displays graphs
- Metrics show data
- No "No data" messages

**What to Check:**
- Request rate graph shows data
- Latency graphs show data
- Resource usage graphs show data
- Time range is correct

---

### Comprehensive Validation Checklist

Use this checklist to ensure everything is working:

- [ ] Cluster connection verified
- [ ] GPU nodes labeled correctly
- [ ] Metrics server installed and working
- [ ] Namespace created
- [ ] ConfigMap created and verified
- [ ] ServiceAccount and RBAC created
- [ ] Deployment created and pods running
- [ ] Service created with endpoints
- [ ] PodDisruptionBudget created
- [ ] Health endpoint returns healthy
- [ ] Ready endpoint returns ready
- [ ] Simple inference request works
- [ ] Complex inference request works
- [ ] Performance is acceptable
- [ ] Load testing passes
- [ ] Prometheus scraping AIM metrics
- [ ] Grafana dashboard shows data
- [ ] No errors in pod logs
- [ ] Resource usage is reasonable

**If all items are checked, your deployment is successful!**

## Troubleshooting

### Storage Class and PVC Issues

#### Problem: PVCs are Pending with "unbound immediate PersistentVolumeClaims"

**Symptoms:**
- Pods show status `Pending`
- Error message: `pod has unbound immediate PersistentVolumeClaims`
- PVCs show status `Pending` with no `VOLUME` assigned

**Solution Steps:**

**1. Check if you have a default storage class:**
```bash
kubectl get storageclass
```

**Expected Output (with default):**
```
NAME                   PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      AGE
local-path (default)   rancher.io/local-path          Delete          WaitForFirstConsumer   15m
```

**2. If no storage class is marked as default, set one:**
```bash
# If you have local-path-provisioner installed
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Or if you have another storage class
kubectl patch storageclass <your-storage-class-name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**3. If PVCs request a storage class named "default" but it doesn't exist:**

This is a common issue when Helm charts are hardcoded to use "default" as the storage class name. Create a storage class named "default":

```bash
# Install local-path-provisioner if not already installed
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# Wait for it to be ready
kubectl wait --for=condition=ready pod -n local-path-storage -l app=local-path-provisioner --timeout=60s

# Create a storage class named "default" using local-path provisioner
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: default
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: false
EOF
```

**4. Verify the storage class was created:**
```bash
kubectl get storageclass
```

**Expected Output:**
```
NAME                   PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      AGE
default                rancher.io/local-path          Delete          WaitForFirstConsumer   5s
local-path (default)   rancher.io/local-path          Delete          WaitForFirstConsumer   15m
```

**5. Check if PVCs bind automatically:**
```bash
kubectl get pvc -n otel-lgtm-stack
```

**Expected Output (after a few seconds):**
```
NAME               STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
grafana-pvc        Bound    pvc-xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx      10Gi       RWO            default        5m
loki-data-pvc      Bound    pvc-xxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx      50Gi       RWO            default        5m
...
```

**6. If PVCs are still Pending, check local-path-provisioner logs:**
```bash
kubectl logs -n local-path-storage -l app=local-path-provisioner --tail=50
```

**7. Once PVCs are Bound, check if pods start:**
```bash
kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana"
```

**Expected Output:**
```
NAME                     READY   STATUS    RESTARTS   AGE
lgtm-xxxxx               2/2     Running   0          5m
```

#### Problem: PVCs show STORAGECLASS as "default" but no "default" storage class exists

**Symptoms:**
- `kubectl get pvc` shows `STORAGECLASS   default`
- `kubectl get storageclass` shows no storage class named "default"
- PVCs remain Pending

**Solution:**

This happens when Helm charts are configured to use "default" as the storage class name. Follow the steps above to create a storage class named "default" using your preferred provisioner (local-path-provisioner recommended).

**Note:** You cannot patch PVCs to change their storage class after creation (PVCs are immutable for storageClassName). You must either:
1. Create a storage class named "default" (recommended)
2. Delete PVCs and reconfigure the installation to use a different storage class name

### Remote Access Setup (SSH Port Forwarding)

**If you are accessing the Kubernetes cluster remotely via SSH**, you'll need to set up SSH port forwarding to access services that are port-forwarded on the remote node.

#### On Your Local Machine

**Establish SSH connection with port forwarding:**

```bash
# SSH to the remote MI300X node with port forwarding for common services
ssh -L 8000:localhost:8000 -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 user@remote-mi300x-node
```

**Port Forwarding Reference:**
- **Port 8000**: AIM inference service (Step 4)
- **Port 8080**: Scalable AIM inference service (Step 7)
- **Port 3000**: Grafana dashboard (Step 6)
- **Port 9090**: Prometheus (optional, for direct Prometheus access)

**Important Notes:**
- Keep the SSH session open while using port-forwarded services
- You can add more port forwards to the SSH command as needed
- If you're already connected via SSH, you can use `kubectl port-forward` directly on the remote node

#### Alternative: Use SSH Config for Persistent Port Forwarding

**Add to your `~/.ssh/config` on your local machine:**

```
Host mi300x-cluster
    HostName <remote-node-ip-or-hostname>
    User <your-username>
    LocalForward 8000 localhost:8000
    LocalForward 8080 localhost:8080
    LocalForward 3000 localhost:3000
    LocalForward 9090 localhost:9090
```

**Then connect with:**
```bash
ssh mi300x-cluster
```

#### Using Port Forwarding

**On the remote node, set up port forwarding:**
```bash
# For AIM inference service (Step 4)
kubectl port-forward service/aim-qwen3-32b-predictor 8000:80

# For Grafana (Step 6)
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000

# For scalable AIM service (Step 7)
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
```

**On your local machine, access the services:**
- AIM inference: http://localhost:8000
- Grafana: http://localhost:3000
- Scalable AIM service: http://localhost:8080

### Pod Status Issues

#### Problem: Pod is Pending - "pod has unbound immediate PersistentVolumeClaims"

See [Storage Class and PVC Issues](#storage-class-and-pvc-issues) section above.

#### Problem: Pod is Pending - No specific error

**Check pod events:**
```bash
kubectl describe pod -n <namespace> <pod-name> | grep -A 20 "Events:"
```

**Common causes:**
1. **Insufficient resources** - Check node resources: `kubectl describe node <node-name>`
2. **Image pull issues** - Check events for "ImagePull" errors
3. **Storage issues** - See Storage Class and PVC Issues section
4. **Node selector/affinity** - Check if pod has node requirements that can't be met

#### Problem: Pod shows 0/2 Ready or 0/1 Ready

**This is normal during startup. Wait for containers to initialize:**
```bash
# Watch pod status
kubectl get pod -n <namespace> <pod-name> -w

# Or wait for it to be ready
kubectl wait --for=condition=ready pod -n <namespace> <pod-name> --timeout=600s
```

**If pod stays at 0/X Ready for too long:**
```bash
# Check container status
kubectl describe pod -n <namespace> <pod-name> | grep -A 10 "Containers:"

# Check container logs
kubectl logs -n <namespace> <pod-name> -c <container-name>
```

### Grafana Access Issues

#### Problem: Cannot access Grafana after port-forwarding - "Unable to connect" or "Connection reset"

**Symptoms:**
- Browser shows "Unable to connect" or "Connection refused"
- Cannot access http://localhost:3000

**Diagnosis Steps:**

**1. Verify Grafana pod is Running:**
```bash
kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana"
```

**Expected Output:**
```
lgtm-xxxxx   2/2     Running   0          10m
```

**2. Verify port-forward is running on the remote node:**
```bash
# On the remote node, check if port-forward process is running
ps aux | grep "kubectl port-forward" | grep 3000

# Or check if port 3000 is listening
netstat -tlnp | grep 3000
# Or
ss -tlnp | grep 3000
```

**3. If port-forward is not running, start it:**
```bash
# On the remote node
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000
```

**Expected Output:**
```
Forwarding from 127.0.0.1:3000 -> 3000
Forwarding from [::1]:3000 -> 3000
```

**Keep this terminal open!** The port-forward must stay running.

**4. For remote access, verify SSH port forwarding is set up:**

**On your local machine, check if you have an active SSH connection with port forwarding:**
```bash
# Check SSH processes
ps aux | grep "ssh.*3000"

# Test if local port 3000 is accessible
curl -v http://localhost:3000
```

**If SSH port forwarding is not set up:**

**Option A: Establish new SSH connection with port forwarding:**
```bash
# On your local machine, connect with port forwarding
ssh -L 3000:localhost:3000 user@remote-mi300x-node

# Keep this SSH session open
# In another terminal on the remote node, start kubectl port-forward
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000
```

**Option B: Add port forwarding to existing SSH connection (if using SSH config):**
```bash
# Edit ~/.ssh/config on local machine
# Add LocalForward 3000 localhost:3000 to your host entry
# Then reconnect: ssh mi300x-cluster
```

**5. Verify the connection chain:**

**On remote node:**
```bash
# Test if Grafana is accessible on remote node
curl http://localhost:3000
# Should return HTML (may show login page or redirect)
```

**On local machine (if accessing remotely):**
```bash
# Test if local port forwarding works
curl http://localhost:3000
# Should return the same HTML as above
```

**6. If you get "Connection reset" error:**

**This usually means the kubectl port-forward on the remote node stopped or the SSH connection dropped.**

**Quick diagnosis:**

**On remote node:**
```bash
# Check if port-forward is still running
ps aux | grep "kubectl port-forward" | grep 3000

# Check if port 3000 is listening
ss -tlnp | grep 3000

# Test if Grafana is accessible locally on remote node
curl -I http://localhost:3000
```

**On local machine:**
```bash
# Check if SSH connection is still active
ps aux | grep "ssh.*3000"

# Test SSH tunnel
curl -I http://localhost:3000
```

**Solution - Restart the connection chain:**

**Step 1: On remote node, restart port-forward:**
```bash
# Stop any existing port-forward (if running)
pkill -f "kubectl port-forward.*3000"

# Start fresh port-forward (keep this terminal open!)
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000
```

**Step 2: On local machine, reconnect SSH (if needed):**
```bash
# If SSH connection dropped, reconnect with port forwarding
ssh -L 3000:localhost:3000 user@remote-mi300x-node
# Keep this SSH session open!
```

**Step 3: Verify connection:**
```bash
# On local machine
curl -I http://localhost:3000
# Should return HTTP 200 or 302 (redirect to login)
```

**Step 4: Access in browser:**
- Open http://localhost:3000
- Should see Grafana login page

**Important:** Both the SSH connection AND the kubectl port-forward must stay running for the connection to work. If either stops, you'll get "Connection reset".

**7. Check Grafana service:**
```bash
kubectl get svc -n otel-lgtm-stack lgtm-stack
```

**Expected Output:**
```
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                                   AGE
lgtm-stack   ClusterIP   10.106.212.140   <none>        3000/TCP,4317/TCP,4318/TCP,9090/TCP,3100/TCP              93m
```

**7. Check for firewall issues:**
```bash
# On remote node, check if port 3000 is blocked
sudo iptables -L -n | grep 3000
# Or check firewall status
sudo ufw status
```

**Common Solutions:**

**Solution 1: Port-forward not running**
- Start port-forward on remote node: `kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000`
- Keep the terminal open

**Solution 2: SSH port forwarding not set up (for remote access)**
- Establish SSH connection with port forwarding: `ssh -L 3000:localhost:3000 user@remote-node`
- Keep SSH session open
- Then start kubectl port-forward on remote node

**Solution 3: Port already in use**
- Use different local port: `ssh -L 3001:localhost:3000 user@remote-node`
- Access Grafana at http://localhost:3001

**Solution 4: Browser cache/connection issues**
- Try incognito/private browsing mode
- Clear browser cache
- Try different browser
- Try accessing via IP: http://127.0.0.1:3000

**Solution 5: Check if Grafana is actually running**
```bash
# Check pod logs for errors
kubectl logs -n otel-lgtm-stack -l app=lgtm-stack --tail=50

# Check if Grafana container is ready
kubectl get pod -n otel-lgtm-stack -l app=lgtm-stack -o jsonpath='{.items[0].status.containerStatuses[*].ready}'
```

#### Problem: Grafana shows "No data" in dashboards

**1. Verify Prometheus data source is configured:**
- Navigate to Configuration > Data Sources in Grafana
- Check Prometheus data source status
- URL should be: `http://lgtm-stack.otel-lgtm-stack.svc:9090`

**2. Send some inference requests to generate metrics:**
- Follow Step 7 to send inference requests
- Wait a few minutes for metrics to be scraped

**3. Check if metrics are being collected:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090

# Query metrics in browser: http://localhost:9090
# Try query: up{job="vllm"}
```

## Troubleshooting

### Pod Not Starting

**Symptoms**: Pod in `Pending` or `CrashLoopBackOff` state

**Diagnosis**:
```bash
# Check pod events
kubectl describe pod -n <namespace> <pod-name> | grep -A 20 "Events:"

# Check pod logs (if container is running)
kubectl logs -n <namespace> <pod-name> --tail=100

# Check node resources
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

**Common Issues**:
1. **Storage/PVC issues**: See [Storage Class and PVC Issues](#storage-class-and-pvc-issues) section
2. **Insufficient GPU resources**: No GPU nodes available or GPU device plugin not installed
3. **Node selector mismatch**: Node not labeled correctly
4. **Image pull errors**: Check image name and registry access
5. **Resource limits too high**: Adjust requests/limits in deployment

### Service Not Accessible

**Symptoms**: Cannot connect to service

**Diagnosis**:
```bash
# Check service endpoints
kubectl get endpoints -n aim

# Check service configuration
kubectl describe svc aim-qwen3-32b -n aim

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://aim-qwen3-32b.aim.svc.cluster.local:8000/health
```

**Solutions**:
1. Verify pods are running and ready
2. Check service selector matches pod labels
3. Verify port configuration matches container port

### HPA Not Scaling

**Symptoms**: HPA shows no scaling activity

**Diagnosis**:
```bash
# Check HPA status
kubectl describe hpa aim-qwen3-32b-hpa -n aim

# Check metrics-server
kubectl top pods -n aim

# Check HPA events
kubectl get events -n aim --sort-by='.lastTimestamp' | grep hpa
```

**Solutions**:
1. Install metrics-server if not present
2. Verify metrics-server is working: `kubectl top nodes`
3. Check HPA metrics configuration
4. Ensure pods have resource requests/limits set

### Observability Issues

**Prometheus Not Scraping**:
```bash
# Check Prometheus targets (for otel-lgtm-stack)
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090
# Navigate to Status > Targets in browser: http://localhost:9090
# Note: If accessing remotely, ensure SSH port forwarding for port 9090 is set up

# Verify pod annotations
kubectl get pods -n <namespace> -o yaml | grep prometheus.io
```

**Grafana Not Showing Data**:
```bash
# Check Grafana datasource
# Access Grafana: http://localhost:3000 (after port-forwarding)
# Navigate to Configuration > Data Sources
# Verify Prometheus URL: http://lgtm-stack.otel-lgtm-stack.svc:9090
# Test the connection

# Check if metrics are being generated
# Send some inference requests (Step 7) and wait a few minutes for metrics to be scraped
```

**Grafana Pod Not Starting**:
- See [Storage Class and PVC Issues](#storage-class-and-pvc-issues) section above
- Check if LGTM pod is Running: `kubectl get pods -n otel-lgtm-stack | grep lgtm`
- Verify PVCs are Bound: `kubectl get pvc -n otel-lgtm-stack`
- Check pod events: `kubectl describe pod -n otel-lgtm-stack <pod-name> | grep -A 20 "Events:"`
kubectl exec -n monitoring deployment/grafana -- \
  curl http://prometheus.monitoring.svc.cluster.local:9090/api/v1/status/config
```

## Production Considerations

### Security

1. **ServiceAccount**: Use dedicated service account with minimal permissions
2. **Network Policies**: Implement network policies to restrict traffic
3. **Secrets Management**: Use Kubernetes secrets for sensitive data
4. **Image Security**: Scan container images for vulnerabilities
5. **RBAC**: Limit access to AIM namespace

### High Availability

1. **Multiple Replicas**: Set minReplicas > 1 in HPA
2. **Pod Anti-Affinity**: Distribute pods across nodes
3. **PodDisruptionBudget**: Ensure minimum availability during updates
4. **Health Checks**: Configure proper liveness/readiness probes

### Resource Management

1. **Resource Quotas**: Set namespace resource quotas
2. **Limit Ranges**: Define default resource limits
3. **Priority Classes**: Use priority classes for critical workloads

### Monitoring and Alerting

1. **Alert Rules**: Configure Prometheus alert rules
2. **Alertmanager**: Set up alert routing and notifications
3. **Log Aggregation**: Use centralized logging (e.g., ELK, Loki)
4. **Distributed Tracing**: Implement tracing for request flow

### Backup and Recovery

1. **ConfigMaps/Secrets**: Version control all configurations
2. **Persistent Storage**: Use persistent volumes for Prometheus data
3. **Disaster Recovery**: Plan for cluster failure scenarios

## Cleanup

### Remove InferenceServices

**Delete InferenceServices:**

```bash
# Delete basic inference service
kubectl delete inferenceservice aim-qwen3-32b

# Delete scalable inference service (if deployed)
kubectl delete inferenceservice aim-qwen3-32b-scalable
```

**Verify Removal:**
```bash
kubectl get inferenceservice
```

**Expected Output:**
```
No resources found in default namespace.
```

### Remove ServingRuntime

**Delete ClusterServingRuntime:**

```bash
kubectl delete clusterservingruntime aim-qwen3-32b-runtime
```

**Verify Removal:**
```bash
kubectl get clusterservingruntime
```

### Remove KServe Infrastructure (Optional)

**Warning:** This will remove KServe from your cluster, affecting all KServe-based services.

```bash
cd aim-deploy/kserve/kserve-install
bash ./uninstall-deps.sh
```

**Or manually remove components:**

```bash
# Remove KServe controller
kubectl delete namespace kserve

# Remove cert-manager (if not used by other services)
kubectl delete namespace cert-manager

# Remove Gateway API CRDs
kubectl delete crd gateways.gateway.networking.k8s.io
kubectl delete crd httproutes.gateway.networking.k8s.io
# ... (other Gateway API CRDs)
```

### Remove Observability Stack (Optional)

**If observability was installed:**

```bash
# Remove OpenTelemetry LGTM stack
kubectl delete namespace otel-lgtm-stack

# Remove KEDA
kubectl delete namespace keda
```

**Or use the uninstall script:**

```bash
cd aim-deploy/kserve/kserve-install
bash ./uninstall-deps.sh --enable=otel-lgtm-stack-standalone,keda
```

### Complete Cleanup

**To remove everything:**

```bash
# 1. Delete all InferenceServices
kubectl delete inferenceservice --all

# 2. Delete all ServingRuntimes
kubectl delete clusterservingruntime --all

# 3. Remove observability (if installed)
kubectl delete namespace otel-lgtm-stack keda

# 4. Remove KServe (if desired)
cd aim-deploy/kserve/kserve-install
bash ./uninstall-deps.sh
```

## Additional Resources

- [AMD AIM Blog - KServe Deployment](https://rocm.blogs.amd.com/artificial-intelligence/enterprise-ai-aims/README.html) - Official AMD guide
- [AMD AIM Deployment Repository](https://github.com/amd-enterprise-ai/aim-deploy) - Source code and examples
- [KServe Documentation](https://kserve.github.io/website/) - KServe framework documentation
- [KEDA Documentation](https://keda.sh/docs/) - Kubernetes Event-driven Autoscaling
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/) - Observability framework
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Support

For issues specific to:
- **AIM**: Check [AMD AIM GitHub Issues](https://github.com/amd-enterprise-ai/aim-deploy/issues)
- **Kubernetes**: Check [Kubernetes GitHub Issues](https://github.com/kubernetes/kubernetes/issues)
- **ROCm**: Check [ROCm Documentation](https://rocm.docs.amd.com/)

