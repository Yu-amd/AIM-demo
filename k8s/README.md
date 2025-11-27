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

# Open a new terminal (or if using SSH, use your local machine terminal):
# If using SSH: The port forwarding is already set up via SSH, so you can run curl directly on your local machine
# If working directly on the node: Open a new terminal on the same node (you'll start in /root)
# Navigate to the deployment directory (or any directory - curl works from anywhere):
cd ~/aim-deploy/kserve/kserve-install
# Make sure the port-forward command above is still running in the previous terminal
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Example queries to try:
# Explain quantum computing in simple terms:
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Explain quantum computing in simple terms"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Write a Python function to calculate fibonacci numbers:
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Write a Python function to calculate fibonacci numbers"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Multi-turn conversation:
curl -X POST http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "What is Kubernetes?"}, {"role": "assistant", "content": "Kubernetes is an open-source container orchestration platform..."}, {"role": "user", "content": "How does it compare to Docker Swarm?"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# 4.5. Deploy scalable service for metrics (optional)
# Get node name(s):
kubectl get nodes
# Check GPU availability (replace <node-name> with the actual node name from the command above):
kubectl describe node <node-name> | grep -A 5 "amd.com/gpu"
# If single GPU: Stop basic service first (skip this command if you have multiple GPUs)
kubectl delete inferenceservice aim-qwen3-32b
# If multiple GPUs (e.g., 8x MI300X): Skip the delete command above, deploy scalable service alongside it
# Check if serving runtime from step 3 is already applied
kubectl get clusterservingruntime aim-qwen3-32b-runtime
# If not found, apply it (from the sample-minimal-aims-deployment directory)
cd ../sample-minimal-aims-deployment
kubectl apply -f servingruntime-aim-qwen3-32b.yaml
cd ../kserve-install

# Create the scalable inference service manifest
cat <<'EOF' > aim-qwen3-32b-scalable.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: aim-qwen3-32b-scalable
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
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
    minReplicas: 1
    maxReplicas: 3
EOF

# Apply the scalable inference service
kubectl apply -f aim-qwen3-32b-scalable.yaml
# Wait for scalable service to start
# Monitor status in real-time (run in another terminal):
# Watch InferenceService status:
kubectl get inferenceservice aim-qwen3-32b-scalable -w
# Or check pod events to track image pulling and startup progress:
POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) && kubectl get events --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' -w
# Or check pod status:
kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -w
# Wait for scalable service to be ready (this may take 15-30+ minutes for large model images):
kubectl wait --for=condition=ready inferenceservice aim-qwen3-32b-scalable --timeout=600s
# For remote access: Set up SSH port forwarding first (on local machine)
ssh -L 8080:localhost:8080 user@remote-mi300x-node
# Keep SSH session open!
# Port forward scalable service (on remote node)
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
# Keep this terminal open!
# Open a new terminal (or if using SSH, use your local machine terminal):
# If using SSH: The port forwarding is already set up via SSH, so you can run curl directly on your local machine
# If working directly on the node: Open a new terminal on the same node (you'll start in /root)
# Navigate to the deployment directory (or any directory - curl works from anywhere):
cd ~/aim-deploy/kserve/kserve-install
# Make sure the port-forward command above is still running in the previous terminal
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Example queries to try:
# Explain quantum computing in simple terms:
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Explain quantum computing in simple terms"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Write a Python function to calculate fibonacci numbers:
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Write a Python function to calculate fibonacci numbers"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Multi-turn conversation:
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "What is Kubernetes?"}, {"role": "assistant", "content": "Kubernetes is an open-source container orchestration platform..."}, {"role": "user", "content": "How does it compare to Docker Swarm?"}], "stream": true}' \
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

# Verify autoscaling is configured (wait a few seconds for KServe to create resources):
sleep 10
# Check if ScaledObject was created (KEDA autoscaling):
kubectl get scaledobject | grep aim-qwen3-32b-scalable
# Check if HPA exists (should be created by KEDA):
kubectl get hpa | grep aim-qwen3-32b-scalable

