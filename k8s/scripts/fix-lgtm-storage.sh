#!/bin/bash
# Script to automatically diagnose and fix LGTM/Grafana pod storage issues
# This script checks for Pending pods due to unbound PVCs and fixes storage class issues

set -e

NAMESPACE="otel-lgtm-stack"
LOCAL_PATH_PROVISIONER_URL="https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"

echo "=== Checking LGTM/Grafana pod status ==="
LGTM_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)

if [ -z "$LGTM_POD" ]; then
  echo "No LGTM/Grafana pod found. Checking if deployment exists..."
  LGTM_DEPLOYMENT=$(kubectl get deployment -n $NAMESPACE 2>/dev/null | grep lgtm | awk '{print $1}' | head -1)
  
  if [ -z "$LGTM_DEPLOYMENT" ]; then
    echo "LGTM deployment is missing. Attempting to recreate it..."
    
    # Check if observability stack YAML exists
    LGTM_YAML_DIR="$HOME/aim-deploy/kserve/kserve-install/post-helm/base/otel-lgtm-stack-standalone"
    if [ ! -d "$LGTM_YAML_DIR" ]; then
      echo "Error: LGTM stack YAML directory not found at $LGTM_YAML_DIR"
      echo "Please ensure the observability stack is installed using: bash ./install-deps.sh --enable=full"
      exit 1
    fi
    
    # Check if local-path storage class exists
    LOCAL_PATH_EXISTS=$(kubectl get storageclass local-path 2>/dev/null | grep -c local-path || echo "0")
    if [ "$LOCAL_PATH_EXISTS" = "0" ]; then
      echo "local-path storage class not found. Installing it first..."
      kubectl apply -f $LOCAL_PATH_PROVISIONER_URL
      kubectl wait --for=condition=ready pod -n local-path-storage -l app=local-path-provisioner --timeout=60s 2>/dev/null || true
      kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true
    fi
    
    # Recreate deployment with local-path storage class
    echo "Recreating LGTM deployment with local-path storage class..."
    cd "$LGTM_YAML_DIR"
    sed 's/storageClassName: default/storageClassName: local-path/g' otel-lgtm.yaml | kubectl apply -f - 2>/dev/null || {
      echo "Failed to apply LGTM YAML. Trying with kustomize..."
      kubectl apply -k . 2>/dev/null || {
        echo "Failed to recreate deployment. Please check manually."
        exit 1
      }
    }
    
    echo "Waiting for deployment to create pods..."
    sleep 10
    LGTM_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
    
    if [ -z "$LGTM_POD" ]; then
      echo "Deployment created but no pod found yet. Checking deployment status..."
      kubectl get deployment -n $NAMESPACE | grep lgtm
      echo "Please wait a moment and run this script again, or check manually: kubectl get pods -n $NAMESPACE"
      exit 1
    fi
  else
    echo "Deployment $LGTM_DEPLOYMENT exists but no pods found. Checking deployment status..."
    kubectl describe deployment -n $NAMESPACE $LGTM_DEPLOYMENT | grep -A 10 "Events:" || true
    echo ""
    echo "If deployment is stuck, you may need to check events or recreate it."
    exit 1
  fi
fi

echo "Found pod: $LGTM_POD"
POD_STATUS=$(kubectl get pod -n $NAMESPACE $LGTM_POD -o jsonpath='{.status.phase}' 2>/dev/null)
echo "Pod status: $POD_STATUS"

