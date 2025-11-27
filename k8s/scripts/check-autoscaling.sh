#!/bin/bash
# Script to check autoscaling status and metrics

echo "=== Autoscaling Status Check ==="
echo ""

echo "1. Deployment Status:"
kubectl get deployment aim-qwen3-32b-scalable-predictor
echo ""

echo "2. ScaledObject Status:"
kubectl get scaledobject aim-qwen3-32b-scalable-predictor -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}{"\n"}{.status.conditions[*].reason}{"\n"}'
echo ""

echo "3. HPA Status (created by KEDA):"
kubectl get hpa keda-hpa-aim-qwen3-32b-scalable-predictor
echo ""

echo "4. Current Metric Value (vllm:num_requests_running):"
# Port forward Prometheus
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

METRIC_VALUE=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service="isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "   Current: $METRIC_VALUE (Target: 1)"
echo "   Status: $([ "$METRIC_VALUE" -gt "0" ] && echo "ACTIVE - Will scale up" || echo "INACTIVE - No requests running")"

kill $PF_PID 2>/dev/null
echo ""

echo "5. Pod Status:"
kubectl get pods -l serving.kserve.io/inferenceservice=aim-qwen3-32b-scalable -o wide
echo ""

echo "=== Summary ==="
echo "To trigger autoscaling, send concurrent requests to port 8080:"
echo "  for i in {1..5}; do curl -X POST http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\": [{\"role\": \"user\", \"content\": \"Hello $i\"}], \"stream\": true}' --no-buffer > /dev/null 2>&1 & done"

