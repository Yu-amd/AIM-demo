#!/bin/bash
# diagnose-metrics.sh
# Comprehensive diagnostics for vLLM metrics not appearing in Grafana

set -e

INFERENCE_SERVICE="${1:-aim-qwen3-32b-scalable}"

echo "=== vLLM Metrics Diagnostics for $INFERENCE_SERVICE ==="
echo ""

# Step 1: Check if InferenceService exists
echo "1. Checking InferenceService..."
if kubectl get inferenceservice $INFERENCE_SERVICE > /dev/null 2>&1; then
    echo "   ✓ InferenceService exists"
    
    # Check for sidecar annotation
    SIDECAR_ANNOTATION=$(kubectl get inferenceservice $INFERENCE_SERVICE -o jsonpath='{.metadata.annotations.sidecar\.opentelemetry\.io/inject}' 2>/dev/null || echo "")
    if [ ! -z "$SIDECAR_ANNOTATION" ]; then
        echo "   ✓ Sidecar injection annotation: $SIDECAR_ANNOTATION"
    else
        echo "   ✗ Missing sidecar injection annotation!"
        echo "      This is required for metrics collection."
        echo "      The InferenceService should have: sidecar.opentelemetry.io/inject: \"otel-lgtm-stack/vllm-sidecar-collector\""
    fi
    
    # Check for VLLM_ENABLE_METRICS
    VLLM_METRICS=$(kubectl get inferenceservice $INFERENCE_SERVICE -o jsonpath='{.spec.predictor.containers[0].env[?(@.name=="VLLM_ENABLE_METRICS")].value}' 2>/dev/null || echo "")
    if [ "$VLLM_METRICS" = "true" ]; then
        echo "   ✓ VLLM_ENABLE_METRICS=true"
    else
        echo "   ✗ VLLM_ENABLE_METRICS not set to true"
        echo "      This is required to enable metrics export."
    fi
else
    echo "   ✗ InferenceService not found!"
    exit 1
fi

echo ""
echo "2. Checking pod status..."
POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=$INFERENCE_SERVICE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD_NAME" ]; then
    echo "   ✗ No pods found for $INFERENCE_SERVICE"
    echo "   → Check if the service is deployed: kubectl get inferenceservice $INFERENCE_SERVICE"
    exit 1
fi

echo "   ✓ Pod found: $POD_NAME"
POD_STATUS=$(kubectl get pod $POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
echo "   Pod status: $POD_STATUS"

# Check if sidecar container exists
SIDECAR_EXISTS=$(kubectl get pod $POD_NAME -o jsonpath='{.spec.containers[*].name}' 2>/dev/null | grep -o "vllm-sidecar-collector" || echo "")
if [ ! -z "$SIDECAR_EXISTS" ]; then
    echo "   ✓ Sidecar container present"
else
    echo "   ✗ Sidecar container not found!"
    echo "      The pod should have a 'vllm-sidecar-collector' container."
    echo "      → Check InferenceService annotation: sidecar.opentelemetry.io/inject"
fi

echo ""
echo "3. Checking metrics endpoint..."
# Try to access metrics from inside the pod
METRICS_COUNT=$(kubectl exec $POD_NAME -c kserve-container -- curl -s http://localhost:8000/metrics 2>/dev/null | grep -c "^vllm:" || echo "0")
if [ "$METRICS_COUNT" -gt "0" ]; then
    echo "   ✓ Pod is exposing $METRICS_COUNT vLLM metrics on /metrics"
    echo "   Sample metrics:"
    kubectl exec $POD_NAME -c kserve-container -- curl -s http://localhost:8000/metrics 2>/dev/null | grep "^vllm:" | head -3 | sed 's/^/      /'
else
    echo "   ✗ No vLLM metrics found on /metrics endpoint"
    echo "   → Check if VLLM_ENABLE_METRICS=true is set"
    echo "   → Check pod logs: kubectl logs $POD_NAME -c kserve-container | grep -i metric"
fi

echo ""
echo "4. Checking Prometheus annotations..."
PROM_PORT=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/port}' 2>/dev/null || echo "")
PROM_SCRAPE=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' 2>/dev/null || echo "")
PROM_PATH=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/path}' 2>/dev/null || echo "")

if [ "$PROM_PORT" = "8000" ] && [ "$PROM_SCRAPE" = "true" ]; then
    echo "   ✓ Prometheus annotations are correct"
    echo "      Port: $PROM_PORT"
    echo "      Scrape: $PROM_SCRAPE"
    echo "      Path: ${PROM_PATH:-/metrics}"
