#!/bin/bash
# deploy-scalable-service.sh
# Deploy the scalable inference service with metrics support

set -e

echo "=== Deploying Scalable Inference Service ==="
echo ""

# Check GPU availability
echo "1. Checking GPU availability..."
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
GPU_COUNT=0
for NODE in $NODES; do
    NODE_GPUS=$(kubectl describe node $NODE 2>/dev/null | grep "amd.com/gpu:" | awk '{print $2}' | head -1)
    if [ ! -z "$NODE_GPUS" ] && [ "$NODE_GPUS" != "<none>" ]; then
        GPU_COUNT=$((GPU_COUNT + NODE_GPUS))
        echo "   Node $NODE: $NODE_GPUS GPU(s)"
    fi
done

if [ $GPU_COUNT -eq 0 ]; then
    echo "   ⚠ No GPUs found. Service may not schedule."
else
    echo "   ✓ Total GPUs available: $GPU_COUNT"
fi

echo ""

# Check if basic service exists
if kubectl get inferenceservice aim-qwen3-32b > /dev/null 2>&1; then
    if [ $GPU_COUNT -eq 1 ]; then
        echo "2. Single GPU detected. Basic service must be stopped first."
        echo ""
        read -p "Do you want to delete the basic service (aim-qwen3-32b)? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete inferenceservice aim-qwen3-32b
            echo "   ✓ Basic service deleted"
        else
            echo "   Skipping. You can delete it manually: kubectl delete inferenceservice aim-qwen3-32b"
        fi
    else
        echo "2. Multiple GPUs detected. Basic service can coexist with scalable service."
    fi
else
    echo "2. Basic service not found (this is fine)"
fi

echo ""

# Check serving runtime
echo "3. Checking serving runtime..."
if ! kubectl get clusterservingruntime aim-qwen3-32b-runtime > /dev/null 2>&1; then
    echo "   ⚠ Serving runtime not found"
    echo "   You need to apply it first:"
    echo "     kubectl apply -f servingruntime-aim-qwen3-32b.yaml"
    echo ""
    read -p "Do you want to apply it now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "servingruntime-aim-qwen3-32b.yaml" ]; then
            kubectl apply -f servingruntime-aim-qwen3-32b.yaml
            echo "   ✓ Serving runtime applied"
        else
            echo "   ✗ File not found. Please apply manually from sample-minimal-aims-deployment directory"
            exit 1
        fi
    else
        exit 1
    fi
else
    echo "   ✓ Serving runtime exists"
fi

echo ""

# Create scalable service YAML
echo "4. Creating scalable service manifest..."
cat <<'EOF' > aim-qwen3-32b-scalable.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: aim-qwen3-32b-scalable
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    serving.kserve.io/enable-prometheus-scraping: "true"
    prometheus.io/scrape: "true"
    prometheus.io/path: "/metrics"
    prometheus.io/port: "8000"
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

echo "   ✓ Created aim-qwen3-32b-scalable.yaml"

echo ""

# Apply the service
echo "5. Applying scalable service..."
kubectl apply -f aim-qwen3-32b-scalable.yaml

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Wait for service to be ready:"
echo "     bash ~/AIM-demo/k8s/scripts/wait-for-ready.sh aim-qwen3-32b-scalable"
echo ""
echo "  2. Set up port forwarding:"
echo "     bash ~/AIM-demo/k8s/scripts/setup-port-forward.sh aim-qwen3-32b-scalable 8080"
echo ""
echo "  3. Test the service:"
echo "     bash ~/AIM-demo/k8s/scripts/test-inference.sh aim-qwen3-32b-scalable 8080"
echo ""

