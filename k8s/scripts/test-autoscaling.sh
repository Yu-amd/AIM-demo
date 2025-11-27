#!/bin/bash
# Script to test autoscaling by sending requests and monitoring metrics

echo "=== Testing Autoscaling ==="
echo ""

# Check if port-forward is needed
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
  echo "ERROR: Port 8080 is not accessible."
  echo "Please start port-forward in another terminal:"
  echo "  kubectl port-forward service/aim-qwen3-32b-scalable-predictor 8080:80"
  echo ""
  exit 1
fi

echo "1. Checking current metric value..."
kubectl port-forward -n otel-lgtm-stack svc/lgtm-stack 9090:9090 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

BEFORE=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "   Current metric value: $BEFORE"
echo ""

echo "2. Sending 5 concurrent NON-STREAMING requests (these take longer)..."
for i in {1..5}; do
  curl -X POST http://localhost:8080/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Write a detailed explanation of how neural networks work (request $i). Make it at least 200 words.\"}], \"stream\": false}" \
       --max-time 30 > /dev/null 2>&1 &
  echo "   Sent request $i"
done

echo ""
echo "3. Monitoring metric value (checking every 2 seconds)..."
for i in {1..10}; do
  sleep 2
  METRIC=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
  echo "   Check $i: Metric = $METRIC (Target: 1)"
  if [ "$METRIC" != "0" ] && [ "$METRIC" != "null" ]; then
    echo "   ✓ Metric is active! Value: $METRIC"
    break
  fi
done

echo ""
echo "4. Waiting for requests to complete..."
wait

echo ""
echo "5. Final metric value:"
AFTER=$(curl -s 'http://localhost:9090/api/v1/query?query=sum(vllm:num_requests_running{service%3D"isvc.aim-qwen3-32b-scalable-predictor"})' 2>/dev/null | jq -r '.data.result[0].value[1] // "0"')
echo "   Metric value: $AFTER"

kill $PF_PID 2>/dev/null

echo ""
echo "=== Summary ==="
if [ "$BEFORE" = "0" ] && [ "$AFTER" = "0" ]; then
  echo "⚠ Metrics stayed at 0. Possible issues:"
  echo "   - Requests completed too quickly"
  echo "   - Metrics not being scraped by Prometheus"
  echo "   - Check Prometheus scrape configuration"
  echo "   - Try longer requests or check pod logs"
else
  echo "✓ Metrics are working! Autoscaling should trigger when metric > 1"
fi