else
    echo "   ✗ Prometheus annotations are incorrect or missing!"
    echo "      Current: port=$PROM_PORT, scrape=$PROM_SCRAPE, path=$PROM_PATH"
    echo "      Expected: port=8000, scrape=true, path=/metrics"
    echo ""
    echo "   → Fixing annotations..."
    kubectl patch pod $POD_NAME -p '{"metadata":{"annotations":{"prometheus.io/port":"8000","prometheus.io/scrape":"true","prometheus.io/path":"/metrics"}}}' 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "   ✓ Fixed Prometheus annotations"
    else
        echo "   ✗ Failed to fix annotations (pod may be immutable)"
        echo "   → You may need to restart the pod or redeploy the service"
    fi
fi

echo ""
echo "5. Checking Prometheus configuration..."
# Check if LGTM stack is running (which includes Prometheus/Mimir)
if kubectl get pods -n otel-lgtm-stack -l app.kubernetes.io/name=lgtm-stack 2>/dev/null | grep -q Running; then
    echo "   ✓ LGTM stack pod is running (includes Prometheus/Mimir)"
    LGTM_POD=$(kubectl get pods -n otel-lgtm-stack -l app.kubernetes.io/name=lgtm-stack -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$LGTM_POD" ]; then
        LGTM_STATUS=$(kubectl get pod $LGTM_POD -n otel-lgtm-stack -o jsonpath='{.status.phase}' 2>/dev/null)
        echo "   Pod: $LGTM_POD (status: $LGTM_STATUS)"
    fi
else
    echo "   ✗ LGTM stack pod not found or not running"
    echo "   → Check: kubectl get pods -n otel-lgtm-stack"
    echo "   → If missing, you may need to set up the observability stack"
fi

# Check if we can query Prometheus
echo ""
echo "6. Checking if metrics are in Prometheus..."
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

METRICS_QUERY=$(curl -s 'http://localhost:9090/api/v1/query?query=vllm:num_requests_running' 2>/dev/null)
if echo "$METRICS_QUERY" | jq -e '.data.result | length > 0' > /dev/null 2>&1; then
    echo "   ✓✓✓ SUCCESS! vLLM metrics found in Prometheus!"
    echo "   Sample metrics:"
    echo "$METRICS_QUERY" | jq -r '.data.result[] | "      \(.metric.service // .metric.job): \(.value[1])"' | head -5
    echo ""
    echo "   → Metrics should appear in Grafana within 1-2 minutes"
else
    echo "   ✗ No vLLM metrics found in Prometheus"
    echo ""
    echo "   Possible causes:"
    echo "   - Prometheus hasn't scraped yet (wait 1-2 minutes and check again)"
    echo "   - Prometheus scrape configuration is incorrect"
    echo "   - Metrics endpoint is not accessible"
    echo ""
    echo "   → Check Prometheus targets:"
    echo "     kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090"
    echo "     Then visit: http://localhost:9090/targets"
    echo ""
    echo "   → Check if Prometheus can see the pod:"
    echo "     curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job | contains(\"aim-qwen3-32b-scalable\"))'"
fi

kill $PF_PID 2>/dev/null

echo ""
echo "7. Checking OpenTelemetry collector..."
COLLECTOR_POD=$(kubectl get pods -n otel-lgtm-stack -l app.kubernetes.io/name=kgateway-metrics-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$COLLECTOR_POD" ]; then
    echo "   ✓ Collector pod found: $COLLECTOR_POD"
    COLLECTOR_STATUS=$(kubectl get pod $COLLECTOR_POD -n otel-lgtm-stack -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "   Collector status: $COLLECTOR_STATUS"
    
    # Check collector logs for errors
    COLLECTOR_ERRORS=$(kubectl logs $COLLECTOR_POD -n otel-lgtm-stack --tail=20 2>/dev/null | grep -i "error\|fail" || echo "")
    if [ ! -z "$COLLECTOR_ERRORS" ]; then
        echo "   ⚠ Collector has errors in logs:"
        echo "$COLLECTOR_ERRORS" | head -3 | sed 's/^/      /'
    else
        echo "   ✓ No errors in collector logs"
    fi
else
    echo "   ✗ Collector pod not found"
    echo "   → Check: kubectl get pods -n otel-lgtm-stack"
fi

echo ""
echo "=== Summary and Next Steps ==="
echo ""
echo "If metrics are in Prometheus, they should appear in Grafana."
echo ""
echo "To view metrics in Grafana:"
echo "1. Go to Explore (compass icon)"
echo "2. Select 'Prometheus' as data source"
echo "3. Try query: vllm:num_requests_running{service=\"isvc.$INFERENCE_SERVICE-predictor\"}"
echo ""
echo "If metrics are still not appearing:"
echo "1. Wait 1-2 minutes for Prometheus to scrape (scrape interval is 60s)"
echo "2. Send some requests to generate metrics:"
echo "   bash ~/AIM-demo/k8s/scripts/test-inference.sh $INFERENCE_SERVICE 8080"
echo "3. Check Prometheus targets: http://localhost:9090/targets"
echo "4. Verify the pod is being scraped by Prometheus"

