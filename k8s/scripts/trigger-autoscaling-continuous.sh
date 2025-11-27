#!/bin/bash
# Script to trigger autoscaling by sending continuous requests (keeps requests active during Prometheus scrape)

echo "=== Triggering Autoscaling with Continuous Load ==="
echo ""
echo "Strategy: Send requests continuously for 90+ seconds"
echo "This ensures requests are active when Prometheus scrapes (every 60s)"
echo ""

# Check if port-forward is running
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
  echo "ERROR: Port 8080 is not accessible."
  echo "Please start port-forward in another terminal:"
  echo "  kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80"
  echo ""
  exit 1
fi

# Start Prometheus port-forward
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

BEFORE=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running)' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "Initial metric value: $BEFORE"
echo ""

echo "Sending requests continuously for 90 seconds..."
echo "This keeps requests active during the Prometheus scrape window"
echo ""

# Send requests continuously in background
(
  for i in {1..100}; do
    curl -X POST http://localhost:8080/v1/chat/completions \
         -H "Content-Type: application/json" \
         -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Write a 300-word explanation of machine learning. Request $i.\"}], \"stream\": false}" \
         --max-time 60 > /dev/null 2>&1 &
    sleep 2  # Send a new request every 2 seconds
    if [ $i -eq 45 ]; then
      break  # Stop after 90 seconds (45 * 2)
    fi
  done
) &
REQUESTS_PID=$!

echo "Monitoring metric value (checking every 10 seconds)..."
for i in {1..10}; do
  sleep 10
  ELAPSED=$((i * 10))
  # Use sum without service filter (works better)
  METRIC=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running)' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
  if [ "$METRIC" = "null" ] || [ -z "$METRIC" ]; then
    METRIC="0"
  fi
  echo "  After ${ELAPSED}s: Metric = $METRIC (Target: 1)"
  
  if [ "$METRIC" != "0" ] && [ "$METRIC" != "null" ]; then
    echo ""
    echo "  ✓✓✓ METRIC IS ACTIVE! Value: $METRIC"
    if [ $(echo "$METRIC > 1" | bc -l 2>/dev/null || echo "0") = "1" ]; then
      echo "  ✓✓ Metric exceeds target (1) - autoscaling should trigger!"
    fi
  fi
done

echo ""
echo "Stopping request generation..."
kill $REQUESTS_PID 2>/dev/null
wait $REQUESTS_PID 2>/dev/null

echo "Waiting for remaining requests to complete..."
sleep 10

AFTER=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running)' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "Final metric value: $AFTER"

kill $PF_PID 2>/dev/null

echo ""
echo "=== Summary ==="
echo "Continuous load strategy:"
echo "  - Sends requests every 2 seconds for 90 seconds"
echo "  - Keeps requests active during Prometheus scrape window"
echo "  - Should show metric > 1 after 60+ seconds"
echo ""
echo "To monitor autoscaling:"
echo "  kubectl get deployment aim-qwen3-32b-scalable-predictor -w"

