#!/bin/bash
# check-collector-connection.sh
# Check if the OpenTelemetry collector can connect to LGTM stack

echo "=== Checking Collector to LGTM Stack Connection ==="
echo ""

# Check if LGTM stack is ready
echo "1. Checking LGTM stack status..."
LGTM_POD=$(kubectl get pods -n otel-lgtm-stack | grep "^lgtm-" | awk '{print $1}' | head -1)
if [ ! -z "$LGTM_POD" ]; then
    LGTM_READY=$(kubectl get pod -n otel-lgtm-stack $LGTM_POD -o jsonpath='{.status.containerStatuses[?(@.name=="lgtm")].ready}' 2>/dev/null)
    if [ "$LGTM_READY" = "true" ]; then
        echo "   ✓ LGTM stack pod is ready: $LGTM_POD"
    else
        echo "   ⚠ LGTM stack pod exists but container not ready: $LGTM_POD"
    fi
else
    echo "   ✗ LGTM stack pod not found"
    exit 1
fi

# Test connectivity
echo ""
echo "2. Testing connectivity to LGTM stack on port 4318..."
kubectl run -n otel-lgtm-stack test-otel-connection --image=curlimages/curl:latest --rm -i --restart=Never -- curl -s -o /dev/null -w "%{http_code}" --max-time 3 -X POST http://lgtm-stack.otel-lgtm-stack.svc:4318/v1/metrics 2>&1 | tail -1
HTTP_CODE=$(kubectl run -n otel-lgtm-stack test-otel-connection --image=curlimages/curl:latest --rm -i --restart=Never -- curl -s -o /dev/null -w "%{http_code}" --max-time 3 -X POST http://lgtm-stack.otel-lgtm-stack.svc:4318/v1/metrics 2>&1 | tail -1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ] || [ "$HTTP_CODE" = "405" ]; then
    echo "   ✓ Connection successful (HTTP $HTTP_CODE)"
    echo "   Note: 405 is expected for empty POST - endpoint is reachable"
else
    echo "   ✗ Connection failed (HTTP $HTTP_CODE)"
fi

# Check collector logs
echo ""
echo "3. Checking recent collector logs for connection status..."
COLLECTOR_POD=$(kubectl get pods -n otel-lgtm-stack -l app.kubernetes.io/name=kgateway-metrics-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$COLLECTOR_POD" ]; then
    echo "   Collector pod: $COLLECTOR_POD"
    RECENT_ERRORS=$(kubectl logs -n otel-lgtm-stack $COLLECTOR_POD --tail=10 2>/dev/null | grep -i "connection refused\|failed" | wc -l)
    if [ "$RECENT_ERRORS" -eq 0 ]; then
        echo "   ✓ No recent connection errors in collector logs"
    else
        echo "   ⚠ Found $RECENT_ERRORS recent connection errors"
        echo "   Recent errors:"
        kubectl logs -n otel-lgtm-stack $COLLECTOR_POD --tail=5 2>/dev/null | grep -i "connection refused\|failed" | tail -3 | sed 's/^/      /'
        echo ""
        echo "   Note: These errors may be from before LGTM stack was ready."
        echo "   The collector will retry automatically."
    fi
else
    echo "   ✗ Collector pod not found"
fi

echo ""
echo "=== Summary ==="
echo "If connectivity test passed, the collector should be able to connect."
echo "Connection errors in logs may be from earlier when LGTM stack wasn't ready."
echo "The collector will automatically retry and should eventually connect."
echo ""
echo "Next steps:"
echo "1. Fix the InferenceService configuration (if not done):"
echo "   bash ~/AIM-demo/k8s/scripts/fix-metrics-config.sh aim-qwen3-32b-scalable"
echo ""
echo "2. Restart the InferenceService pod to get the sidecar:"
echo "   kubectl delete pod -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable"
echo ""
echo "3. After pod restarts, the sidecar will send metrics to the collector,"
echo "   which will forward them to the LGTM stack."

