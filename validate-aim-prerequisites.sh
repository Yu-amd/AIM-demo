#!/bin/bash

################################################################################
# AMD Inference Microservice (AIM) - Prerequisites Validation Script
# 
# This script validates all prerequisites for deploying AIM on AMD Instinct GPUs
# It covers Steps 1.1 through 1.9 from the AIM walkthrough guide.
#
# Usage: ./validate-aim-prerequisites.sh
################################################################################

# Don't exit on error - we want to continue checking all prerequisites
set +e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
# Step 1.1: Verify Operating System
################################################################################
print_section "Step 1.1: Verify Operating System"

print_check "Operating System Information" "uname -a"
OS_INFO=$(uname -a)
echo "Output:"
echo "$OS_INFO"
echo ""

# Check OS type
if [[ "$OS_INFO" == *"Linux"* ]]; then
    echo -e "${GREEN}✓ Operating system is Linux${NC}"
else
    check_failed "OS_TYPE"
    print_fix "This script is designed for Linux systems. Please run on a Linux-based system."
    echo ""
fi

# Check architecture
if [[ "$OS_INFO" == *"x86_64"* ]]; then
    echo -e "${GREEN}✓ Architecture is x86_64${NC}"
    check_passed "OS_ARCH"
else
    check_failed "OS_ARCH"
    print_fix "AMD Instinct MI300X requires x86_64 architecture. Please verify you are on the correct node type."
    echo ""
fi

# Extract kernel version
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d. -f2)

if [ "$KERNEL_MAJOR" -gt 5 ] || ([ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -ge 15 ]); then
    echo -e "${GREEN}✓ Kernel version is 5.15+ (recommended for MI300X)${NC}"
    check_passed "OS_KERNEL"
else
    echo -e "${YELLOW}⚠ Kernel version is $KERNEL_VERSION (5.15+ recommended)${NC}"
    check_passed "OS_KERNEL"  # Warning but not blocking
    echo ""
fi

check_passed "STEP_1_1"

################################################################################
# Step 1.2: Verify Docker Installation
################################################################################
print_section "Step 1.2: Verify Docker Installation"