# Troubleshooting: If ScaledObject is not created and you see HPA conflicts:
# If you see errors about "already managed by the hpa", delete the conflicting HPA:
# kubectl delete hpa aim-qwen3-32b-scalable-predictor
# Then delete and recreate the InferenceService:
# kubectl delete inferenceservice aim-qwen3-32b-scalable
# kubectl apply -f aim-qwen3-32b-scalable.yaml

# 6. Access Grafana dashboard (optional - requires observability setup)
# First, verify LGTM/Grafana pod is Running and Ready
# Automated fix (recommended): Run the script to automatically diagnose and fix storage issues
bash ~/AIM-demo/k8s/scripts/fix-lgtm-storage.sh

# Manual verification (if you prefer to check manually):
# kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana"
# If no pods found, verify observability stack is installed:
# kubectl get pods -n otel-lgtm-stack
# If pod is Pending (e.g., 0/2 Pending), check why:
# LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
# if [ ! -z "$LGTM_POD" ]; then
#   kubectl describe pod -n otel-lgtm-stack $LGTM_POD | grep -A 10 "Events:"
# else
#   echo "No LGTM/Grafana pod found. Check if observability stack is installed: kubectl get pods -n otel-lgtm-stack"
# fi
# If you see "pod has unbound immediate PersistentVolumeClaims", this is a storage class issue
# Check PVC status:
# kubectl get pvc -n otel-lgtm-stack
# If PVCs are Pending, check storage class:
# kubectl get storageclass
# If storage class uses "kubernetes.io/no-provisioner" (like local-storage), install local-path-provisioner:
# kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
# kubectl wait --for=condition=ready pod -n local-path-storage -l app=local-path-provisioner --timeout=60s
# kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
# kubectl patch storageclass local-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
# kubectl delete pvc -n otel-lgtm-stack --all
# LGTM_DEPLOYMENT=$(kubectl get deployment -n otel-lgtm-stack | grep lgtm | awk '{print $1}' | head -1)
# if [ ! -z "$LGTM_DEPLOYMENT" ]; then kubectl delete deployment -n otel-lgtm-stack $LGTM_DEPLOYMENT; fi
# sleep 10
# kubectl get pvc -n otel-lgtm-stack
# Wait for pod to be ready after storage is fixed:
# LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
# if [ ! -z "$LGTM_POD" ]; then
#   kubectl wait --for=condition=ready pod -n otel-lgtm-stack $LGTM_POD --timeout=600s
# else
#   echo "No LGTM/Grafana pod found. Check if observability stack is installed: kubectl get pods -n otel-lgtm-stack"
# fi

# For remote access: Set up SSH port forwarding first (on local machine)
ssh -L 3000:localhost:3000 user@remote-mi300x-node
# Keep SSH session open!

# Port forward Grafana service (on remote node)
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 3000:3000
# Keep this terminal open!

# Open http://localhost:3000 in browser (on local machine if remote, or on remote node if local)
# Default credentials: admin/admin

# What to monitor in Grafana:
# 1. Navigate to Dashboards (left menu) > Browse
# 2. Look for vLLM or AIM dashboards (if pre-configured)
# 3. Key metrics to monitor:
#    - Request rate: Number of requests per second
#    - Request latency: P50, P95, P99 latencies
#    - Tokens per second: Generation throughput
#    - Active requests: Currently processing requests
#    - GPU utilization: GPU usage percentage
#    - Memory usage: Pod memory consumption
#    - Pod replicas: Number of running pods (autoscaling)
# 4. Create custom queries in Explore:
#    - vLLM metrics: vllm:num_requests_running, vllm:request_latency_seconds
#    - Pod metrics: container_memory_usage_bytes, container_cpu_usage_seconds_total
#    - Kubernetes metrics: kube_deployment_status_replicas
# 5. Set up alerts for:
#    - High latency (P95 > threshold)
#    - Low GPU utilization
#    - Pod failures or restarts
#    - High error rates

