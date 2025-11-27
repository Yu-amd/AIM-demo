#!/bin/bash

# Cleanup AIM Kubernetes deployment
# This script removes all AIM-related resources from the cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="aim"
MONITORING_NAMESPACE="monitoring"

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

confirm_cleanup() {
    read -p "Are you sure you want to delete all AIM resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Cleanup cancelled."
        exit 0
    fi
}

cleanup_aim_resources() {
    print_info "Cleaning up AIM resources..."
    
    if kubectl get namespace ${NAMESPACE} &> /dev/null; then
        print_info "Deleting namespace ${NAMESPACE} (this will delete all resources in the namespace)..."
        kubectl delete namespace ${NAMESPACE} --wait=true || {
            print_warn "Some resources may still be terminating. Use 'kubectl get all -n ${NAMESPACE}' to check."
        }
        print_info "AIM namespace deleted."
    else
        print_info "Namespace ${NAMESPACE} does not exist."
    fi
}

cleanup_observability() {
    if [ "$1" == "--with-observability" ]; then
        print_info "Cleaning up observability stack..."
        
        if kubectl get namespace ${MONITORING_NAMESPACE} &> /dev/null; then
            read -p "Delete monitoring namespace? This will remove Prometheus and Grafana. (yes/no): " -r
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                kubectl delete namespace ${MONITORING_NAMESPACE} --wait=true || true
                print_info "Monitoring namespace deleted."
            else
                print_info "Skipping monitoring namespace deletion."
            fi
        else
            print_info "Monitoring namespace does not exist."
        fi
    fi
}

# Main cleanup flow
main() {
    print_warn "This will delete all AIM resources from the Kubernetes cluster."
    confirm_cleanup
    
    cleanup_aim_resources
    cleanup_observability "$@"
    
    print_info "Cleanup completed!"
}

# Run main function
main "$@"

