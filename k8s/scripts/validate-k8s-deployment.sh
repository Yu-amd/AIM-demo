#!/bin/bash

# Validate AIM Kubernetes deployment
# This script checks if the AIM deployment is healthy and functioning correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="aim"
SERVICE_NAME="aim-qwen3-32b"
TIMEOUT=300

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_cluster_connection() {
    print_info "Checking Kubernetes cluster connection..."
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi
    print_info "Cluster connection: OK"
}

check_namespace() {
    print_info "Checking namespace..."
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        print_info "Namespace exists: OK"
    else
        print_error "Namespace ${NAMESPACE} does not exist."
        exit 1
    fi
}

check_deployment() {
    print_info "Checking deployment..."
    if kubectl get deployment ${SERVICE_NAME} -n ${NAMESPACE} &> /dev/null; then
        READY=$(kubectl get deployment ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}')
        DESIRED=$(kubectl get deployment ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
        if [ "$READY" == "$DESIRED" ] && [ "$READY" != "0" ]; then
            print_info "Deployment ready: ${READY}/${DESIRED} replicas"
        else
            print_error "Deployment not ready: ${READY}/${DESIRED} replicas"
            print_info "Checking pod status..."
            kubectl get pods -n ${NAMESPACE} -l app=${SERVICE_NAME}
            exit 1
        fi
    else
        print_error "Deployment ${SERVICE_NAME} does not exist."
        exit 1
    fi
}

check_pods() {
    print_info "Checking pods..."
    PODS=$(kubectl get pods -n ${NAMESPACE} -l app=${SERVICE_NAME} -o jsonpath='{.items[*].metadata.name}')
    if [ -z "$PODS" ]; then
        print_error "No pods found for ${SERVICE_NAME}"
        exit 1
    fi
    
    for POD in $PODS; do
        STATUS=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.status.phase}')
        if [ "$STATUS" == "Running" ]; then
            print_info "Pod ${POD}: ${STATUS}"
        else
            print_error "Pod ${POD}: ${STATUS}"
            print_info "Pod logs:"
            kubectl logs ${POD} -n ${NAMESPACE} --tail=50
            exit 1
        fi
    done
}

check_service() {
    print_info "Checking service..."
    if kubectl get service ${SERVICE_NAME} -n ${NAMESPACE} &> /dev/null; then
        print_info "Service exists: OK"
        CLUSTER_IP=$(kubectl get service ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
        print_info "Service ClusterIP: ${CLUSTER_IP}"
    else
        print_error "Service ${SERVICE_NAME} does not exist."
        exit 1
    fi
}

check_health_endpoint() {
    print_info "Checking health endpoint..."
    
    # Get a pod name
    POD=$(kubectl get pods -n ${NAMESPACE} -l app=${SERVICE_NAME} -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$POD" ]; then
        print_error "No pods available for health check"
        exit 1
    fi
    
    # Check health endpoint
    print_info "Testing /health endpoint on pod ${POD}..."
    if kubectl exec ${POD} -n ${NAMESPACE} -- curl -s -f http://localhost:8000/health &> /dev/null; then
        print_info "Health endpoint: OK"
    else
        print_warn "Health endpoint check failed. Service may still be starting up."
        print_info "Checking service logs..."
        kubectl logs ${POD} -n ${NAMESPACE} --tail=50
    fi
}

check_ready_endpoint() {
    print_info "Checking ready endpoint..."
    
    POD=$(kubectl get pods -n ${NAMESPACE} -l app=${SERVICE_NAME} -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$POD" ]; then
        print_error "No pods available for readiness check"
        exit 1
    fi
    
    if kubectl exec ${POD} -n ${NAMESPACE} -- curl -s -f http://localhost:8000/ready &> /dev/null; then
        print_info "Ready endpoint: OK"
    else
        print_warn "Ready endpoint check failed. Service may still be initializing."
    fi
}

check_resources() {
    print_info "Checking resource usage..."
    kubectl top pods -n ${NAMESPACE} -l app=${SERVICE_NAME} 2>/dev/null || print_warn "Metrics not available (metrics-server may not be installed)"
}

check_hpa() {
    print_info "Checking HorizontalPodAutoscaler..."
    if kubectl get hpa ${SERVICE_NAME}-hpa -n ${NAMESPACE} &> /dev/null; then
        print_info "HPA exists: OK"
        kubectl get hpa ${SERVICE_NAME}-hpa -n ${NAMESPACE}
    else
        print_warn "HPA not found (this is optional)"
    fi
}

check_observability() {
    print_info "Checking observability stack..."
    if kubectl get namespace monitoring &> /dev/null; then
        if kubectl get deployment prometheus -n monitoring &> /dev/null; then
            print_info "Prometheus: OK"
        else
            print_warn "Prometheus not found"
        fi
        if kubectl get deployment grafana -n monitoring &> /dev/null; then
            print_info "Grafana: OK"
        else
            print_warn "Grafana not found"
        fi
    else
        print_warn "Monitoring namespace not found (observability not deployed)"
    fi
}

# Main validation flow
main() {
    print_info "Starting AIM Kubernetes deployment validation..."
    echo ""
    
    check_cluster_connection
    check_namespace
    check_deployment
    check_pods
    check_service
    check_health_endpoint
    check_ready_endpoint
    check_resources
    check_hpa
    check_observability
    
    echo ""
    print_info "Validation completed!"
    print_info "To test inference: kubectl port-forward -n ${NAMESPACE} svc/${SERVICE_NAME} 8000:8000"
    print_info "Then: curl http://localhost:8000/v1/completions -H 'Content-Type: application/json' -d '{\"prompt\":\"Hello\",\"max_tokens\":10}'"
}

# Run main function
main "$@"