print_check "Docker Version" "docker --version"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "Output:"
    echo "$DOCKER_VERSION"
    echo ""
    
    # Extract version number
    DOCKER_VER_NUM=$(docker --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    DOCKER_MAJOR=$(echo $DOCKER_VER_NUM | cut -d. -f1)
    DOCKER_MINOR=$(echo $DOCKER_VER_NUM | cut -d. -f2)
    
    if [ "$DOCKER_MAJOR" -gt 20 ] || ([ "$DOCKER_MAJOR" -eq 20 ] && [ "$DOCKER_MINOR" -ge 10 ]); then
        echo -e "${GREEN}✓ Docker version is 20.10+${NC}"
        check_passed "DOCKER_VERSION"
    else
        echo -e "${YELLOW}⚠ Docker version is $DOCKER_VER_NUM (20.10+ recommended)${NC}"
        check_passed "DOCKER_VERSION"  # Warning but not blocking
    fi
else
    check_failed "DOCKER_VERSION"
    print_fix "Docker is not installed. Install Docker:
    
For Ubuntu/Debian:
  sudo apt-get update
  sudo apt-get install docker.io
  sudo systemctl start docker
  sudo systemctl enable docker

For RHEL/CentOS:
  sudo yum install docker
  sudo systemctl start docker
  sudo systemctl enable docker

After installation, add your user to the docker group:
  sudo usermod -aG docker \$USER
  newgrp docker"
    echo ""
fi

# Test Docker daemon
print_check "Docker Daemon Status" "docker ps"
if docker ps &> /dev/null; then
    echo "Output:"
    docker ps
    echo ""
    echo -e "${GREEN}✓ Docker daemon is running${NC}"
    check_passed "DOCKER_DAEMON"
else
    check_failed "DOCKER_DAEMON"
    print_fix "Docker daemon is not running. Start it with:
  sudo systemctl start docker

If you get permission denied, add your user to the docker group:
  sudo usermod -aG docker \$USER
  newgrp docker

Or use sudo: sudo docker ps"
    echo ""
fi

# Test Docker can run containers
print_check "Docker Container Test" "docker run --rm hello-world"
if docker run --rm hello-world &> /dev/null; then
    echo -e "${GREEN}✓ Docker can run containers${NC}"
    check_passed "DOCKER_CONTAINER_TEST"
else
    check_failed "DOCKER_CONTAINER_TEST"
    print_fix "Docker cannot run containers. Check:
1. Docker daemon is running: sudo systemctl status docker
2. User has permissions: sudo usermod -aG docker \$USER; newgrp docker
3. Try with sudo: sudo docker run --rm hello-world"
    echo ""
fi

check_passed "STEP_1_2"

################################################################################
# Step 1.3: Verify ROCm Installation
################################################################################
print_section "Step 1.3: Verify ROCm Installation"

print_check "ROCm Version" "rocm-smi --version"
if command -v rocm-smi &> /dev/null; then
    ROCM_VERSION_OUTPUT=$(rocm-smi --version 2>&1)
    echo "Output:"
    echo "$ROCM_VERSION_OUTPUT"
    echo ""
    
    if [[ "$ROCM_VERSION_OUTPUT" == *"ROCM-SMI version"* ]]; then
        echo -e "${GREEN}✓ ROCm is installed${NC}"
        check_passed "ROCM_INSTALLED"
    else
        check_failed "ROCM_INSTALLED"
    fi
else
    check_failed "ROCM_INSTALLED"
    print_fix "ROCm is not installed or not in PATH. 

For CSP nodes, ROCm should be pre-installed. Contact your cloud provider support.
For bare metal, install ROCm following AMD's documentation:
  https://rocm.docs.amd.com/en/latest/deploy/linux/quick_start.html

Verify ROCm installation:
  which rocm-smi
  rocm-smi --version"
    echo ""
fi

# Check GPU detection
print_check "GPU Detection" "rocm-smi"
if command -v rocm-smi &> /dev/null; then
    ROCM_SMI_OUTPUT=$(rocm-smi 2>&1)
    echo "Output:"
    echo "$ROCM_SMI_OUTPUT"
    echo ""
    
    if echo "$ROCM_SMI_OUTPUT" | grep -q "Device"; then
        GPU_COUNT=$(echo "$ROCM_SMI_OUTPUT" | grep -c "Device" || echo "0")
        echo -e "${GREEN}✓ Detected $GPU_COUNT GPU device(s)${NC}"
        check_passed "ROCM_GPU_DETECTED"
    else
        check_failed "ROCM_GPU_DETECTED"
        print_fix "No GPUs detected. Check:
1. GPU is properly installed: lspci | grep -i amd
2. ROCm drivers are loaded: lsmod | grep amdgpu
3. Check kernel messages: dmesg | grep -i amd
4. Verify GPU is not in low-power state (this is often normal when idle)"
        echo ""
    fi
else
    check_failed "ROCM_GPU_DETECTED"
fi

# Get detailed GPU information
print_check "GPU Product Information" "rocm-smi --showproductname"
if command -v rocm-smi &> /dev/null; then
    GPU_INFO=$(rocm-smi --showproductname 2>&1)
    echo "Output:"
    echo "$GPU_INFO"
    echo ""
    
    if echo "$GPU_INFO" | grep -qi "MI300\|MI325\|Instinct"; then
        GPU_MODEL=$(echo "$GPU_INFO" | grep "Card Series" | head -1 | awk -F': ' '{print $2}' | xargs)
        echo -e "${GREEN}✓ GPU model detected: $GPU_MODEL${NC}"
        check_passed "ROCM_GPU_MODEL"
    else
        echo -e "${YELLOW}⚠ GPU model may not be MI300X/MI325X (check compatibility)${NC}"
        check_passed "ROCM_GPU_MODEL"  # Warning but not blocking
    fi
    
    if echo "$GPU_INFO" | grep -q "gfx942\|gfx940\|gfx941"; then
        GFX_VERSION=$(echo "$GPU_INFO" | grep "GFX Version" | head -1 | awk -F': ' '{print $2}' | xargs)
        echo -e "${GREEN}✓ GFX version: $GFX_VERSION (compatible)${NC}"
        check_passed "ROCM_GFX_VERSION"
    else
        echo -e "${YELLOW}⚠ GFX version may not be optimal for MI300X${NC}"
        check_passed "ROCM_GFX_VERSION"  # Warning but not blocking
    fi
else
    check_failed "ROCM_GPU_MODEL"
    check_failed "ROCM_GFX_VERSION"
fi

check_passed "STEP_1_3"

################################################################################
# Step 1.4: Verify GPU Device Nodes
################################################################################
print_section "Step 1.4: Verify GPU Device Nodes"

print_check "GPU Device Nodes" "ls -la /dev/kfd /dev/dri/"
if [ -e /dev/kfd ]; then
    echo "Output:"
    ls -la /dev/kfd /dev/dri/ 2>&1
    echo ""
    
    if [ -c /dev/kfd ]; then
        echo -e "${GREEN}✓ /dev/kfd exists and is a character device${NC}"
        check_passed "DEV_KFD_EXISTS"
    else
        check_failed "DEV_KFD_EXISTS"
        print_fix "/dev/kfd is not a character device. This may indicate ROCm installation issues.
Check: ls -l /dev/kfd
If missing, try: sudo modprobe kfd"
        echo ""
    fi
else
    check_failed "DEV_KFD_EXISTS"
    print_fix "/dev/kfd does not exist. This indicates ROCm is not properly installed or kernel module is not loaded.

Try:
  sudo modprobe kfd
  ls -la /dev/kfd

If still missing, ROCm may need to be reinstalled or kernel modules loaded."
    echo ""
fi

# Check /dev/dri directory
if [ -d /dev/dri ]; then
    CARD_COUNT=$(ls -1 /dev/dri/card* 2>/dev/null | wc -l)
    RENDER_COUNT=$(ls -1 /dev/dri/renderD* 2>/dev/null | wc -l)
    
    if [ "$CARD_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $CARD_COUNT card device(s) in /dev/dri/${NC}"
        check_passed "DEV_DRI_CARDS"
    else
        check_failed "DEV_DRI_CARDS"
        print_fix "No card devices found in /dev/dri/. Check ROCm installation and GPU detection."
        echo ""
    fi
    
    if [ "$RENDER_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $RENDER_COUNT render device(s) in /dev/dri/${NC}"
        check_passed "DEV_DRI_RENDER"
    else
        check_failed "DEV_DRI_RENDER"
        print_fix "No render devices found in /dev/dri/. Check ROCm installation."
        echo ""
    fi
else
    check_failed "DEV_DRI_CARDS"
    check_failed "DEV_DRI_RENDER"
    print_fix "/dev/dri/ directory does not exist. Check ROCm installation."
    echo ""
fi

# Verify device accessibility
print_check "Device Accessibility" "test -r /dev/kfd && test -r /dev/dri/card0"
if [ -r /dev/kfd ] && [ -r /dev/dri/card0 ]; then
    echo -e "${GREEN}✓ /dev/kfd is readable${NC}"
    echo -e "${GREEN}✓ /dev/dri/card0 is readable${NC}"
    check_passed "DEV_ACCESSIBLE"
else
    check_failed "DEV_ACCESSIBLE"
    print_fix "GPU devices are not readable. Fix permissions:

1. Check current permissions:
   ls -l /dev/kfd /dev/dri/card*

2. Add user to required groups:
   sudo usermod -aG render,video \$USER
   newgrp render
   newgrp video

3. If running as root, permissions should be fine. Verify with:
   sudo test -r /dev/kfd && echo 'Readable' || echo 'Not readable'"
    echo ""
fi

check_passed "STEP_1_4"

################################################################################
# Step 1.5: Verify User Permissions
################################################################################
print_section "Step 1.5: Verify User Permissions"

print_check "User ID and Groups" "id; groups"
USER_ID=$(id)
USER_GROUPS=$(groups)
echo "Output:"
echo "$USER_ID"
echo "$USER_GROUPS"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${GREEN}✓ Running as root (has all permissions)${NC}"
    check_passed "USER_PERMISSIONS"
else
    # Check for render group
    if echo "$USER_GROUPS" | grep -q "render"; then
        echo -e "${GREEN}✓ User is in 'render' group${NC}"
        RENDER_GROUP_OK=true
    else
        echo -e "${RED}✗ User is NOT in 'render' group${NC}"
        RENDER_GROUP_OK=false
    fi
    
    # Check for video group
    if echo "$USER_GROUPS" | grep -q "video"; then
        echo -e "${GREEN}✓ User is in 'video' group${NC}"
        VIDEO_GROUP_OK=true
    else
        echo -e "${RED}✗ User is NOT in 'video' group${NC}"
        VIDEO_GROUP_OK=false
    fi
    
    if [ "$RENDER_GROUP_OK" = true ] && [ "$VIDEO_GROUP_OK" = true ]; then
        check_passed "USER_PERMISSIONS"
    else
        check_failed "USER_PERMISSIONS"
        print_fix "User is missing required group memberships. Add to groups:

  sudo usermod -aG render,video \$USER

Then start a new shell session or run:
  newgrp render
  newgrp video

Verify with: groups"
        echo ""
    fi
fi

check_passed "STEP_1_5"

################################################################################
# Step 1.6: Verify System Resources
################################################################################
print_section "Step 1.6: Verify System Resources"

print_check "Available Memory" "free -h"
MEMORY_INFO=$(free -h)
echo "Output:"
echo "$MEMORY_INFO"
echo ""

# Extract available memory in GB
AVAIL_MEM=$(free -g | awk '/^Mem:/ {print $7}')
TOTAL_MEM=$(free -g | awk '/^Mem:/ {print $2}')

if [ "$AVAIL_MEM" -ge 64 ]; then
    echo -e "${GREEN}✓ Available memory: ${AVAIL_MEM}GB (64GB+ recommended)${NC}"
    check_passed "MEMORY_AVAILABLE"
elif [ "$AVAIL_MEM" -ge 32 ]; then
    echo -e "${YELLOW}⚠ Available memory: ${AVAIL_MEM}GB (64GB+ recommended, 32GB minimum)${NC}"
    check_passed "MEMORY_AVAILABLE"  # Warning but may work for smaller models
else
    check_failed "MEMORY_AVAILABLE"
    print_fix "Insufficient available memory: ${AVAIL_MEM}GB. 

For 32B models, recommend at least 64GB RAM (128GB+ preferred).
Consider:
- Using a smaller model
- Requesting a larger node from your CSP
- Freeing up memory by stopping other processes"
    echo ""
fi

print_check "Disk Space" "df -h /"
DISK_INFO=$(df -h /)
echo "Output:"
echo "$DISK_INFO"
echo ""

# Extract available disk space
AVAIL_DISK=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

if [ "$AVAIL_DISK" -ge 200 ]; then
    echo -e "${GREEN}✓ Available disk space: ${AVAIL_DISK}GB (200GB+ recommended)${NC}"
    check_passed "DISK_SPACE"
elif [ "$AVAIL_DISK" -ge 100 ]; then
    echo -e "${YELLOW}⚠ Available disk space: ${AVAIL_DISK}GB (200GB+ recommended, 100GB minimum)${NC}"
    check_passed "DISK_SPACE"  # Warning but may work
else
    check_failed "DISK_SPACE"
    print_fix "Insufficient disk space: ${AVAIL_DISK}GB.

For large models (32B), recommend at least 100GB free (200GB+ preferred).
Model weights can be 60GB+.

Free up space:
  docker system prune -a  # Remove unused Docker images
  # Clean up other files as needed
  df -h  # Check what's using space"
    echo ""
fi

check_passed "STEP_1_6"

################################################################################
# Step 1.7: Verify Network Connectivity
################################################################################
print_section "Step 1.7: Verify Network Connectivity"

print_check "Internet Connectivity" "ping -c 3 8.8.8.8"
if ping -c 3 -W 5 8.8.8.8 &> /dev/null; then
    echo "Output:"
    ping -c 3 8.8.8.8
    echo ""
    echo -e "${GREEN}✓ Internet connectivity is working${NC}"
    check_passed "NETWORK_CONNECTIVITY"
else
    check_failed "NETWORK_CONNECTIVITY"
    print_fix "Internet connectivity test failed. Check:
1. Network configuration: ip addr show
2. Default gateway: ip route show
3. DNS resolution: nslookup google.com
4. Firewall rules: sudo iptables -L -n
5. Some CSPs require proxy configuration - check your CSP documentation"
    echo ""
fi

print_check "Docker Hub Access" "curl -I https://hub.docker.com"
if curl -I -s --max-time 10 https://hub.docker.com &> /dev/null; then
    echo "Output:"
    curl -I -s --max-time 10 https://hub.docker.com | head -5
    echo ""
    echo -e "${GREEN}✓ Docker Hub is accessible${NC}"
    check_passed "DOCKER_HUB_ACCESS"
else
    check_failed "DOCKER_HUB_ACCESS"
    print_fix "Cannot access Docker Hub. Check:
1. Network connectivity (see above)
2. Proxy configuration if behind corporate firewall
3. DNS resolution: nslookup hub.docker.com
4. Some CSPs block external registries - check CSP documentation
5. Configure Docker registry mirrors if needed"
    echo ""
fi

check_passed "STEP_1_7"

################################################################################
# Step 1.8: Verify Port Availability
################################################################################
print_section "Step 1.8: Verify Port Availability"

PORT=8000
print_check "Port $PORT Availability" "netstat -tuln | grep $PORT || ss -tuln | grep $PORT"

if command -v netstat &> /dev/null; then
    PORT_CHECK=$(netstat -tuln 2>/dev/null | grep ":$PORT " || true)
elif command -v ss &> /dev/null; then
    PORT_CHECK=$(ss -tuln 2>/dev/null | grep ":$PORT " || true)
else
    PORT_CHECK=""
fi

if [ -z "$PORT_CHECK" ]; then
    echo "Output: (no output - port is free)"
    echo ""
    echo -e "${GREEN}✓ Port $PORT is available${NC}"
    check_passed "PORT_AVAILABLE"
else
    echo "Output:"
    echo "$PORT_CHECK"
    echo ""
    echo -e "${YELLOW}⚠ Port $PORT is already in use${NC}"
    check_passed "PORT_AVAILABLE"  # Warning, can use different port
    print_fix "Port $PORT is in use. Options:

1. Find and stop the conflicting service:
   sudo lsof -i :$PORT
   sudo netstat -tulpn | grep :$PORT
   # Then stop the service using the port

2. Use a different port when running the container:
   docker run ... -p 8001:8000 ...  # Use port 8001 instead"
    echo ""
fi

check_passed "STEP_1_8"

################################################################################
# Step 1.9: Final Pre-Deployment Checklist
################################################################################
print_section "Step 1.9: Final Pre-Deployment Checklist"

echo "Reviewing all validation results..."
echo ""

# Create checklist
declare -A CHECKLIST
CHECKLIST["Operating system is Linux x86_64"]=${CHECK_RESULTS[OS_ARCH]:-"FAILED"}
CHECKLIST["Docker is installed and working"]=${CHECK_RESULTS[DOCKER_DAEMON]:-"FAILED"}
CHECKLIST["Docker daemon is running"]=${CHECK_RESULTS[DOCKER_DAEMON]:-"FAILED"}
CHECKLIST["ROCm is installed"]=${CHECK_RESULTS[ROCM_INSTALLED]:-"FAILED"}
CHECKLIST["GPU is detected"]=${CHECK_RESULTS[ROCM_GPU_DETECTED]:-"FAILED"}
CHECKLIST["GPU model is compatible"]=${CHECK_RESULTS[ROCM_GPU_MODEL]:-"FAILED"}
CHECKLIST["/dev/kfd exists and is readable"]=${CHECK_RESULTS[DEV_KFD_EXISTS]:-"FAILED"}
CHECKLIST["/dev/dri/card* devices exist"]=${CHECK_RESULTS[DEV_DRI_CARDS]:-"FAILED"}
CHECKLIST["User has render and video group membership"]=${CHECK_RESULTS[USER_PERMISSIONS]:-"FAILED"}
CHECKLIST["Sufficient RAM available (64GB+ recommended)"]=${CHECK_RESULTS[MEMORY_AVAILABLE]:-"FAILED"}
CHECKLIST["Sufficient disk space (100GB+ free)"]=${CHECK_RESULTS[DISK_SPACE]:-"FAILED"}
CHECKLIST["Network connectivity works"]=${CHECK_RESULTS[NETWORK_CONNECTIVITY]:-"FAILED"}
CHECKLIST["Port 8000 is available (or alternative chosen)"]=${CHECK_RESULTS[PORT_AVAILABLE]:-"FAILED"}

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
    echo -e "${GREEN}✓ All prerequisites are met!${NC}"
    echo ""
    echo "You can proceed to Step 2: AIM Container Deployment"
    echo ""
    echo "Next steps:"
    echo "  1. Clone the AIM deployment repository:"
    echo "     git clone https://github.com/amd-enterprise-ai/aim-deploy.git"
    echo ""
    echo "  2. Pull the AIM container image:"
    echo "     docker pull amdenterpriseai/aim-qwen-qwen3-32b:0.8.4"
    echo ""
    echo "  3. Deploy the AIM container:"
    echo "     docker run -d --name aim-qwen3-32b \\"
    echo "       --device=/dev/kfd --device=/dev/dri \\"
    echo "       --security-opt seccomp=unconfined \\"
    echo "       --group-add video \\"
    echo "       --ipc=host \\"
    echo "       --shm-size=8g \\"
    echo "       -p 8000:8000 \\"
    echo "       amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 serve"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some prerequisites are not met${NC}"
    echo ""
    echo "Please review the failed checks above and follow the fix instructions."
    echo "Once all issues are resolved, run this script again to verify."
    echo ""
    exit 1
fi

