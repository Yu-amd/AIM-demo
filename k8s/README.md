# Kubernetes Deployment Guide for AMD Inference Microservice (AIM)

This guide provides comprehensive instructions for deploying AMD Inference Microservice (AIM) on Kubernetes using **KServe**, the official Kubernetes-native framework for serving ML models. This follows the [official AMD AIM deployment approach](https://rocm.blogs.amd.com/artificial-intelligence/enterprise-ai-aims/README.html).

## Overview

AMD Inference Microservice (AIM) provides a streamlined way to deploy AI models on AMD Instinct GPUs in Kubernetes clusters. This deployment includes:

- **KServe-Based Deployment**: Official AMD AIM deployment approach
- **Production-Ready Configuration**: Resource management, health checks, and high availability
- **Observability**: OpenTelemetry LGTM stack with Grafana dashboards
- **Autoscaling**: KEDA-based autoscaling with custom metrics

## Quick Links

- **[KUBERNETES-DEPLOYMENT.md](./KUBERNETES-DEPLOYMENT.md)** - Comprehensive step-by-step deployment guide
- **[kubernetes-quick-reference.md](./kubernetes-quick-reference.md)** - Quick command reference

## Prerequisites

### Kubernetes Cluster Setup

**Before proceeding, you must have a Kubernetes cluster with AMD GPU support configured.**

**Note:** If you're using AMD Developer Cloud or a fresh node, you'll need to set up Kubernetes first before validating prerequisites.

Set up your cluster using the [Kubernetes-MI300X guide](https://github.com/Yu-amd/Kubernetes-MI300X):

```bash
# Clone the Kubernetes-MI300X repository
git clone https://github.com/Yu-amd/Kubernetes-MI300X.git
cd Kubernetes-MI300X

# Run system check
sudo ./check-system-enhanced.sh

# Install Kubernetes
sudo ./install-kubernetes.sh

# Install AMD GPU Operator
./install-amd-gpu-operator.sh
```

### Required Tools

- `kubectl` (v1.24+) - Kubernetes command-line tool
- `Helm 3.8+` - Package manager for Kubernetes
- **Cluster admin privileges** - Required for installing KServe
- **Internet access** - For pulling charts and manifests
- `curl` - For testing the service
- `git` - For cloning the deployment repository

### Cluster Requirements

- **Kubernetes**: v1.28+ (installed via Kubernetes-MI300X)
- **GPU Nodes**: AMD Instinct MI300X GPUs with AMD GPU Operator installed
- **Default Storage Class**: Required for observability components (optional but recommended)

### Automated Prerequisites Validation

**After setting up your Kubernetes cluster, run the automated validation script to verify everything is configured correctly:**

**Navigate to the AIM-demo directory:**
```bash
# If you're currently in the Kubernetes-MI300X directory
cd ~/AIM-demo/k8s/scripts

# Or if you need to clone the AIM-demo repository first
cd ~
git clone https://github.com/Yu-amd/AIM-demo.git
cd AIM-demo/k8s/scripts
```

**Run the validation script:**
```bash
bash ./validate-k8s-prerequisites.sh
```

This script checks all prerequisites automatically and provides a summary. See [KUBERNETES-DEPLOYMENT.md](./KUBERNETES-DEPLOYMENT.md) for detailed prerequisite information.

**Note:** This validation script requires an existing Kubernetes cluster. If you haven't set up your cluster yet, complete the Kubernetes Cluster Setup section above first.

## Quick Start

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

# 4. Wait for service to be ready (choose one monitoring option):
# Option A: Watch status (recommended for first-time setup)
bash ~/AIM-demo/k8s/scripts/wait-for-ready.sh aim-qwen3-32b watch

# Option B: Monitor pod events (shows image pulling, container starts)
bash ~/AIM-demo/k8s/scripts/wait-for-ready.sh aim-qwen3-32b 600 events

# Option C: Monitor model loading logs (shows download, checkpoint loading, compilation)
bash ~/AIM-demo/k8s/scripts/wait-for-ready.sh aim-qwen3-32b 600 logs

# Option D: Wait silently with timeout (for automation)
bash ~/AIM-demo/k8s/scripts/wait-for-ready.sh aim-qwen3-32b 600 wait

# 5. Set up port forwarding (run in a separate terminal, keep it open):
# For remote access: First set up SSH port forwarding on your local machine:
#   ssh -L 8000:localhost:8000 user@remote-mi300x-node

# Then on the remote node, run:
bash ~/AIM-demo/k8s/scripts/setup-port-forward.sh aim-qwen3-32b 8000

# 6. Test the service (in another terminal):
# The script streams responses in real-time so you can see progress immediately
bash ~/AIM-demo/k8s/scripts/test-inference.sh aim-qwen3-32b 8000

# 7. Deploy scalable service for metrics and autoscaling (optional):
# This script handles GPU checking, service deletion if needed, and deployment
bash ~/AIM-demo/k8s/scripts/deploy-scalable-service.sh

# After deployment, wait for scalable service:
bash ~/AIM-demo/k8s/scripts/wait-for-ready.sh aim-qwen3-32b-scalable watch

# Set up port forwarding for scalable service (port 8080):
bash ~/AIM-demo/k8s/scripts/setup-port-forward.sh aim-qwen3-32b-scalable 8080

# Test scalable service (responses stream in real-time):
bash ~/AIM-demo/k8s/scripts/test-inference.sh aim-qwen3-32b-scalable 8080

# 8. Access Grafana dashboard (optional - requires observability setup):
# First, verify Grafana is running:
kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana"

# If pod is not ready, fix storage issues (if needed):
bash ~/AIM-demo/k8s/scripts/fix-lgtm-storage.sh

# Set up port forwarding for Grafana (run in a separate terminal, keep it open):
# For remote access: First set up SSH port forwarding on your local machine:
#   ssh -L 3000:localhost:3000 user@remote-mi300x-node

# Then on the remote node, port forward Grafana:
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000

# Access Grafana in your browser: http://localhost:3000
# Default credentials: admin/admin (change on first login)
# 
# To view vLLM metrics in Grafana:
# 1. Go to Explore (compass icon)
# 2. Select "Prometheus" as data source
# 3. Try queries like: vllm:num_requests_running
# 
# Verify metrics are being collected:
bash ~/AIM-demo/k8s/scripts/check-grafana-metrics.sh
```

**Note:** All scripts are located in `~/AIM-demo/k8s/scripts/`. For manual commands and detailed explanations, see the [Deployment Steps](#deployment-steps) section below.

For detailed step-by-step instructions, see [KUBERNETES-DEPLOYMENT.md](./KUBERNETES-DEPLOYMENT.md).

## Deployment Steps

### Step 1: Get the Deployment Repository

Clone the official AIM deployment repository:

```bash
git clone https://github.com/amd-enterprise-ai/aim-deploy.git
cd aim-deploy/kserve/kserve-install
```

### Step 2: Install KServe Infrastructure

Install KServe with full observability and autoscaling:

```bash
bash ./install-deps.sh --enable=full
```

This installs:
- cert-manager
- Gateway API CRDs
- KServe CRDs and controller
- OpenTelemetry LGTM stack (Loki, Grafana, Tempo, Mimir)
- KEDA (Kubernetes Event-driven Autoscaling)

### Step 3: Deploy AIM Inference Service

Deploy the ServingRuntime and InferenceService:

```bash
cd ../sample-minimal-aims-deployment
kubectl apply -f servingruntime-aim-qwen3-32b.yaml
kubectl apply -f aim-qwen3-32b.yaml
```

### Step 4: Verify Deployment

Check the InferenceService status:

```bash
kubectl get inferenceservice aim-qwen3-32b
```

Wait until the READY column shows "True" (may take 5-10 minutes for model loading).

### Step 5: Test the Service

Port forward and test:

```bash
kubectl port-forward service/aim-qwen3-32b-predictor 8000:80
```

In another terminal, test using the provided script (recommended - streams responses in real-time):

```bash
bash ~/AIM-demo/k8s/scripts/test-inference.sh aim-qwen3-32b 8000
```

**Note:** The test script streams responses in real-time, so you'll see the output appear progressively rather than waiting for the complete response. This provides immediate feedback that the service is working.

Alternatively, you can send a test request manually:

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer -N -s | \
     while IFS= read -r line; do
         line="${line#data: }"
         [[ "$line" == "[DONE]" ]] && continue
         [[ -z "$line" ]] && continue
         echo "$line" | jq -r '.choices[0].delta.content // empty' 2>/dev/null | tr -d '\n'
     done && echo
```

## Features

### KServe-Based Deployment

- **InferenceService CRD**: Kubernetes-native model serving
- **ServingRuntime CRD**: Reusable runtime configurations
- **Automatic Service Creation**: KServe creates services automatically
- **Canary Deployments**: Support for gradual rollouts

### Observability (Optional)

- **OpenTelemetry LGTM Stack**: Comprehensive metrics, logs, and traces
- **Grafana Dashboards**: Pre-configured visualization
- **vLLM Metrics**: Real-time inference metrics collection
- **Prometheus Integration**: Metrics scraping and storage

### Autoscaling (Optional)

- **KEDA Integration**: Custom metrics-based autoscaling
- **vLLM Metrics**: Scale based on running inference requests
- **Configurable Policies**: Min/max replicas and scaling behavior

## Documentation

- **[KUBERNETES-DEPLOYMENT.md](./KUBERNETES-DEPLOYMENT.md)**: Comprehensive guide covering:
  - Prerequisites and cluster setup
  - Detailed step-by-step deployment instructions
  - Observability configuration
  - Scalability setup
  - Testing and validation
  - Troubleshooting guide
  - Production considerations

- **[kubernetes-quick-reference.md](./kubernetes-quick-reference.md)**: Quick command reference for common operations

## System Requirements

### Hardware
- AMD Instinct MI300X GPU
- Sufficient system memory (64Gi+ per pod)
- CPU cores (8+ per pod)

### Software
- Kubernetes v1.28+ (installed via [Kubernetes-MI300X](https://github.com/Yu-amd/Kubernetes-MI300X))
- AMD GPU Operator (installed via Kubernetes-MI300X)
- ROCm drivers
- Container runtime (containerd, configured during cluster setup)

## Support and Resources

- [AMD AIM Blog - KServe Deployment](https://rocm.blogs.amd.com/artificial-intelligence/enterprise-ai-aims/README.html) - Official AMD guide
- [AMD AIM Deployment Repository](https://github.com/amd-enterprise-ai/aim-deploy) - Source code and examples
- [Kubernetes-MI300X](https://github.com/Yu-amd/Kubernetes-MI300X) - Kubernetes cluster setup guide
