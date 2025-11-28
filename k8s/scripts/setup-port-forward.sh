#!/bin/bash
# setup-port-forward.sh
# Helper script to set up port forwarding for inference services

set -e

INFERENCE_SERVICE="${1:-aim-qwen3-32b}"
LOCAL_PORT="${2:-8000}"
REMOTE_PORT="${3:-80}"

echo "=== Port Forwarding Setup ==="
echo ""

SVC_NAME="${INFERENCE_SERVICE}-predictor"

# Check if service exists
if ! kubectl get svc $SVC_NAME > /dev/null 2>&1; then
    echo "ERROR: Service '$SVC_NAME' not found"
    echo ""
    echo "Available services:"
    kubectl get svc | grep -E "NAME|predictor" || echo "  None found"
    exit 1
fi

echo "Service: $SVC_NAME"
echo "Forwarding: localhost:${LOCAL_PORT} -> ${SVC_NAME}:${REMOTE_PORT}"
echo ""

# Check if port is already in use
if lsof -Pi :${LOCAL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠ Port ${LOCAL_PORT} is already in use"
    echo ""
    read -p "Do you want to kill the existing process and continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kill $(lsof -t -i:${LOCAL_PORT}) 2>/dev/null || true
        sleep 1
    else
        echo "Please choose a different port or stop the existing process"
        exit 1
    fi
fi

echo "Starting port forwarding..."
echo "Press Ctrl+C to stop"
echo ""

# For remote access, provide SSH instructions
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo "Note: You're connected via SSH."
    echo "To access from your local machine, set up SSH port forwarding first:"
    echo "  ssh -L ${LOCAL_PORT}:localhost:${LOCAL_PORT} user@remote-host"
    echo ""
fi

kubectl port-forward service/$SVC_NAME ${LOCAL_PORT}:${REMOTE_PORT}

