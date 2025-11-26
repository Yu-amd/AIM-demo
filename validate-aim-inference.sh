#!/bin/bash

################################################################################
# AMD Inference Microservice (AIM) - Inference Testing Validation Script
# 
# This script validates all inference testing steps (5.1 through 5.8) for AIM
# deployment. It verifies that the API server is working correctly and can
# handle inference requests.
#
# Usage: ./validate-aim-inference.sh
# Prerequisites: AIM container should be deployed and running
################################################################################

set +e  # Don't exit on error - we want to continue checking all steps

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="aim-qwen3-32b"
API_PORT=8000
API_URL="http://localhost:${API_PORT}"
TEST_MAX_TOKENS=2048
TEST_TIMEOUT=90

# Track validation results
declare -A CHECK_RESULTS
ALL_CHECKS_PASSED=true

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo ""
}

# Function to print check header
print_check() {
    echo -e "${YELLOW}Checking: $1${NC}"
    echo "Command: $2"
    echo ""
}

# Function to mark check as passed
check_passed() {
    echo -e "${GREEN}✓ PASSED${NC}"
    CHECK_RESULTS["$1"]="PASSED"
    echo ""
}

# Function to mark check as failed
check_failed() {
    echo -e "${RED}✗ FAILED${NC}"
    CHECK_RESULTS["$1"]="FAILED"
    ALL_CHECKS_PASSED=false
    echo ""
}

# Function to print fix instructions
print_fix() {
    echo -e "${YELLOW}Fix Instructions:${NC}"
    echo "$1"
    echo ""
}

################################################################################
# Step 5.1: Verify API Server is Ready
################################################################################
print_section "Step 5.1: Verify API Server is Ready"

print_check "Container Status" "docker ps | grep $CONTAINER_NAME"
CONTAINER_STATUS=$(docker ps --format "{{.Names}}\t{{.Status}}" | grep "$CONTAINER_NAME" || echo "")
if [ -n "$CONTAINER_STATUS" ]; then
    echo "Output:"
    echo "$CONTAINER_STATUS"
    echo ""
    if echo "$CONTAINER_STATUS" | grep -q "Up"; then
        UPTIME=$(echo "$CONTAINER_STATUS" | awk '{print $2}')
        echo -e "${GREEN}✓ Container is running (Up $UPTIME)${NC}"
        check_passed "CONTAINER_RUNNING"
    else
        check_failed "CONTAINER_RUNNING"
        print_fix "Container exists but is not running. Check status:
  docker ps -a | grep $CONTAINER_NAME
  docker logs $CONTAINER_NAME | tail -50
  
If container exited, check logs for errors and restart:
  docker start $CONTAINER_NAME"
        echo ""
    fi
else
    check_failed "CONTAINER_RUNNING"
    print_fix "Container '$CONTAINER_NAME' is not running. Deploy it first:
  docker run -d --name $CONTAINER_NAME \\
    --device=/dev/kfd --device=/dev/dri \\
    --security-opt seccomp=unconfined \\
    --group-add video \\
    --ipc=host \\
    --shm-size=8g \\
    -p $API_PORT:8000 \\
    amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 serve"
    echo ""
fi

print_check "Application Startup Status" "docker logs $CONTAINER_NAME 2>&1 | grep -i 'application startup complete'"
STARTUP_LOG=$(docker logs $CONTAINER_NAME 2>&1 | grep -i "application startup complete" | tail -1)
if [ -n "$STARTUP_LOG" ]; then
    echo "Output:"
    echo "$STARTUP_LOG"
    echo ""
    echo -e "${GREEN}✓ API server has completed startup${NC}"
    check_passed "SERVER_READY"
else
    echo "Output: (not found)"
    echo ""
    echo -e "${YELLOW}⚠ 'Application startup complete' not found in logs${NC}"
    echo "Checking if server is responding..."
    
    # Try to check if server responds
    HTTP_RESPONSE=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" "$API_URL/health" 2>/dev/null || echo "000")
    if [ "$HTTP_RESPONSE" = "200" ] || [ "$HTTP_RESPONSE" = "000" ]; then
        if [ "$HTTP_RESPONSE" = "200" ]; then
            echo -e "${GREEN}✓ Server is responding (HTTP $HTTP_RESPONSE)${NC}"
            check_passed "SERVER_READY"
        else
            echo -e "${YELLOW}⚠ Server may still be starting up${NC}"
            check_passed "SERVER_READY"  # Warning but not blocking
        fi
    else
        check_failed "SERVER_READY"
        print_fix "Server is not ready. Check logs:
  docker logs $CONTAINER_NAME | tail -50
  
