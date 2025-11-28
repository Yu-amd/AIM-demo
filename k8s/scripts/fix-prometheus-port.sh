#!/bin/bash
# fix-prometheus-port.sh
# Fixes Prometheus scraping port annotation on KServe pods
# KServe sometimes sets prometheus.io/port to 9091, but vLLM metrics are on port 8000
# This script patches the pod to use the correct port for metrics scraping

set -e

INFERENCE_SERVICE="${1:-aim-qwen3-32b-scalable}"

echo "=== Fixing Prometheus Port Annotation ==="
echo ""

# Get the pod name
POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "ERROR: Pod not found for InferenceService: $INFERENCE_SERVICE"
    echo ""
    echo "Available InferenceServices:"
    kubectl get inferenceservice 2>/dev/null | grep -E "NAME|aim-qwen" || echo "  None found"
    exit 1
fi

echo "Found pod: $POD_NAME"
echo ""

# Check current annotations
CURRENT_PORT=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/port}' 2>/dev/null || echo "")
CURRENT_SCRAPE=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' 2>/dev/null || echo "")

echo "Current annotations:"
echo "  prometheus.io/port: ${CURRENT_PORT:-<not set>}"
echo "  prometheus.io/scrape: ${CURRENT_SCRAPE:-<not set>}"
echo ""

# Check if fix is needed
if [ "$CURRENT_PORT" = "8000" ] && [ "$CURRENT_SCRAPE" = "true" ]; then
    echo "✓ Prometheus annotations are already correct!"
    echo "  Port: 8000 (correct)"
    echo "  Scrape: enabled"
    exit 0
fi

# Fix the annotations
echo "Fixing annotations..."
kubectl patch pod $POD_NAME -p '{"metadata":{"annotations":{"prometheus.io/port":"8000","prometheus.io/scrape":"true","prometheus.io/path":"/metrics"}}}'

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Successfully fixed Prometheus annotations!"
    echo ""
    echo "Updated annotations:"
    kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/port}' && echo " - prometheus.io/port"
    kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' && echo " - prometheus.io/scrape"
    echo ""
    echo "Note: This fix is temporary. If the pod restarts, you may need to run this script again."
    echo "      KServe will recreate the pod with its default annotations."
else
    echo ""
    echo "ERROR: Failed to patch pod"
    exit 1
fi