# 7. Generate inference requests to view metrics and autoscaling (optional)
# For remote access: Set up SSH port forwarding for port 8080 (on local machine)
# ssh -L 8080:localhost:8080 user@remote-mi300x-node
# Or add to existing SSH: ssh -L 8000:localhost:8000 -L 3000:localhost:3000 -L 8080:localhost:8080 user@remote-mi300x-node
# Keep SSH session open!

# Port-forward the scalable service (on remote node)
kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80
# Keep this terminal open!

# In a new terminal (or if using SSH, on your local machine), send inference requests
# Single request (for testing):
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# To trigger autoscaling (scale up), send multiple concurrent requests:
# The autoscaling metric is vllm:num_requests_running with target value of 1
# When running requests exceed 1, it will scale up replicas
# Send 5-10 concurrent requests to trigger scale-up:
for i in {1..5}; do
  curl -X POST http://localhost:8080/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Write a detailed explanation of machine learning (request $i)\"}], \"stream\": true}" \
       --no-buffer > /dev/null 2>&1 &
done
echo "Sent 5 concurrent requests. Monitor autoscaling with: kubectl get deployment -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -w"
# Wait for requests to complete
wait

# Alternative: Use a load testing tool or send requests in a loop:
# while true; do curl -X POST http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' --no-buffer > /dev/null 2>&1 & sleep 1; done

# Example queries to try:
# Explain quantum computing in simple terms:
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Explain quantum computing in simple terms"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Write a Python function to calculate fibonacci numbers:
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Write a Python function to calculate fibonacci numbers"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Multi-turn conversation:
curl -X POST http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "What is Kubernetes?"}, {"role": "assistant", "content": "Kubernetes is an open-source container orchestration platform..."}, {"role": "user", "content": "How does it compare to Docker Swarm?"}], "stream": true}' \
     --no-buffer | \
     sed 's/^data: //' | \
     grep -v '^\[DONE\]$' | \
     jq -r '.choices[0].delta.content // empty' | \
     tr -d '\n' && echo

# Monitor autoscaling status and metrics
# Quick status check (recommended):
bash ~/AIM-demo/k8s/scripts/check-autoscaling.sh

# Or check manually:
# 1. Check ScaledObject status:
kubectl describe scaledobject aim-qwen3-32b-scalable-predictor | grep -A 10 "Status:"
# 2. Check HPA status (created by KEDA):
kubectl get hpa keda-hpa-aim-qwen3-32b-scalable-predictor
# 3. Watch deployment replicas in real-time:
SCALABLE_DEPLOYMENT=$(kubectl get deployment -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$SCALABLE_DEPLOYMENT" ]; then
  kubectl get deployment $SCALABLE_DEPLOYMENT -w
else
  echo "Scalable deployment not found. List all deployments: kubectl get deployment | grep aim-qwen3-32b-scalable"
fi

# What to watch for:
# - READY: Number of ready replicas (should scale up/down based on load)
# - UP-TO-DATE: Replicas updated to latest version
# - AVAILABLE: Replicas available to serve requests
# - HPA TARGETS: Shows current metric value vs target (e.g., "2/1 (avg)" means 2 running requests, target is 1, will scale up)
# As you send concurrent inference requests, you should see:
#   - HPA TARGETS increase (0/1 -> 1/1 -> 2/1 -> 3/1)
#   - Replicas scale up (1 -> 2 -> 3) when metric exceeds target
#   - Replicas scale down when load decreases
# In Grafana, monitor: kube_deployment_status_replicas{deployment="aim-qwen3-32b-scalable-predictor"} to see replica count over time

# Note: Single node with multiple GPUs is fine for autoscaling
# - Autoscaling scales pods (replicas), not nodes
# - With 8 GPUs on one node, you can run up to 8 pods simultaneously
# - All pods can run on the same node if resources allow
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
