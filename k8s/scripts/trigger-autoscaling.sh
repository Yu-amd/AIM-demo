#!/bin/bash
# Script to trigger autoscaling by sending concurrent requests

echo "=== Triggering Autoscaling ==="
echo ""

# Check if port-forward is running
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
  echo "ERROR: Port 8080 is not accessible."
  echo "Please start port-forward in another terminal:"
  echo "  kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80"
  echo ""
  exit 1
fi

# Get number of requests (default 5)
NUM_REQUESTS=${1:-5}
echo "Sending $NUM_REQUESTS concurrent NON-STREAMING requests..."
echo "(Non-streaming requests take longer and show up better in metrics)"
echo ""

# Start Prometheus port-forward for monitoring
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# Check initial metric
BEFORE=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "Initial metric value: $BEFORE"
echo ""

# Send concurrent requests
echo "Sending requests..."
for i in $(seq 1 $NUM_REQUESTS); do
  curl -X POST http://localhost:8080/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Write a detailed 300-word explanation of how machine learning algorithms work. Include specific examples and use cases. This is request number $i.\"}], \"stream\": false}" \
       --max-time 60 > /dev/null 2>&1 &
  echo "  ✓ Sent request $i"
  sleep 0.5  # Small delay between requests
done

echo ""
echo "Monitoring metric value (checking every 2 seconds)..."
echo "Target: metric > 1 to trigger autoscaling"
echo ""

MAX_CHECKS=15
for i in $(seq 1 $MAX_CHECKS); do
  sleep 2
  METRIC=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
  
  if [ "$METRIC" = "null" ] || [ -z "$METRIC" ]; then
    METRIC="0"
  fi
  
  echo "  Check $i: Metric = $METRIC (Target: 1)"
  
  if [ "$METRIC" != "0" ] && [ "$METRIC" != "null" ]; then
    echo ""
    echo "  ✓✓✓ METRIC IS ACTIVE! Value: $METRIC"
    echo "  ✓ Autoscaling should trigger when metric > 1"
    if (( $(echo "$METRIC > 1" | bc -l) )); then
      echo "  ✓✓ Metric exceeds target (1) - autoscaling should scale up!"
    fi
    break
  fi
done

echo ""
echo "Waiting for requests to complete..."
wait

echo ""
echo "Final metric value:"
AFTER=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "  Metric: $AFTER"

kill $PF_PID 2>/dev/null

echo ""
echo "=== Summary ==="
echo "To see autoscaling in action, watch the deployment in another terminal:"
echo "  kubectl get deployment aim-qwen3-32b-scalable-predictor -w"
echo ""
echo "Or check HPA status:"
echo "  kubectl get hpa keda-hpa-aim-qwen3-32b-scalable-predictor"
echo ""
echo "The metric should show > 1 when multiple requests are being processed simultaneously."

