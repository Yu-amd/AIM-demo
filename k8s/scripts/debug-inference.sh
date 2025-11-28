#!/bin/bash
# debug-inference.sh
# Debug script to see raw API response

PORT="${1:-8080}"
BASE_URL="http://localhost:${PORT}"

echo "Testing API at $BASE_URL"
echo "Raw response (first 20 lines):"
echo "---"

curl -X POST "${BASE_URL}/v1/chat/completions" \
     -H "Content-Type: application/json" \
     -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}' \
     --no-buffer -N -s 2>&1 | head -20

echo ""
echo "---"
echo "Done"

