#!/bin/bash
# wait-for-ready.sh
# Wait for an InferenceService to become ready and provide monitoring options

set -e

INFERENCE_SERVICE="${1:-aim-qwen3-32b}"
TIMEOUT="${2:-600}"
MODE="${3:-watch}"

echo "=== Waiting for InferenceService: $INFERENCE_SERVICE ==="
echo ""

# Check if InferenceService exists
if ! kubectl get inferenceservice $INFERENCE_SERVICE > /dev/null 2>&1; then
    echo "ERROR: InferenceService '$INFERENCE_SERVICE' not found"
    exit 1
fi

echo "Monitoring options:"
echo "  1. Watch InferenceService status (default)"
echo "  2. Monitor pod events"
echo "  3. Monitor model loading logs"
echo "  4. Wait silently with timeout"
echo ""

case "$MODE" in
    events)
        echo "Monitoring pod events..."
        POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -z "$POD_NAME" ]; then
            echo "Waiting for pod to be created..."
            sleep 5
            POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        fi
        if [ ! -z "$POD_NAME" ]; then
            kubectl get events --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' -w
        else
            echo "Pod not found yet"
        fi
        ;;
    logs)
        echo "Monitoring model loading logs..."
        POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -z "$POD_NAME" ]; then
            echo "Waiting for pod to be created..."
            while [ -z "$POD_NAME" ]; do
                sleep 2
                POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            done
        fi
        echo "Pod: $POD_NAME"
        kubectl logs $POD_NAME -c kserve-container -f
        ;;
    wait)
        echo "Waiting for service to be ready (timeout: ${TIMEOUT}s)..."
        if kubectl wait --for=condition=ready inferenceservice $INFERENCE_SERVICE --timeout=${TIMEOUT}s 2>/dev/null; then
            echo ""
            echo "✓ Service is ready!"
            kubectl get inferenceservice $INFERENCE_SERVICE
        else
            echo ""
            echo "✗ Service did not become ready within ${TIMEOUT}s"
            echo "Current status:"
            kubectl get inferenceservice $INFERENCE_SERVICE
            exit 1
        fi
        ;;
    watch|*)
        echo "Watching InferenceService status (Ctrl+C to stop)..."
        kubectl get inferenceservice $INFERENCE_SERVICE -w
        ;;
esac

