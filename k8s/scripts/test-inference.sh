#!/bin/bash
# test-inference.sh
# Test the AIM inference service with example queries

set -e

INFERENCE_SERVICE="${1:-aim-qwen3-32b}"
PORT="${2:-8000}"
BASE_URL="http://localhost:${PORT}"

echo "=== Testing Inference Service: $INFERENCE_SERVICE ==="
echo ""

# Check if service exists
SVC_NAME="${INFERENCE_SERVICE}-predictor"
if ! kubectl get svc $SVC_NAME > /dev/null 2>&1; then
    echo "ERROR: Service '$SVC_NAME' not found"
    echo ""
    echo "Available services:"
    kubectl get svc | grep -E "NAME|predictor" || echo "  None found"
    echo ""
    echo "Check InferenceService status:"
    kubectl get inferenceservice $INFERENCE_SERVICE 2>/dev/null || echo "  InferenceService not found"
    exit 1
fi

# Check if port-forward is needed
if ! curl -s --max-time 2 "$BASE_URL/health" > /dev/null 2>&1; then
    echo "⚠ Service not accessible on $BASE_URL"
    echo ""
    echo "You need to set up port forwarding first:"
    echo "  kubectl port-forward service/$SVC_NAME ${PORT}:80"
    echo ""
    echo "Run this command in another terminal, then run this script again."
    echo ""
    read -p "Do you want to set up port forwarding now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Starting port forwarding in background..."
        kubectl port-forward service/$SVC_NAME ${PORT}:80 > /tmp/port-forward.log 2>&1 &
        PF_PID=$!
        echo "Port forwarding started (PID: $PF_PID)"
        echo "Logs: /tmp/port-forward.log"
        sleep 3
    else
        exit 1
    fi
fi

# Test function
test_query() {
    local prompt="$1"
    local description="$2"
    
    echo "Query: $description"
    echo "Prompt: $prompt"
    echo "Response:"
    curl -X POST "${BASE_URL}/v1/chat/completions" \
         -H "Content-Type: application/json" \
         -d "{\"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}], \"stream\": true}" \
         --no-buffer 2>/dev/null | \
         sed 's/^data: //' | \
         grep -v '^\[DONE\]$' | \
         jq -r '.choices[0].delta.content // empty' 2>/dev/null | \
         tr -d '\n' && echo ""
    echo ""
}

# Run test queries
echo "Running test queries..."
echo ""

test_query "Hello" "Simple greeting"

test_query "Explain quantum computing in simple terms" "Quantum computing explanation"

test_query "Write a Python function to calculate fibonacci numbers" "Python code generation"

test_query "What is Kubernetes?" "Kubernetes question"

echo "=== Testing Complete ==="
echo ""
echo "To test more queries, you can use:"
echo "  curl -X POST $BASE_URL/v1/chat/completions \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"messages\": [{\"role\": \"user\", \"content\": \"Your question here\"}], \"stream\": true}' \\"
echo "       --no-buffer | sed 's/^data: //' | grep -v '^\[DONE\]$' | jq -r '.choices[0].delta.content // empty' | tr -d '\\n' && echo"

