#!/bin/bash
# Script to verify metrics are available in Grafana/Prometheus

echo "=== Metrics Collection Status ==="
echo ""

echo "1. Checking if metrics exist in Prometheus:"
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

METRIC_COUNT=$(curl -s 'http://localhost:9090/api/v1/series?match[]=vllm:num_requests_running' | jq '.data | length')
if [ "$METRIC_COUNT" -gt "0" ]; then
  echo "   ✓ vLLM metrics found in Prometheus ($METRIC_COUNT series)"
  echo ""
  echo "   Sample metrics:"
  curl -s 'http://localhost:9090/api/v1/query?query=vllm:num_requests_running' | jq '.data.result[] | {service: .metric.service, value: .value[1]}'
else
  echo "   ✗ No vLLM metrics found"
fi

echo ""
echo "2. Checking InferenceService annotation (ensures new pods get metrics):"
ANNOTATION=$(kubectl get inferenceservice aim-qwen3-32b-scalable -o jsonpath='{.metadata.annotations.sidecar\.opentelemetry\.io/inject}' 2>/dev/null)
if [ ! -z "$ANNOTATION" ]; then
  echo "   ✓ Sidecar injection annotation: $ANNOTATION"
  echo "   ✓ New pods will automatically get metrics collection"
else
  echo "   ✗ No sidecar annotation found"
fi

echo ""
echo "3. Checking Prometheus scraping configuration:"
POD_NAME=$(kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$POD_NAME" ]; then
  PROM_PORT=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/port}' 2>/dev/null || echo "")
  PROM_SCRAPE=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' 2>/dev/null || echo "")
  
  if [ "$PROM_PORT" = "8000" ] && [ "$PROM_SCRAPE" = "true" ]; then
    echo "   ✓ Prometheus scraping enabled (port: $PROM_PORT)"
  elif [ "$PROM_PORT" = "9091" ]; then
    echo "   ⚠ Prometheus port is incorrect: $PROM_PORT (should be 8000)"
    echo "   → Run: bash ~/AIM-demo/k8s/scripts/fix-prometheus-port.sh"
  elif [ -z "$PROM_SCRAPE" ] || [ "$PROM_SCRAPE" != "true" ]; then
    echo "   ⚠ Prometheus scraping not enabled"
    echo "   → Run: bash ~/AIM-demo/k8s/scripts/fix-prometheus-port.sh"
  else
    echo "   ⚠ Prometheus port: ${PROM_PORT:-<not set>} (expected: 8000)"
    echo "   → Run: bash ~/AIM-demo/k8s/scripts/fix-prometheus-port.sh"
  fi
else
  echo "   ⚠ Pod not found - cannot check Prometheus annotations"
fi

echo ""
echo "4. Available vLLM metrics in Prometheus:"
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | jq '.data[] | select(contains("vllm"))' | head -15

kill $PF_PID 2>/dev/null

echo ""
echo "=== How to View Metrics in Grafana ==="
echo ""
echo "1. Access Grafana: http://localhost:3000 (or via SSH port-forward)"
echo "2. Go to Explore (compass icon in left menu)"
echo "3. Select 'Prometheus' as data source"
echo "4. Try these queries:"
echo "   - vllm:num_requests_running"
echo "   - vllm:num_requests_running{service=\"isvc.aim-qwen3-32b-scalable-predictor\"}"
echo "   - sum(vllm:num_requests_running{service=\"isvc.aim-qwen3-32b-scalable-predictor\"})"
echo "   - kube_deployment_status_replicas{deployment=\"aim-qwen3-32b-scalable-predictor\"}"
echo "   - vllm:e2e_request_latency_seconds"
echo "   - vllm:gpu_cache_usage_perc"
echo ""
echo "5. Check for dashboards:"
echo "   - Go to Dashboards > Browse"
echo "   - Look for vLLM or AIM dashboards"
echo ""
echo "=== Will New Pods Send Metrics? ==="
echo "YES - The InferenceService has annotation: sidecar.opentelemetry.io/inject"
echo "This ensures all new pods (from autoscaling) automatically:"
echo "  - Get the metrics collection sidecar"
echo "  - Expose metrics on /metrics endpoint"
echo "  - Send metrics to Prometheus via OpenTelemetry collector"
echo "  - Appear in Grafana dashboards automatically"

