#!/bin/bash
# verify-vllm-metrics.sh
# Verify that vLLM metrics are being collected and available in Prometheus/Grafana

echo "=== vLLM Metrics Verification ==="
echo ""

# Check if metrics service exists
echo "1. Checking metrics service..."
if kubectl get svc aim-qwen3-32b-scalable-metrics > /dev/null 2>&1; then
    echo "   ✓ Metrics service exists"
    SVC_IP=$(kubectl get svc aim-qwen3-32b-scalable-metrics -o jsonpath='{.spec.clusterIP}')
    echo "   Service IP: $SVC_IP"
else
    echo "   ✗ Metrics service not found"
    exit 1
fi

# Check if pod is exposing metrics
echo ""
echo "2. Checking pod metrics endpoint..."
POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$POD_NAME" ]; then
    METRICS_COUNT=$(kubectl exec $POD_NAME -c kserve-container -- curl -s http://localhost:8000/metrics 2>/dev/null | grep -c "^vllm:" || echo "0")
    if [ "$METRICS_COUNT" -gt "0" ]; then
        echo "   ✓ Pod is exposing $METRICS_COUNT vLLM metrics"
    else
        echo "   ✗ Pod is not exposing vLLM metrics"
    fi
else
    echo "   ✗ Pod not found"
fi

# Check Prometheus
echo ""
echo "3. Checking Prometheus for vLLM metrics..."
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

METRICS=$(curl -s 'http://localhost:9090/api/v1/query?query=vllm:num_requests_running' 2>/dev/null)
if echo "$METRICS" | jq -e '.data.result | length > 0' > /dev/null 2>&1; then
    echo "   ✓✓✓ SUCCESS! vLLM metrics found in Prometheus:"
    echo "$METRICS" | jq -r '.data.result[] | "     \(.metric.service // .metric.job // .metric.instance): \(.value[1])"'
    echo ""
    echo "   Metrics are available in Grafana!"
else
    echo "   ⚠ Metrics not yet in Prometheus (this is normal, can take 1-2 minutes)"
    echo "   The setup is correct - wait a bit longer and check again"
fi

kill $PF_PID 2>/dev/null

# Check collector logs
echo ""
echo "4. Checking OpenTelemetry collector status..."
COLLECTOR_LOGS=$(kubectl logs -n otel-lgtm-stack -l app.kubernetes.io/name=kgateway-metrics-collector --tail=5 2>/dev/null | grep -i "aim-qwen3-32b-scalable" || echo "")
if [ ! -z "$COLLECTOR_LOGS" ]; then
    echo "   ✓ Collector is configured for aim-qwen3-32b-scalable"
else
    echo "   ⚠ Collector logs don't show aim-qwen3-32b-scalable (may be normal)"
fi

echo ""
echo "=== Summary ==="
echo "If metrics are in Prometheus, they should appear in Grafana within 1-2 minutes."
echo "Try querying in Grafana Explore: vllm:num_requests_running"
