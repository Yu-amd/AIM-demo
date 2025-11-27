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

# 3.5. Check model endpoint status and wait for ready
kubectl get inferenceservice aim-qwen3-32b
# Wait until READY column shows "True" (may take 5-10 minutes for model to load)
# Or watch the status: kubectl get inferenceservice aim-qwen3-32b -w

# Monitor pod events to track image pulling progress:
# Get pod name and monitor events (one-liner):
POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b -o jsonpath='{.items[0].metadata.name}') && kubectl get events --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' | tail -20
# Or monitor events in real-time:
POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b -o jsonpath='{.items[0].metadata.name}') && kubectl get events --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' -w
# Note: Large model images (32B) can take 15-30+ minutes to pull. Wait for "Pulled" or "Started" events.

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
# Check GPU availability (replace <node-name> with your node name):
kubectl describe node <node-name> | grep -A 5 "amd.com/gpu"
# If single GPU: Stop basic service first (skip this command if you have multiple GPUs)
kubectl delete inferenceservice aim-qwen3-32b
# If multiple GPUs (e.g., 8x MI300X): Skip the delete command above, deploy scalable service alongside it
# Wait for scalable service to start
kubectl wait --for=condition=ready inferenceservice aim-qwen3-32b-scalable --timeout=600s
# For remote access: Set up SSH port forwarding first (on local machine)
ssh -L 8080:localhost:8080 user@remote-mi300x-node
# Keep SSH session open!
# Port forward scalable service (on remote node)
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
# Keep this terminal open!
# In another terminal (or if using SSH, on your local machine), test the service:
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

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

For detailed step-by-step instructions, see [KUBERNETES-DEPLOYMENT.md](./KUBERNETES-DEPLOYMENT.md).

## Repository Structure

```
k8s/
├── KUBERNETES-DEPLOYMENT.md    # Comprehensive deployment guide
├── kubernetes-quick-reference.md # Quick command reference
└── README.md                    # This file
```

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

In another terminal, send a test request:

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
- [KServe Documentation](https://kserve.github.io/website/) - KServe framework documentation
- [KEDA Documentation](https://keda.sh/docs/) - Kubernetes Event-driven Autoscaling
- [Kubernetes-MI300X](https://github.com/Yu-amd/Kubernetes-MI300X) - Kubernetes cluster setup guide
