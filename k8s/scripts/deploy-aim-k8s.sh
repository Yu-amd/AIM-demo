#!/bin/bash

# Deploy AMD Inference Microservice (AIM) to Kubernetes
# This script automates the deployment of AIM to a Kubernetes cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="aim"
KUBECTL_CMD="kubectl"
DEPLOYMENT_DIR="kubernetes"
OBSERVABILITY_DIR="observability"

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

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    print_info "Prerequisites check passed."
}

deploy_namespace() {
    print_info "Creating namespace..."
    kubectl apply -f ${DEPLOYMENT_DIR}/namespace.yaml
    print_info "Namespace created."
}

deploy_configmap() {
    print_info "Creating ConfigMap..."
    kubectl apply -f ${DEPLOYMENT_DIR}/configmap.yaml
    print_info "ConfigMap created."
}

deploy_serviceaccount() {
    print_info "Creating ServiceAccount and RBAC..."
    kubectl apply -f ${DEPLOYMENT_DIR}/serviceaccount.yaml
    print_info "ServiceAccount and RBAC created."
}

deploy_deployment() {
    print_info "Deploying AIM inference service..."
    kubectl apply -f ${DEPLOYMENT_DIR}/deployment.yaml
    print_info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/aim-qwen3-32b -n ${NAMESPACE} || {
        print_error "Deployment failed to become ready. Check logs with: kubectl logs -n ${NAMESPACE} -l app=aim-qwen3-32b"
        exit 1
    }
    print_info "Deployment is ready."
}

deploy_service() {
    print_info "Creating Service..."
    kubectl apply -f ${DEPLOYMENT_DIR}/service.yaml
    print_info "Service created."
}

deploy_pdb() {
    print_info "Creating PodDisruptionBudget..."
    kubectl apply -f ${DEPLOYMENT_DIR}/pdb.yaml
    print_info "PodDisruptionBudget created."
}

deploy_hpa() {
    print_info "Creating HorizontalPodAutoscaler..."
    # Check if metrics-server is available
    if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        kubectl apply -f ${DEPLOYMENT_DIR}/hpa.yaml
        print_info "HorizontalPodAutoscaler created."
    else
        print_warn "metrics-server not found. HPA will not work properly. Skipping HPA deployment."
        print_warn "To enable HPA, install metrics-server: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
}

deploy_observability() {
    if [ "$1" == "--with-observability" ]; then
        print_info "Deploying observability stack..."
        
        # Deploy Prometheus
        print_info "Deploying Prometheus..."
        kubectl apply -f ${OBSERVABILITY_DIR}/prometheus-deployment.yaml
        
        # Deploy Grafana
        print_info "Deploying Grafana..."
        kubectl apply -f ${OBSERVABILITY_DIR}/grafana-deployment.yaml
        
        # Wait for Prometheus
        print_info "Waiting for Prometheus to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring || true
        
        # Wait for Grafana
        print_info "Waiting for Grafana to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring || true
        
        print_info "Observability stack deployed."
        print_info "Access Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
        print_info "Access Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    fi
}

show_status() {
    print_info "Deployment status:"
    echo ""
    kubectl get pods -n ${NAMESPACE}
    echo ""
    kubectl get svc -n ${NAMESPACE}
    echo ""
    kubectl get hpa -n ${NAMESPACE} 2>/dev/null || echo "HPA not deployed"
    echo ""
    print_info "To view logs: kubectl logs -n ${NAMESPACE} -l app=aim-qwen3-32b -f"
    print_info "To test the service: kubectl port-forward -n ${NAMESPACE} svc/aim-qwen3-32b 8000:8000"
}

# Main deployment flow
main() {
    print_info "Starting AIM Kubernetes deployment..."
    
    check_prerequisites
    deploy_namespace
    deploy_configmap
    deploy_serviceaccount
    deploy_deployment
    deploy_service
    deploy_pdb
    deploy_hpa "$@"
    deploy_observability "$@"
    
    show_status
    
    print_info "Deployment completed successfully!"
}

# Run main function
main "$@"