if [ "$POD_STATUS" = "Running" ]; then
  echo "Pod is already Running. Checking if all containers are ready..."
  READY=$(kubectl get pod -n $NAMESPACE $LGTM_POD -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
  if [[ "$READY" == *"false"* ]]; then
    echo "Pod is Running but not all containers are ready. Waiting..."
    kubectl wait --for=condition=ready pod -n $NAMESPACE $LGTM_POD --timeout=600s
  else
    echo "Pod is Running and all containers are ready!"
    exit 0
  fi
fi

if [ "$POD_STATUS" = "Pending" ]; then
  echo "Pod is Pending. Checking events..."
  EVENTS=$(kubectl describe pod -n $NAMESPACE $LGTM_POD 2>/dev/null | grep -A 10 "Events:" || echo "")
  echo "$EVENTS"
  
  if echo "$EVENTS" | grep -q "unbound immediate PersistentVolumeClaims"; then
    echo ""
    echo "=== Detected storage class issue: unbound PersistentVolumeClaims ==="
    
    # Check PVC status
    echo "Checking PVC status..."
    kubectl get pvc -n $NAMESPACE
    
    # Check storage class
    echo ""
    echo "Checking storage classes..."
    kubectl get storageclass
    
    # Check if storage class uses no-provisioner
    NO_PROVISIONER=$(kubectl get storageclass -o jsonpath='{.items[?(@.provisioner=="kubernetes.io/no-provisioner")].metadata.name}' 2>/dev/null | head -1)
    
    if [ ! -z "$NO_PROVISIONER" ]; then
      echo ""
      echo "=== Found no-provisioner storage class: $NO_PROVISIONER ==="
      echo "Installing local-path-provisioner to automatically provision PVs..."
      
      # Install local-path-provisioner
      kubectl apply -f $LOCAL_PATH_PROVISIONER_URL
      
      # Wait for local-path-provisioner to be ready
      echo "Waiting for local-path-provisioner to be ready..."
      if kubectl wait --for=condition=ready pod -n local-path-storage -l app=local-path-provisioner --timeout=60s 2>/dev/null; then
        echo "local-path-provisioner is ready!"
      else
        echo "Warning: local-path-provisioner may not be ready yet, but continuing..."
      fi
      
      # Set local-path as default
      echo "Setting local-path as default storage class..."
      kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || echo "local-path storage class may not exist yet"
      
      # Remove default from old storage class
      if [ ! -z "$NO_PROVISIONER" ]; then
        echo "Removing default annotation from $NO_PROVISIONER..."
        kubectl patch storageclass $NO_PROVISIONER -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true
      fi
      
      # Delete PVCs to recreate with new storage class
      echo "Deleting existing PVCs to recreate with new storage class..."
      kubectl delete pvc -n $NAMESPACE --all 2>/dev/null || true
      
      # Delete deployment to force recreation
      LGTM_DEPLOYMENT=$(kubectl get deployment -n $NAMESPACE 2>/dev/null | grep lgtm | awk '{print $1}' | head -1)
      if [ ! -z "$LGTM_DEPLOYMENT" ]; then
        echo "Deleting deployment $LGTM_DEPLOYMENT to force recreation..."
        kubectl delete deployment -n $NAMESPACE $LGTM_DEPLOYMENT 2>/dev/null || true
      fi
      
      echo "Waiting 10 seconds for resources to be cleaned up..."
      sleep 10
      
      # Recreate deployment with local-path storage class
      echo "Recreating LGTM deployment with local-path storage class..."
      LGTM_YAML_DIR="$HOME/aim-deploy/kserve/kserve-install/post-helm/base/otel-lgtm-stack-standalone"
      if [ -d "$LGTM_YAML_DIR" ]; then
        cd "$LGTM_YAML_DIR"
        # Use sed to replace default with local-path in the YAML
        sed 's/storageClassName: default/storageClassName: local-path/g' otel-lgtm.yaml | kubectl apply -f - 2>/dev/null || {
          echo "Warning: Failed to apply with storage class replacement, trying original YAML..."
          kubectl apply -k . 2>/dev/null || true
        }
      else
        echo "Warning: LGTM YAML directory not found. Deployment may need to be recreated manually."
      fi
      
      echo "Waiting 10 seconds for resources to be recreated..."
      sleep 10
      
      # Check PVC status
      echo ""
      echo "Checking PVC status after fix..."
      kubectl get pvc -n $NAMESPACE
      
      # Wait for pod to be recreated and ready
      echo ""
      echo "Waiting for pod to be recreated and ready..."
      MAX_WAIT=600
      ELAPSED=0
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        NEW_POD=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep -E "lgtm|grafana" | awk '{print $1}' | head -1)
        if [ ! -z "$NEW_POD" ]; then
          if kubectl wait --for=condition=ready pod -n $NAMESPACE $NEW_POD --timeout=60s 2>/dev/null; then
            echo "Pod $NEW_POD is now Ready!"
            exit 0
          fi
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        echo "Waiting... ($ELAPSED/$MAX_WAIT seconds)"
      done
      
      echo "Pod did not become ready within timeout. Check status manually:"
      kubectl get pods -n $NAMESPACE | grep -E "lgtm|grafana"
      exit 1
    else
      echo "No no-provisioner storage class found. Please check PVC and storage class configuration manually."
      exit 1
    fi
  else
    echo "Pod is Pending but not due to storage issues. Please check events manually:"
    kubectl describe pod -n $NAMESPACE $LGTM_POD
    exit 1
  fi
else
  echo "Pod status is $POD_STATUS. Waiting for it to become Ready..."
  kubectl wait --for=condition=ready pod -n $NAMESPACE $LGTM_POD --timeout=600s || {
    echo "Pod did not become ready. Check status:"
    kubectl describe pod -n $NAMESPACE $LGTM_POD
    exit 1
  }
  echo "Pod is now Ready!"
  exit 0
fi

