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

# 4. Test the service
kubectl port-forward service/aim-qwen3-32b-predictor 8000:80
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo
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