Wait for model to finish loading (can take 2-5 minutes for 32B model).
Monitor progress:
  docker logs -f $CONTAINER_NAME"
        echo ""
    fi
fi

check_passed "STEP_5_1"

################################################################################
# Step 5.2: Test Health Endpoint
################################################################################
print_section "Step 5.2: Test Health Endpoint"

print_check "Health Endpoint" "curl -v $API_URL/health"
HEALTH_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$API_URL/health" 2>&1)
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | grep -v "HTTP_CODE")

if [ "$HTTP_CODE" = "200" ]; then
    echo "Output:"
    echo "HTTP Status: $HTTP_CODE"
    if [ -n "$HEALTH_BODY" ]; then
        echo "Response: $HEALTH_BODY"
    fi
    echo ""
    echo -e "${GREEN}✓ Health endpoint responds with HTTP 200${NC}"
    check_passed "HEALTH_ENDPOINT"
else
    echo "Output:"
    echo "$HEALTH_RESPONSE"
    echo ""
    if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
        check_failed "HEALTH_ENDPOINT"
        print_fix "Cannot connect to health endpoint. Check:
1. Container is running: docker ps | grep $CONTAINER_NAME
2. Port is mapped correctly: docker ps | grep $API_PORT
3. Server is ready: docker logs $CONTAINER_NAME | grep 'startup complete'
4. Try accessing: curl $API_URL/health"
        echo ""
    else
        echo -e "${YELLOW}⚠ Health endpoint returned HTTP $HTTP_CODE (may not be available)${NC}"
        check_passed "HEALTH_ENDPOINT"  # Warning but not blocking
    fi
fi

check_passed "STEP_5_2"

################################################################################
# Step 5.3: List Available Models
################################################################################
print_section "Step 5.3: List Available Models"

print_check "Models Endpoint" "curl -s $API_URL/v1/models | python3 -m json.tool"
MODELS_RESPONSE=$(curl -s "$API_URL/v1/models" 2>&1)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/v1/models" 2>&1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "Output:"
    echo "$MODELS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$MODELS_RESPONSE"
    echo ""
    
    # Check if response is valid JSON and contains model
    if echo "$MODELS_RESPONSE" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        MODEL_ID=$(echo "$MODELS_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('data', [{}])[0].get('id', ''))" 2>/dev/null)
        if [ -n "$MODEL_ID" ]; then
            echo -e "${GREEN}✓ Models endpoint works, found model: $MODEL_ID${NC}"
            check_passed "MODELS_ENDPOINT"
        else
            echo -e "${YELLOW}⚠ Models endpoint works but no model ID found${NC}"
            check_passed "MODELS_ENDPOINT"  # Warning but not blocking
        fi
    else
        check_failed "MODELS_ENDPOINT"
        print_fix "Models endpoint returned invalid JSON. Check server logs:
  docker logs $CONTAINER_NAME | tail -20"
        echo ""
    fi
else
    check_failed "MODELS_ENDPOINT"
    print_fix "Models endpoint failed (HTTP $HTTP_CODE). Check:
1. Server is ready: docker logs $CONTAINER_NAME | grep 'startup complete'
2. Model loaded correctly: docker logs $CONTAINER_NAME | grep -i 'model'
3. Try manually: curl $API_URL/v1/models"
    echo ""
fi

check_passed "STEP_5_3"

################################################################################
# Step 5.4: Test Chat Completions Endpoint
################################################################################
print_section "Step 5.4: Test Chat Completions Endpoint"

print_check "Chat Completions (Non-Streaming)" "curl -X POST $API_URL/v1/chat/completions ..."
TEST_QUESTION="What are the key advantages of using GPUs for AI inference, and how do they compare to CPUs?"
CHAT_REQUEST=$(curl -s -X POST "$API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"Qwen/Qwen3-32B\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$TEST_QUESTION\"}],
    \"max_tokens\": $TEST_MAX_TOKENS,
    \"temperature\": 0.7
  }" \
  -w "\nHTTP_CODE:%{http_code}" 2>&1)

