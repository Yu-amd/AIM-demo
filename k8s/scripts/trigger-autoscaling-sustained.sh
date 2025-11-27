#!/bin/bash
# Script to trigger autoscaling with sustained load (accounts for Prometheus 60s scrape interval)

echo "=== Triggering Autoscaling with Sustained Load ==="
echo ""
echo "NOTE: Prometheus scrape interval is 60 seconds"
echo "We need to send requests that last longer than 60 seconds for metrics to update"
echo ""

# Check if port-forward is running
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
  echo "ERROR: Port 8080 is not accessible."
  echo "Please start port-forward in another terminal:"
  echo "  kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80"
  echo ""
  exit 1
fi

NUM_REQUESTS=${1:-20}
echo "Sending $NUM_REQUESTS concurrent requests..."
echo "NOTE: Need many concurrent requests (20+) to ensure some are active when Prometheus scrapes (60s interval)"
echo ""

# Start Prometheus port-forward
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

BEFORE=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "Initial metric value: $BEFORE"
echo ""

echo "Sending $NUM_REQUESTS concurrent requests..."
echo "NOTE: Requests typically complete in 40-50 seconds, but Prometheus scrapes every 60s"
echo "For better results, use the continuous script: bash ~/AIM-demo/k8s/scripts/trigger-autoscaling-continuous.sh"
echo ""
for i in $(seq 1 $NUM_REQUESTS); do
  curl -X POST http://localhost:8080/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Write a detailed 500-word explanation of machine learning algorithms, neural networks, and deep learning. Include examples and use cases. Request $i.\"}], \"stream\": false}" \
       --max-time 120 > /dev/null 2>&1 &
  echo "  ✓ Sent request $i"
  sleep 0.2  # Small delay to stagger requests slightly
done

echo ""
echo "Waiting 65 seconds for Prometheus to scrape (scrape interval is 60s)..."
echo "Monitoring metric value:"
for i in {1..13}; do
  sleep 5
  METRIC=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
  if [ "$METRIC" = "null" ] || [ -z "$METRIC" ]; then
    METRIC="0"
  fi
  ELAPSED=$((i * 5))
  echo "  After ${ELAPSED}s: Metric = $METRIC (Target: 1)"
  
  if [ "$METRIC" != "0" ] && [ "$METRIC" != "null" ]; then
    echo ""
    echo "  ✓✓✓ METRIC IS ACTIVE! Value: $METRIC"
    if [ $(echo "$METRIC > 1" | bc -l 2>/dev/null || echo "0") = "1" ]; then
      echo "  ✓✓ Metric exceeds target (1) - autoscaling should trigger!"
      echo ""
      echo "Watch deployment scale:"
      echo "  kubectl get deployment aim-qwen3-32b-scalable-predictor -w"
    fi
  fi
done

echo ""
echo "Waiting for requests to complete (this may take 2-3 minutes)..."
wait

AFTER=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "Final metric value: $AFTER"

kill $PF_PID 2>/dev/null

echo ""
echo "=== Summary ==="
echo "Due to Prometheus 60-second scrape interval:"
echo "  - Metrics only update every 60 seconds"
echo "  - Requests must last longer than 60 seconds to be visible"
echo "  - Use very long prompts (1000+ words) for testing"
echo ""
echo "To monitor autoscaling:"
echo "  kubectl get deployment aim-qwen3-32b-scalable-predictor -w"
echo "  kubectl get hpa keda-hpa-aim-qwen3-32b-scalable-predictor -w"

