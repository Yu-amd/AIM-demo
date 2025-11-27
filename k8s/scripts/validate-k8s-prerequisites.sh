#!/bin/bash

# validate-k8s-prerequisites.sh
# Automated prerequisite validation for Kubernetes AIM deployment
# This script checks all prerequisites mentioned in KUBERNETES-DEPLOYMENT.md
# 
# Usage: bash ./validate-k8s-prerequisites.sh

# Don't exit on error - we want to continue checking all prerequisites
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $message"
        ((PASSED++))
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗${NC} $message"
        ((FAILED++))
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
        ((WARNINGS++))
    else
        echo -e "${BLUE}ℹ${NC} $message"
    fi
}

# Function to check command availability
check_command() {
    local cmd=$1
    local version_flag=${2:-"--version"}
    
    if command -v "$cmd" &> /dev/null; then
        local version=$(eval "$cmd $version_flag 2>&1" | head -1)
        print_status "PASS" "$cmd is installed: $version"
        return 0
    else
        print_status "FAIL" "$cmd is not installed"
        return 1
    fi
}

# Function to check kubectl cluster access
check_kubectl_cluster() {
    if kubectl cluster-info &> /dev/null; then
        local endpoint=$(kubectl cluster-info 2>/dev/null | grep "Kubernetes control plane" | sed 's/.*running at //')
        print_status "PASS" "Kubernetes cluster is accessible: $endpoint"
        return 0
    else
        print_status "FAIL" "Cannot access Kubernetes cluster. Check kubectl configuration."
        return 1
    fi
}

# Function to check GPU operator
check_gpu_operator() {
    local found=0
    
    # Check amd-gpu-operator namespace
    if kubectl get pods -n amd-gpu-operator &> /dev/null; then
        local device_plugin=$(kubectl get pods -n amd-gpu-operator 2>/dev/null | grep device-plugin | head -1)
        if [ ! -z "$device_plugin" ]; then
            print_status "PASS" "AMD GPU device plugin found in amd-gpu-operator namespace"
            found=1
        fi
    fi
    
    # Check all namespaces as fallback
    if [ $found -eq 0 ]; then
        local device_plugin=$(kubectl get pods --all-namespaces 2>/dev/null | grep -E "gpu|device-plugin" | head -1)
        if [ ! -z "$device_plugin" ]; then
            print_status "PASS" "GPU device plugin found (alternative namespace)"
            found=1
        fi
    fi
    
    if [ $found -eq 0 ]; then
        print_status "FAIL" "AMD GPU operator or device plugin not found"
        echo "  → Refer to Kubernetes-MI300X setup guide: https://github.com/Yu-amd/Kubernetes-MI300X"
        return 1
    fi
    
    return 0
}

# Function to check GPU resources
check_gpu_resources() {
    local nodes=$(kubectl get nodes -o name 2>/dev/null | head -1)
    if [ -z "$nodes" ]; then
        print_status "FAIL" "No nodes found in cluster"
        return 1
    fi
    
    local node_name=$(echo $nodes | sed 's|node/||')
    local gpu_info=$(kubectl describe node "$node_name" 2>/dev/null | grep -i "amd.com/gpu" | head -1)
    
    if [ ! -z "$gpu_info" ]; then
        print_status "PASS" "GPU resources detected on node: $node_name"
        echo "  → $gpu_info"
        return 0
    else
        print_status "WARN" "GPU resources not found on node: $node_name"
        echo "  → This may be normal if GPU operator is still initializing"
        return 0
    fi
}

# Function to check storage class
check_storage_class() {
    local default_sc=$(kubectl get storageclass 2>/dev/null | grep "(default)" | head -1)
    
    if [ ! -z "$default_sc" ]; then
        print_status "PASS" "Default storage class found"
        echo "  → $(echo $default_sc | awk '{print $1}')"
        return 0
    else
        print_status "WARN" "No default storage class found"
        echo "  → Required for observability components (Step 2.3)"
        echo "  → You can create one or set an existing storage class as default"
        return 0
    fi
}

# Function to check cluster admin privileges
check_cluster_admin() {
    if kubectl auth can-i create namespaces &> /dev/null; then
        print_status "PASS" "Cluster admin privileges confirmed"
        return 0
    else
        print_status "FAIL" "Insufficient privileges. Cluster admin access required for KServe installation."
        return 1
    fi
}

# Main validation
echo "=========================================="
echo "Kubernetes AIM Deployment Prerequisites"
echo "=========================================="
echo ""

echo "Checking required tools..."
echo "---------------------------"

# Check kubectl
if check_command "kubectl" "version --client"; then
    local k8s_version=$(kubectl version --client --short 2>/dev/null | head -1)
    if [ ! -z "$k8s_version" ]; then
        echo "  → $k8s_version"
    fi
fi

# Check Helm
if check_command "helm" "version"; then
    local helm_version=$(helm version --short 2>/dev/null | head -1)
    if [ ! -z "$helm_version" ]; then
        echo "  → $helm_version"
    fi
fi

# Check curl
check_command "curl" "--version" > /dev/null 2>&1 || true

# Check git
check_command "git" "--version" > /dev/null 2>&1 || true

# Check jq (optional)
if command -v jq &> /dev/null; then
    local jq_version=$(jq --version 2>/dev/null)
    print_status "PASS" "jq is installed: $jq_version (optional but recommended for JSON processing)"
else
    print_status "WARN" "jq is not installed (optional, but useful for JSON processing)"
fi

echo ""
echo "Checking Kubernetes cluster access..."
echo "--------------------------------------"

# Check cluster access
check_kubectl_cluster

# Check nodes
if kubectl get nodes &> /dev/null; then
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    print_status "PASS" "Found $node_count node(s) in cluster"
    kubectl get nodes 2>/dev/null | head -5
else
    print_status "FAIL" "Cannot list nodes"
fi

echo ""
echo "Checking GPU support..."
echo "----------------------"

# Check GPU operator
check_gpu_operator

# Check GPU resources
check_gpu_resources

echo ""
echo "Checking cluster configuration..."
echo "---------------------------------"

# Check storage class
check_storage_class

# Check cluster admin
check_cluster_admin

# Check internet access (basic check)
if curl -s --max-time 5 https://www.google.com &> /dev/null || curl -s --max-time 5 https://github.com &> /dev/null; then
    print_status "PASS" "Internet access available (required for pulling charts and manifests)"
else
    print_status "WARN" "Internet access check failed (may still work if internal registry is configured)"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC} $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical prerequisites are met!${NC}"
    echo ""
    echo "You can proceed with the deployment."
    echo "Refer to KUBERNETES-DEPLOYMENT.md for step-by-step instructions."
    exit 0
else
    echo -e "${RED}✗ Some prerequisites are not met.${NC}"
    echo ""
    echo "Please resolve the failed checks before proceeding."
    echo "Refer to the Kubernetes-MI300X setup guide: https://github.com/Yu-amd/Kubernetes-MI300X"
    exit 1
fi