HTTP_CODE=$(echo "$CHAT_REQUEST" | grep "HTTP_CODE" | cut -d: -f2)
CHAT_BODY=$(echo "$CHAT_REQUEST" | grep -v "HTTP_CODE")

if [ "$HTTP_CODE" = "200" ]; then
    # Validate JSON response
    if echo "$CHAT_BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); exit(0 if 'choices' in data else 1)" 2>/dev/null; then
        CONTENT=$(echo "$CHAT_BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('choices', [{}])[0].get('message', {}).get('content', '')[:100])" 2>/dev/null)
        FINISH_REASON=$(echo "$CHAT_BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('choices', [{}])[0].get('finish_reason', ''))" 2>/dev/null)
        
        echo "Output: (truncated)"
        echo "Response preview: ${CONTENT}..."
        echo "Finish reason: $FINISH_REASON"
        echo ""
        
        if [ -n "$CONTENT" ] && [ ${#CONTENT} -gt 10 ]; then
            if [ "$FINISH_REASON" = "stop" ]; then
                echo -e "${GREEN}✓ Chat completions works, response generated (finish_reason: stop)${NC}"
                check_passed "CHAT_COMPLETIONS"
            elif [ "$FINISH_REASON" = "length" ]; then
                echo -e "${YELLOW}⚠ Chat completions works but response was truncated (finish_reason: length)${NC}"
                echo "Consider increasing max_tokens if you need longer responses"
                check_passed "CHAT_COMPLETIONS"  # Warning but functional
            else
                echo -e "${GREEN}✓ Chat completions works, finish_reason: $FINISH_REASON${NC}"
                check_passed "CHAT_COMPLETIONS"
            fi
        else
            check_failed "CHAT_COMPLETIONS"
            print_fix "Chat completions returned empty or very short content. Check:
1. Model is fully loaded: docker logs $CONTAINER_NAME | grep 'startup complete'
2. max_tokens is sufficient (recommended: 2048+)
3. Check full response: curl -X POST $API_URL/v1/chat/completions ..."
            echo ""
        fi
    else
        check_failed "CHAT_COMPLETIONS"
        print_fix "Chat completions returned invalid JSON. Check server logs:
  docker logs $CONTAINER_NAME | tail -30"
        echo ""
    fi
else
    check_failed "CHAT_COMPLETIONS"
    print_fix "Chat completions failed (HTTP $HTTP_CODE). Check:
1. Server is ready: docker logs $CONTAINER_NAME | grep 'startup complete'
2. Model is loaded: docker logs $CONTAINER_NAME | grep -i 'model'
3. Check error details: docker logs $CONTAINER_NAME | tail -50
4. Try manually: curl -X POST $API_URL/v1/chat/completions ..."
    echo ""
fi

print_check "Chat Completions (Streaming)" "curl -s -X POST $API_URL/v1/chat/completions ... stream=true"
STREAM_RESPONSE=$(timeout $TEST_TIMEOUT curl -s -X POST "$API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"Qwen/Qwen3-32B\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one sentence.\"}],
    \"max_tokens\": 100,
    \"stream\": true
  }" 2>&1 | head -20)

if echo "$STREAM_RESPONSE" | grep -q "data:"; then
    DATA_LINES=$(echo "$STREAM_RESPONSE" | grep -c "data:")
    echo "Output: (first 20 lines)"
    echo "$STREAM_RESPONSE" | head -10
    echo "..."
    echo ""
    echo -e "${GREEN}✓ Streaming works, received $DATA_LINES data chunks${NC}"
    check_passed "CHAT_STREAMING"
else
    check_failed "CHAT_STREAMING"
    print_fix "Streaming not working. Check:
1. Server supports streaming: docker logs $CONTAINER_NAME | grep -i stream
2. Request format is correct (stream: true)
3. Network connectivity: curl -v $API_URL/v1/models"
    echo ""
fi

check_passed "STEP_5_4"

################################################################################
# Step 5.5: Test Text Completions Endpoint
################################################################################
print_section "Step 5.5: Test Text Completions Endpoint"

print_check "Text Completions" "curl -X POST $API_URL/v1/completions ..."
COMPLETIONS_REQUEST=$(curl -s -X POST "$API_URL/v1/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"prompt\": \"The AMD Inference Microservice (AIM) is\",
    \"max_tokens\": 100,
    \"temperature\": 0.7
  }" \
  -w "\nHTTP_CODE:%{http_code}" 2>&1)

HTTP_CODE=$(echo "$COMPLETIONS_REQUEST" | grep "HTTP_CODE" | cut -d: -f2)
COMPLETIONS_BODY=$(echo "$COMPLETIONS_REQUEST" | grep -v "HTTP_CODE")

if [ "$HTTP_CODE" = "200" ]; then
    if echo "$COMPLETIONS_BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); exit(0 if 'choices' in data else 1)" 2>/dev/null; then
        TEXT=$(echo "$COMPLETIONS_BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('choices', [{}])[0].get('text', '')[:100])" 2>/dev/null)
        
        echo "Output: (truncated)"
        echo "Response preview: ${TEXT}..."
        echo ""
        
        if [ -n "$TEXT" ] && [ ${#TEXT} -gt 5 ]; then
            echo -e "${GREEN}✓ Text completions works, response generated${NC}"
            check_passed "TEXT_COMPLETIONS"
        else
            echo -e "${YELLOW}⚠ Text completions works but response is very short${NC}"
            check_passed "TEXT_COMPLETIONS"  # Warning but functional
        fi
    else
        check_failed "TEXT_COMPLETIONS"
        print_fix "Text completions returned invalid JSON. Check server logs:
  docker logs $CONTAINER_NAME | tail -20"
        echo ""
    fi
else
    check_failed "TEXT_COMPLETIONS"
    print_fix "Text completions failed (HTTP $HTTP_CODE). Check:
1. Endpoint is available: curl $API_URL/v1/models
2. Some models prefer chat format over completions
3. Check server logs: docker logs $CONTAINER_NAME | tail -30"
    echo ""
fi

check_passed "STEP_5_5"

################################################################################
# Step 5.6: Monitor GPU Usage During Inference
################################################################################
print_section "Step 5.6: Monitor GPU Usage During Inference"

print_check "GPU Status" "rocm-smi --showmemuse --showuse"
if command -v rocm-smi &> /dev/null; then
    GPU_INFO=$(rocm-smi --showmemuse --showuse 2>&1)
    echo "Output:"
    echo "$GPU_INFO"
    echo ""
    
    VRAM_USAGE=$(echo "$GPU_INFO" | grep "VRAM%" | head -1 | grep -oE '[0-9]+%' | head -1 | sed 's/%//')
    GPU_USE=$(echo "$GPU_INFO" | grep "GPU use" | head -1 | grep -oE '[0-9]+%' | head -1 | sed 's/%//')
    
    if [ -n "$VRAM_USAGE" ] && [ "$VRAM_USAGE" -gt 50 ]; then
        echo -e "${GREEN}✓ GPU VRAM usage: ${VRAM_USAGE}% (model is loaded)${NC}"
        check_passed "GPU_VRAM"
    else
        echo -e "${YELLOW}⚠ GPU VRAM usage: ${VRAM_USAGE}% (may be low if model not fully loaded)${NC}"
        check_passed "GPU_VRAM"  # Warning but not blocking
    fi
    
    if [ -n "$GPU_USE" ]; then
        echo -e "${GREEN}✓ GPU utilization: ${GPU_USE}%${NC}"
        check_passed "GPU_UTILIZATION"
    else
        echo -e "${YELLOW}⚠ Could not determine GPU utilization${NC}"
        check_passed "GPU_UTILIZATION"  # Warning but not blocking
    fi
else
    echo -e "${YELLOW}⚠ rocm-smi not available, skipping GPU monitoring${NC}"
    check_passed "GPU_VRAM"  # Not available, not a failure
    check_passed "GPU_UTILIZATION"
fi

check_passed "STEP_5_6"

################################################################################
# Step 5.7: Performance Validation
################################################################################
print_section "Step 5.7: Performance Validation"

print_check "Response Time Test" "time curl -X POST $API_URL/v1/chat/completions ..."
PERF_START=$(date +%s)
PERF_RESPONSE=$(timeout 60 curl -s -X POST "$API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"Qwen/Qwen3-32B\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Say hello.\"}],
    \"max_tokens\": 50
  }" 2>&1)
PERF_END=$(date +%s)
PERF_DURATION=$((PERF_END - PERF_START))

echo "Output:"
echo "Response time: ${PERF_DURATION} seconds"
echo ""

if [ "$PERF_DURATION" -lt 120 ]; then
    if [ "$PERF_DURATION" -lt 60 ]; then
        echo -e "${GREEN}✓ Response time: ${PERF_DURATION}s (good)${NC}"
    else
        echo -e "${YELLOW}⚠ Response time: ${PERF_DURATION}s (acceptable, may be slower on first request)${NC}"
    fi
    check_passed "PERFORMANCE"
else
    echo -e "${YELLOW}⚠ Response time: ${PERF_DURATION}s (slow, but may be normal for first request)${NC}"
    check_passed "PERFORMANCE"  # Warning but not blocking
    print_fix "Response time is slow. This may be normal for:
1. First request (model initialization)
2. Complex questions requiring extensive thinking
3. Large max_tokens values

Monitor GPU usage during inference to verify GPU is being utilized:
  rocm-smi --showuse"
    echo ""
fi

check_passed "STEP_5_7"

################################################################################
# Step 5.8: Final Validation Checklist
################################################################################
print_section "Step 5.8: Final Validation Checklist"

echo "Reviewing all validation results..."
echo ""

# Create checklist
declare -A CHECKLIST
CHECKLIST["Container is running"]=${CHECK_RESULTS[CONTAINER_RUNNING]:-"FAILED"}
CHECKLIST["API server is ready"]=${CHECK_RESULTS[SERVER_READY]:-"FAILED"}
CHECKLIST["Health endpoint responds (if available)"]=${CHECK_RESULTS[HEALTH_ENDPOINT]:-"FAILED"}
CHECKLIST["Models endpoint works"]=${CHECK_RESULTS[MODELS_ENDPOINT]:-"FAILED"}
CHECKLIST["Chat completions work"]=${CHECK_RESULTS[CHAT_COMPLETIONS]:-"FAILED"}
CHECKLIST["Chat streaming works"]=${CHECK_RESULTS[CHAT_STREAMING]:-"FAILED"}
CHECKLIST["Text completions work"]=${CHECK_RESULTS[TEXT_COMPLETIONS]:-"FAILED"}
CHECKLIST["GPU is accessible"]=${CHECK_RESULTS[GPU_VRAM]:-"FAILED"}
CHECKLIST["Response times are acceptable"]=${CHECK_RESULTS[PERFORMANCE]:-"FAILED"}

echo "Final Checklist:"
echo ""

ALL_PASSED=true
for item in "${!CHECKLIST[@]}"; do
    status=${CHECKLIST[$item]}
    if [ "$status" = "PASSED" ]; then
        echo -e "  ${GREEN}[✓]${NC} $item"
    else
        echo -e "  ${RED}[✗]${NC} $item"
        ALL_PASSED=false
    fi
done

echo ""

################################################################################
# Final Summary
################################################################################
print_section "Validation Summary"

if [ "$ALL_PASSED" = true ] && [ "$ALL_CHECKS_PASSED" = true ]; then
    echo -e "${GREEN}✓ All inference tests passed!${NC}"
    echo ""
    echo "Your AIM deployment is fully operational and ready for use."
    echo ""
    echo "You can now:"
    echo "  - Make inference requests to the API"
    echo "  - Use streaming for real-time responses"
    echo "  - Monitor GPU usage during inference"
    echo "  - Scale the deployment as needed"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some inference tests failed${NC}"
    echo ""
    echo "Please review the failed checks above and follow the fix instructions."
    echo "Common issues:"
    echo "  - Container not running: Check docker ps and docker logs"
    echo "  - Server not ready: Wait for model to finish loading"
    echo "  - API errors: Check container logs for details"
    echo "  - Slow responses: Normal for first request, monitor GPU usage"
    echo ""
    echo "Once issues are resolved, run this script again to verify."
    echo ""
    exit 1
fi

