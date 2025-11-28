#!/bin/bash
# fix-metrics-config.sh
# Fixes the InferenceService to enable metrics collection by adding:
# 1. Sidecar injection annotation
# 2. VLLM_ENABLE_METRICS environment variable

set -e

INFERENCE_SERVICE="${1:-aim-qwen3-32b-scalable}"

echo "=== Fixing Metrics Configuration for $INFERENCE_SERVICE ==="
echo ""

# Check if InferenceService exists
if ! kubectl get inferenceservice $INFERENCE_SERVICE > /dev/null 2>&1; then
    echo "ERROR: InferenceService '$INFERENCE_SERVICE' not found"
    exit 1
fi

echo "Found InferenceService: $INFERENCE_SERVICE"
echo ""

# Check current configuration
CURRENT_SIDECAR=$(kubectl get inferenceservice $INFERENCE_SERVICE -o jsonpath='{.metadata.annotations.sidecar\.opentelemetry\.io/inject}' 2>/dev/null || echo "")
CURRENT_VLLM_METRICS=$(kubectl get inferenceservice $INFERENCE_SERVICE -o jsonpath='{.spec.predictor.model.env[?(@.name=="VLLM_ENABLE_METRICS")].value}' 2>/dev/null || echo "")

echo "Current configuration:"
echo "  Sidecar annotation: ${CURRENT_SIDECAR:-<not set>}"
echo "  VLLM_ENABLE_METRICS: ${CURRENT_VLLM_METRICS:-<not set>}"
echo ""

# Check if already configured
if [ "$CURRENT_SIDECAR" = "otel-lgtm-stack/vllm-sidecar-collector" ] && [ "$CURRENT_VLLM_METRICS" = "true" ]; then
    echo "✓ Configuration is already correct!"
    exit 0
fi

echo "Updating InferenceService configuration..."
echo ""

# Get the current YAML
CURRENT_YAML=$(kubectl get inferenceservice $INFERENCE_SERVICE -o yaml)

# Check if we need to add the annotation
if [ -z "$CURRENT_SIDECAR" ]; then
    echo "Adding sidecar injection annotation..."
    kubectl annotate inferenceservice $INFERENCE_SERVICE \
        sidecar.opentelemetry.io/inject=otel-lgtm-stack/vllm-sidecar-collector \
        --overwrite
    echo "  ✓ Added sidecar annotation"
else
    echo "  Sidecar annotation already exists: $CURRENT_SIDECAR"
fi

# Check if we need to add VLLM_ENABLE_METRICS
if [ -z "$CURRENT_VLLM_METRICS" ]; then
    echo "Adding VLLM_ENABLE_METRICS environment variable..."
    
    # Use kubectl patch to add the env variable
    # First, check the current structure
    HAS_ENV=$(kubectl get inferenceservice $INFERENCE_SERVICE -o jsonpath='{.spec.predictor.model.env}' 2>/dev/null || echo "[]")
    
    if [ "$HAS_ENV" = "[]" ] || [ -z "$HAS_ENV" ]; then
        # No env section exists, we need to add it
        kubectl patch inferenceservice $INFERENCE_SERVICE --type='json' -p='[
            {
                "op": "add",
                "path": "/spec/predictor/model/env",
                "value": [
                    {
                        "name": "VLLM_ENABLE_METRICS",
                        "value": "true"
                    }
                ]
            }
        ]'
    else
        # Env section exists, add to it
        kubectl patch inferenceservice $INFERENCE_SERVICE --type='json' -p='[
            {
                "op": "add",
                "path": "/spec/predictor/model/env/-",
                "value": {
                    "name": "VLLM_ENABLE_METRICS",
                    "value": "true"
                }
            }
        ]'
    fi
    echo "  ✓ Added VLLM_ENABLE_METRICS=true"
else
    echo "  VLLM_ENABLE_METRICS already set: $CURRENT_VLLM_METRICS"
fi

echo ""
echo "=== Configuration Updated ==="
echo ""

# Verify the changes
echo "Verifying configuration..."
NEW_SIDECAR=$(kubectl get inferenceservice $INFERENCE_SERVICE -o jsonpath='{.metadata.annotations.sidecar\.opentelemetry\.io/inject}' 2>/dev/null || echo "")
NEW_VLLM_METRICS=$(kubectl get inferenceservice $INFERENCE_SERVICE -o jsonpath='{.spec.predictor.model.env[?(@.name=="VLLM_ENABLE_METRICS")].value}' 2>/dev/null || echo "")

if [ "$NEW_SIDECAR" = "otel-lgtm-stack/vllm-sidecar-collector" ] && [ "$NEW_VLLM_METRICS" = "true" ]; then
    echo "✓ Configuration verified successfully!"
    echo ""
    echo "Updated configuration:"
    echo "  Sidecar annotation: $NEW_SIDECAR"
    echo "  VLLM_ENABLE_METRICS: $NEW_VLLM_METRICS"
    echo ""
    echo "⚠ IMPORTANT: The pod will need to be restarted for changes to take effect."
    echo ""
    echo "To restart the pod:"
    echo "  1. Delete the pod (it will be recreated automatically):"
    echo "     kubectl delete pod -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE"
    echo ""
    echo "  2. Wait for the new pod to be ready:"
    echo "     kubectl wait --for=condition=ready pod -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE --timeout=600s"
    echo ""
    echo "  3. Verify the new pod has the sidecar:"
    echo "     kubectl get pod -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE -o jsonpath='{.items[0].spec.containers[*].name}'"
    echo ""
    echo "  4. After the pod restarts, run diagnostics again:"
    echo "     bash ~/AIM-demo/k8s/scripts/diagnose-metrics.sh $INFERENCE_SERVICE"
else
    echo "⚠ Configuration update may have failed. Please check manually:"
    echo "  kubectl get inferenceservice $INFERENCE_SERVICE -o yaml"
    exit 1
fi

