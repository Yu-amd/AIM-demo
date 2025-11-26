# Quickstart for AI Developers: Deploy AMD Inference Microservice (AIM) on Instinct MI300X

## Overview
This document summarizes the successful deployment and testing of AMD Inference Microservice (AIM) on an AMD Instinct MI300X GPU system, following the walkthrough from the [AMD ROCm blog](https://rocm.blogs.amd.com/artificial-intelligence/enterprise-ai-aims/README.html).

## System Configuration

### Hardware
- **GPU**: AMD Developer Cloud AMD Instinct MI300X VF
- **GPU ID**: 0x74b5
- **VRAM**: 196GB total
- **GFX Version**: gfx942

### Software
- **OS**: Ubuntu (Linux 6.8.0-87-generic)
- **ROCm**: Installed and functional
- **Docker**: Version 29.0.2
- **Container Image**: `amdenterpriseai/aim-qwen-qwen3-32b:0.8.4`

## Deployment Steps Completed

### 1. Prerequisites Verification

**Quick Start:** For automated validation, use the provided script:
```bash
chmod +x validate-aim-prerequisites.sh
./validate-aim-prerequisites.sh
```

This script automates Steps 1.1-1.9 and provides fix instructions for any failed checks.

**Manual Validation:** This section provides comprehensive step-by-step validation to ensure your CSP node is ready for AIM deployment. **Perform each check in order and verify the expected outputs before proceeding.**

#### Step 1.1: Verify Operating System

**Command:**
```bash
uname -a
```

**Expected Output:**
```
Linux <hostname> <kernel-version> #<build> <distro> <date> <arch> x86_64 x86_64 x86_64 GNU/Linux
```

**What to Check:**
- System is Linux-based (Ubuntu, RHEL, or similar)
- Architecture is `x86_64`
- Kernel version is recent (5.15+ recommended for MI300X)

**Example Output:**
```
Linux 7 6.8.0-87-generic #88-Ubuntu SMP PREEMPT_DYNAMIC Sat Oct 11 09:28:41 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
```

**Troubleshooting:**
- If architecture is not x86_64, verify you're on the correct node type
- If kernel is very old, consider updating (may require CSP support)

---

#### Step 1.2: Verify Docker Installation

**Command:**
```bash
docker --version
```

**Expected Output:**
```
Docker version <version>, build <build-id>
```

**What to Check:**
- Docker is installed
- Version is 20.10+ (recommended: 24.0+)

**Example Output:**
```
Docker version 29.0.2, build 8108357
```

**Additional Docker Checks:**

**Test Docker daemon:**
```bash
docker ps
```

**Expected Output:**
```
CONTAINER ID   IMAGE     COMMAND                  CREATED         STATUS         PORTS     NAMES
```
(May be empty if no containers running - this is fine)

**Verify Docker can run containers:**
```bash
docker run --rm hello-world
```

**Expected Output:**
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
...
```

**Troubleshooting:**
- If `docker: command not found`, install Docker:
  ```bash
  # Ubuntu/Debian
  sudo apt-get update
  sudo apt-get install docker.io
  sudo systemctl start docker
  sudo systemctl enable docker
  ```
- If `permission denied`, add user to docker group or use `sudo`
- If daemon not running: `sudo systemctl start docker`

---

#### Step 1.3: Verify ROCm Installation

**Command:**
```bash
rocm-smi --version
```

**Expected Output:**
```
ROCM-SMI version: <version>
ROCM-SMI-LIB version: <version>
```

**What to Check:**
- ROCm is installed
- Version is 6.0+ (required for MI300X)

**Example Output:**
```
ROCM-SMI version: 4.0.0+4179531dcd
ROCM-SMI-LIB version: 7.8.0
```

**Verify ROCm can detect GPUs:**
```bash
rocm-smi
```

**Expected Output:**
```
============================================ ROCm System Management Interface ============================================
====================================================== Concise Info ======================================================
Device  Node  IDs              Temp        Power     Partitions          SCLK    MCLK    Fan  Perf  PwrCap  VRAM%  GPU%  
              (DID,     GUID)  (Junction)  (Socket)  (Mem, Compute, ID)                                                  
==========================================================================================================================
0       1     0x<device-id>,   <temp>°C    <power>W  <partitions>       <freq>  <freq>  <fan>%  auto  <cap>W  <vram>%  <gpu>%    
==========================================================================================================================
================================================== End of ROCm SMI Log ===================================================
```

**What to Check:**
- At least one GPU device is listed
- Device ID is present (e.g., `0x74b5` for MI300X)
- Temperature and power readings are reasonable
- VRAM% shows available memory

**Get Detailed GPU Information:**
```bash
rocm-smi --showproductname
```

**Expected Output:**
```
============================ ROCm System Management Interface ============================
====================================== Product Info ======================================
GPU[0]		: Card Series: 		AMD Instinct MI300X VF
GPU[0]		: Card Model: 		0x74b5
GPU[0]		: Card Vendor: 		Advanced Micro Devices, Inc. [AMD/ATI]
GPU[0]		: Card SKU: 		M3000100
GPU[0]		: Subsystem ID: 	0x74a1
GPU[0]		: Device Rev: 		0x00
GPU[0]		: Node ID: 		1
GPU[0]		: GUID: 		<guid>
GPU[0]		: GFX Version: 		gfx942
==========================================================================================
================================== End of ROCm SMI Log ===================================
```

**What to Check:**
- Card Series shows "AMD Instinct MI300X" (or compatible model)
- GFX Version is `gfx942` or compatible (gfx940, gfx941, gfx942 for MI300X)
- Device ID matches expected values

**Troubleshooting:**
- If `rocm-smi: command not found`, ROCm is not installed. Contact CSP support or install ROCm
- If no GPUs detected, verify:
  - GPU is properly installed
  - ROCm drivers are loaded: `lsmod | grep amdgpu`
  - Check kernel messages: `dmesg | grep -i amd`
- If GPU shows 0% VRAM or errors, GPU may be in low-power state (this is often normal when idle)

---

#### Step 1.4: Verify GPU Device Nodes

**Command:**
```bash
ls -la /dev/kfd /dev/dri/
```

**Expected Output:**
```
crw-rw---- 1 root render 238, 0 <date> /dev/kfd

/dev/dri/:
total 0
drwxr-xr-x  3 root root        <size> <date> .
drwxr-xr-x 18 root root        <size> <date> ..
drwxr-xr-x  2 root root        <size> <date> by-path
crw-rw----  1 root video  226,   0 <date> card0
crw-rw----  1 root video  226,   1 <date> card1
...
crw-rw----  1 root render 226, 128 <date> renderD128
crw-rw----  1 root render 226, 129 <date> renderD129
...
```

**What to Check:**
- `/dev/kfd` exists and is a character device (starts with `c`)
- `/dev/dri/` directory exists
- Multiple `card*` devices exist (one per GPU partition)
- Multiple `renderD*` devices exist (one per render node)
- Permissions show `root render` for `/dev/kfd` and `root video` for `card*`

**Verify Device Accessibility:**
```bash
test -r /dev/kfd && echo "✓ /dev/kfd is readable" || echo "✗ /dev/kfd is NOT readable"
test -r /dev/dri/card0 && echo "✓ /dev/dri/card0 is readable" || echo "✗ /dev/dri/card0 is NOT readable"
```

**Expected Output:**
```
✓ /dev/kfd is readable
✓ /dev/dri/card0 is readable
```

**Troubleshooting:**
- If `/dev/kfd` doesn't exist:
  - ROCm may not be properly installed
  - Kernel module may not be loaded: `sudo modprobe kfd`
- If devices exist but aren't readable:
  - Check permissions: `ls -l /dev/kfd /dev/dri/card*`
  - Add user to `render` and `video` groups: `sudo usermod -aG render,video $USER`
  - Log out and back in, or use `newgrp render` and `newgrp video`

---

#### Step 1.5: Verify User Permissions

**Command:**
```bash
id
groups
```

**Expected Output:**
```
uid=<uid>(<username>) gid=<gid>(<group>) groups=<gid>(<group>),<gid>(render),<gid>(video),...
```

**What to Check:**
- User is in `render` group (for `/dev/kfd` access)
- User is in `video` group (for `/dev/dri/card*` access)
- If running as root, these checks may not apply (root has access)

**Example Output (non-root user):**
```
uid=1000(user) gid=1000(user) groups=1000(user),27(sudo),107(render),44(video)
```

**If Groups Are Missing:**
```bash
# Add user to required groups
sudo usermod -aG render,video $USER

# Verify (requires new login session)
groups
```

**Troubleshooting:**
- If not in required groups, add them and start a new shell session
- If running as root, permissions should be fine, but verify device access

---

#### Step 1.6: Verify System Resources

**Check Available Memory:**
```bash
free -h
```

**Expected Output:**
```
               total        used        free      shared  buff/cache   available
Mem:           <size>G      <used>G     <free>G     <shared>G     <cache>G     <avail>G
Swap:          <size>G      <used>G     <free>G
```

**What to Check:**
- At least 64GB RAM available (128GB+ recommended for 32B models)
- Sufficient free memory for model loading

**Example Output:**
```
               total        used        free      shared  buff/cache   available
Mem:           235Gi        15Gi       110Gi       4.6Mi       112Gi       220Gi
Swap:             0B          0B          0B
```

**Check Disk Space:**
```bash
df -h /
```

**Expected Output:**
```
Filesystem      Size  Used Avail Use% Mounted on
<fs>            <size>G  <used>G  <avail>G  <use>% /
```

**What to Check:**
- At least 100GB free space (200GB+ recommended)
- Model weights can be 60GB+ for large models

**Example Output:**
```
/dev/vda1       697G  181G  516G  26% /
```

**Troubleshooting:**
- If memory is insufficient, consider smaller models or increase node size
- If disk space is low, clean up or request larger storage

---

#### Step 1.7: Verify Network Connectivity

**Command:**
```bash
ping -c 3 8.8.8.8
```

**Expected Output:**
```
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=... time=... ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=... time=... ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=... time=... ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time ...
```

**What to Check:**
- Internet connectivity is working
- Required for downloading model weights and container images

**Test Docker Hub Access:**
```bash
curl -I https://hub.docker.com
```

**Expected Output:**
```
HTTP/2 200 
...
```

**Troubleshooting:**
- If ping fails, check network configuration
- If Docker Hub is blocked, configure registry mirrors or use alternative registries
- Some CSPs require proxy configuration

---

#### Step 1.8: Verify Port Availability

**Command:**
```bash
netstat -tuln | grep 8000 || ss -tuln | grep 8000
```

**Expected Output:**
```
(No output - port is free)
```

**OR if port is in use:**
```
tcp        0      0 0.0.0.0:8000            0.0.0.0:*               LISTEN
```

**What to Check:**
- Port 8000 is available (or choose a different port)
- If port is in use, either stop the service or use `-p <different-port>:8000`

**Troubleshooting:**
- If port is in use, find the process: `sudo lsof -i :8000` or `sudo netstat -tulpn | grep 8000`
- Stop the conflicting service or use a different port

---

#### Step 1.9: Final Pre-Deployment Checklist

Before proceeding to deployment, verify all items:

- [ ] Operating system is Linux x86_64
- [ ] Docker is installed and working (`docker --version` succeeds)
- [ ] Docker daemon is running (`docker ps` works)
- [ ] ROCm is installed (`rocm-smi --version` succeeds)
- [ ] GPU is detected (`rocm-smi` shows at least one GPU)
- [ ] GPU model is compatible (MI300X, MI325X, or similar)
- [ ] `/dev/kfd` exists and is readable
- [ ] `/dev/dri/card*` devices exist and are readable
- [ ] User has `render` and `video` group membership (or running as root)
- [ ] Sufficient RAM available (64GB+ recommended)
- [ ] Sufficient disk space (100GB+ free)
- [ ] Network connectivity works
- [ ] Port 8000 is available (or alternative port chosen)

**If all checks pass, proceed to Step 2: AIM Container Deployment.**

### 2. AIM Container Deployment

#### Step 2.1: Clone AIM Deployment Repository

**Command:**
```bash
cd ~
git clone https://github.com/amd-enterprise-ai/aim-deploy.git
cd aim-deploy
```

**Expected Output:**
```
Cloning into 'aim-deploy'...
remote: Enumerating objects: <n>, done.
remote: Counting objects: 100% (<n>/<n>), done.
remote: Compressing objects: 100% (<n>/<n>), done.
remote: Total <n> (delta <n>), reused <n> (delta <n>), pack-reused <n>
Receiving objects: 100% (<n>/<n>), <size> KiB | <speed> MiB/s, done.
Resolving deltas: 100% (<n>/<n>), done.
```

**What to Check:**
- Repository cloned successfully
- No error messages

**Verify Repository Contents:**
```bash
ls -la aim-deploy/
```

**Expected Output:**
```
total <size>
drwxr-xr-x  <n> root root  <size> <date> .
drwxr-xr-x  <n> root root  <size> <date> ..
drwxr-xr-x  <n> root root  <size> <date> .git
-rw-r--r--  <n> root root  <size> <date> .gitignore
-rw-r--r--  <n> root root  <size> <date> LICENSE
-rw-r--r--  <n> root root  <size> <date> README.md
drwxr-xr-x  <n> root root  <size> <date> k8s
drwxr-xr-x  <n> root root  <size> <date> kserve
```

**Troubleshooting:**
- If `git: command not found`, install git: `sudo apt-get install git` (Ubuntu/Debian)
- If clone fails, check network connectivity and GitHub access

---

#### Step 2.2: Pull AIM Container Image

**Command:**
```bash
docker pull amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
```

**Expected Output:**
```
0.8.4: Pulling from amdenterpriseai/aim-qwen-qwen3-32b
<layer-id>: Pulling fs layer
<layer-id>: Pull complete
...
Digest: sha256:<hash>
Status: Downloaded newer image for amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
docker.io/amdenterpriseai/aim-qwen-qwen3-32b:0.8.4
```

**What to Check:**
- Image pull completes without errors
- Final status shows "Downloaded newer image" or "Image is up to date"
- Digest is shown (for verification)

**Verify Image is Available:**
```bash
docker images | grep aim-qwen
```

**Expected Output:**
```
amdenterpriseai/aim-qwen-qwen3-32b   0.8.4    <image-id>   <size>   <time-ago>
```

**What to Check:**
- Image is listed with correct tag
- Image size is reasonable (several GB)

**Troubleshooting:**
- If pull fails with "unauthorized", check Docker Hub access
- If pull is slow, check network bandwidth
- If pull fails with "no space", free up disk space: `docker system prune`

---

#### Step 2.3: Test AIM Container (Dry Run)

**Before deploying, test that AIM can detect your hardware:**

**Command:**
```bash
docker run --rm --device=/dev/kfd --device=/dev/dri \
  --security-opt seccomp=unconfined \
  --group-add video \
  --ipc=host \
  --shm-size=8g \
  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 list-profiles
```

**Expected Output:**
```
2025-<date> - aim_runtime.gpu_detector - INFO - Detected <n> AMD GPU(s)
2025-<date> - aim_runtime.gpu_detector - INFO - GPU <device-id>: {
  "device_id": "<id>",
  "model": "MI300X",
  "vram_total": <size>,
  "vram_used": <size>,
  "vram_free": <size>,
  ...
}
...
AIM Profile Compatibility Report
====================================================================================================
...
| Profile                                 | GPU    | Precision | Engine | TP | Metric     | Type        | Priority | Manual Only | Compatibility   |
|-----------------------------------------|--------|-----------|--------|----|------------|-------------|----------|-------------|-----------------|
| vllm-mi300x-fp16-tp1-latency            | MI300X | fp16      | vllm   | 1  | latency    | optimized   | 2        | No          | compatible      |
...
```

**What to Check:**
- GPU is detected ("Detected <n> AMD GPU(s)")
- GPU model is identified correctly (MI300X, MI325X, etc.)
- VRAM information is shown
- At least one profile shows "compatible" status
- No critical errors in output

**Troubleshooting:**
- If "Detected 0 AMD GPU(s)", verify GPU device access in container
- If GPU model is not recognized, check if it's a supported model
- If profiles show "gpu_mismatch", verify GPU model compatibility

---

#### Step 2.4: Deploy AIM Container

**Command:**
```bash
docker run -d --name aim-qwen3-32b \
  --device=/dev/kfd \
  --device=/dev/dri \
  --security-opt seccomp=unconfined \
  --group-add video \
  --ipc=host \
  --shm-size=8g \
  -p 8000:8000 \
  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 serve
```

**Expected Output:**
```
<container-id>
```

**What to Check:**
- Container ID is returned (long hexadecimal string)
- No error messages

**Verify Container is Running:**
```bash
docker ps | grep aim-qwen3-32b
```

**Expected Output:**
```
<container-id>   amdenterpriseai/aim-qwen-qwen3-32b:0.8.4   "./entrypoint.py ser…"   <time> ago   Up <time>   0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp   aim-qwen3-32b
```

**What to Check:**
- Container is listed
- Status shows "Up <time>"
- Port mapping shows `0.0.0.0:8000->8000/tcp`

**Troubleshooting:**
- If container exits immediately, check logs: `docker logs aim-qwen3-32b`
- If port binding fails, check if port 8000 is already in use
- If container fails to start, verify all device paths exist

---

#### Step 2.5: Monitor Container Startup

**Check Container Logs:**
```bash
docker logs -f aim-qwen3-32b
```

**Expected Output (Initial):**
```
2025-<date> - aim_runtime.gpu_detector - INFO - Detected 1 AMD GPU(s)
2025-<date> - aim_runtime.profile_selector - INFO - Selected profile: .../vllm-mi300x-fp16-tp1-latency.yaml
2025-<date> - aim_runtime.aim_runtime - INFO - --- Setting Environment Variables ---
...
INFO 11-26 <time> [api_server.py:1885] vLLM API server version <version>
INFO 11-26 <time> [__init__.py:742] Resolved architecture: Qwen3ForCausalLM
INFO 11-26 <time> [gpu_model_runner.py:1932] Starting to load model Qwen/Qwen3-32B...
```

**What to Check:**
- GPU detection succeeds
- Profile is selected
- vLLM API server starts
- Model loading begins

**Expected Output (During Model Loading):**
```
Loading safetensors checkpoint shards:   0% Completed | 0/17 [00:00<?, ?it/s]
Loading safetensors checkpoint shards:   6% Completed | 1/17 [00:02<00:33,  2.12s/it]
Loading safetensors checkpoint shards:  12% Completed | 2/17 [00:04<00:34,  2.29s/it]
...
```

**What to Check:**
- Model shards are loading (progress increases)
- No errors during loading

**Expected Output (When Ready):**
```
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
```

**What to Check:**
- "Application startup complete" message appears
- Server is ready to accept requests

**Troubleshooting:**
- If model download fails, check network connectivity
- If loading is very slow, verify GPU memory is sufficient
- If errors occur, check full logs: `docker logs aim-qwen3-32b 2>&1 | tail -50`

**Monitor GPU Usage During Loading:**
```bash
watch -n 2 'rocm-smi --showmemuse | grep -A 2 "GPU\[0\]"'
```

**Expected Behavior:**
- VRAM usage increases as model loads
- Eventually reaches 85-95% for 32B model on single GPU

---

#### Step 2.6: Verify Container Health

**Check Container Status:**
```bash
docker ps -a | grep aim-qwen3-32b
```

**Expected Output:**
```
<container-id>   ...   Up <time>   ...   aim-qwen3-32b
```

**What to Check:**
- Status is "Up" (not "Exited" or "Restarting")
- Uptime is reasonable

**Check Resource Usage:**
```bash
docker stats aim-qwen3-32b --no-stream
```

**Expected Output:**
```
CONTAINER ID   NAME              CPU %     MEM USAGE / LIMIT     MEM %     NET I/O   BLOCK I/O   PIDS
<id>           aim-qwen3-32b      <cpu>%    <mem>GiB / <limit>GiB   <pct>%   <net>     <block>     <n>
```

**What to Check:**
- Memory usage is reasonable (several GB)
- CPU usage may be high during model loading, then lower when idle
- Container is not using excessive resources

**Troubleshooting:**
- If container is "Exited", check exit code: `docker inspect aim-qwen3-32b | grep -A 5 State`
- If container is "Restarting", check logs for errors
- If memory usage is very high, verify model size matches available resources

### 3. AIM Features Explored

#### Profile Selection
- AIM automatically detected the MI300X GPU
- Selected optimal profile: `vllm-mi300x-fp16-tp1-latency` (optimized, FP16 precision)
- Found 3 compatible profiles for the hardware configuration
- Total of 24 profiles analyzed (16 for MI300X, 8 for MI325X)

#### Hardware Detection
- Automatically detected 1 AMD GPU
- Identified GPU model: MI300X
- Detected VRAM: 196GB total, 196GB free at startup
- Configured for gfx942 architecture

#### Environment Variables
AIM automatically set the following optimization variables:
- `GPU_ARCHS=gfx942`
- `HSA_NO_SCRATCH_RECLAIM=1`
- `VLLM_USE_AITER_TRITON_ROPE=1`
- `VLLM_ROCM_USE_AITER=1`
- `VLLM_ROCM_USE_AITER_RMSNORM=1`

### 4. Model Loading
- Model: Qwen/Qwen3-32B (32B parameters)
- Download time: ~14.7 seconds
- Loading: 17 checkpoint shards loaded successfully
- GPU memory usage: 91% VRAM allocated during operation
- Total startup time: ~2.5 minutes

### 5. Inference Testing

**Quick Start:** For automated validation, use the provided script:
```bash
chmod +x validate-aim-inference.sh
./validate-aim-inference.sh
```

This script automates Steps 5.1-5.8 and provides fix instructions for any failed checks.

**Manual Validation:** This section provides step-by-step validation of inference functionality. **Perform each check in order and verify the expected outputs before proceeding.**

#### Step 5.1: Verify API Server is Ready

**Wait for "Application startup complete" in logs:**
```bash
docker logs aim-qwen3-32b 2>&1 | grep -i "application startup complete"
```

**Expected Output:**
```
INFO:     Application startup complete.
```

**What to Check:**
- Message appears in logs
- No errors after this message

**Alternative: Check if server responds:**
```bash
timeout 5 curl -s http://localhost:8000/health || echo "Server not ready yet"
```

**Expected Output (when ready):**
```
(May return empty or JSON response)
```

**OR (if not ready):**
```
Server not ready yet
```

**Troubleshooting:**
- If server doesn't become ready after 5-10 minutes, check logs for errors
- If port is not accessible, verify port mapping: `docker ps | grep 8000`

---

#### Step 5.2: Test Health Endpoint

**Command:**
```bash
curl -v http://localhost:8000/health
```

**Expected Output:**
```
*   Trying 127.0.0.1:8000...
* Connected to localhost (127.0.0.1) port 8000
< HTTP/1.1 200 OK
< ...
```

**What to Check:**
- HTTP status is 200 OK
- Connection succeeds

**Troubleshooting:**
- If connection refused, verify container is running and port is mapped
- If 404, endpoint may not be available (this is okay, try `/v1/models` instead)

---

#### Step 5.3: List Available Models

**Command:**
```bash
curl -s http://localhost:8000/v1/models | python3 -m json.tool
```

**Expected Output:**
```json
{
    "object": "list",
    "data": [
        {
            "id": "Qwen/Qwen3-32B",
            "object": "model",
            "created": <timestamp>,
            "owned_by": "vllm",
            "root": "Qwen/Qwen3-32B",
            "parent": null,
            "max_model_len": 32768,
            "permission": [...]
        }
    ]
}
```

**What to Check:**
- JSON response is valid
- Model ID matches expected model (Qwen/Qwen3-32B)
- `max_model_len` is shown (32768 for Qwen3-32B)

**Alternative (without python):**
```bash
curl -s http://localhost:8000/v1/models
```

**Expected Output:**
```
{"object":"list","data":[{"id":"Qwen/Qwen3-32B",...}]}
```

**Troubleshooting:**
- If connection fails, check container status: `docker ps | grep aim`
- If JSON is malformed, server may still be starting
- If model ID doesn't match, verify correct container image was used

---

#### Step 5.4: Test Chat Completions Endpoint

**Important Note for Qwen3:** Qwen3-32B uses a reasoning/thinking process before generating responses. This can make it appear slow or unresponsive. Use **streaming** to see progress, and set higher `max_tokens` to allow complete thinking + response.

##### Option 1: Streaming Response (Recommended)

**Command (with streaming - recommended token allocation):**
```bash
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-32B",
    "messages": [
      {"role": "user", "content": "What are the key advantages of using GPUs for AI inference, and how do they compare to CPUs?"}
    ],
    "max_tokens": 2048,
    "stream": true,
    "temperature": 0.7
  }'
```

**Note:** Using `-s` flag to suppress curl progress output. Using `max_tokens: 2048` to ensure thinking completes and response is generated.

**Expected Output (Raw Streaming - use `-s` flag to suppress curl progress):**
```
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"Qwen/Qwen3-32B","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"Qwen/Qwen3-32B","choices":[{"index":0,"delta":{"reasoning_content":"\n"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"Qwen/Qwen3-32B","choices":[{"index":0,"delta":{"reasoning_content":"Okay"},"finish_reason":null}]}

... (thinking process continues with reasoning_content) ...

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"Qwen/Qwen3-32B","choices":[{"index":0,"delta":{"content":"\n\n"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":...,"model":"Qwen/Qwen3-32B","choices":[{"index":0,"delta":{"content":"GPUs"},"finish_reason":null}]}

... (response continues with content) ...

data: [DONE]
```

**Important:** Qwen3 uses two fields:
- `reasoning_content`: The thinking/reasoning process (appears first)
- `content`: The final response (appears after thinking)

**Note:** Without the `-s` flag, curl shows progress output that can interfere with parsing. Always use `curl -s` for streaming responses.

**What to Check:**
- Stream starts immediately (shows progress)
- Thinking process is visible (may include `<thinking>` tags or reasoning text)
- Final response follows after thinking
- Stream ends with `[DONE]`

**Process Streaming Response (Python example - shows both thinking and response):**
```bash
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-32B",
    "messages": [{"role": "user", "content": "What are the key advantages of using GPUs for AI inference, and how do they compare to CPUs?"}],
    "max_tokens": 2048,
    "stream": true
  }' | python3 -c "
import sys, json
for line in sys.stdin:
    if line.startswith('data: '):
        data = line[6:].strip()
        if data == '[DONE]':
            break
        try:
            chunk = json.loads(data)
            if 'choices' in chunk and len(chunk['choices']) > 0:
                delta = chunk['choices'][0].get('delta', {})
                # Qwen3 uses reasoning_content for thinking, content for response
                reasoning = delta.get('reasoning_content', '')
                content = delta.get('content', '')
                if reasoning:
                    print(reasoning, end='', flush=True)
                if content:
                    print(content, end='', flush=True)
        except:
            pass
print()  # Newline at end
"
```

**Process Streaming Response (shows only final response, filters thinking):**
```bash
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-32B",
    "messages": [{"role": "user", "content": "What are the key advantages of using GPUs for AI inference, and how do they compare to CPUs?"}],
    "max_tokens": 2048,
    "stream": true
  }' | python3 -c "
import sys, json
for line in sys.stdin:
    if line.startswith('data: '):
        data = line[6:].strip()
        if data == '[DONE]':
            break
        try:
            chunk = json.loads(data)
            if 'choices' in chunk and len(chunk['choices']) > 0:
                delta = chunk['choices'][0].get('delta', {})
                # Only show content (final response), skip reasoning_content
                content = delta.get('content', '')
                if content:
                    print(content, end='', flush=True)
        except:
            pass
print()  # Newline at end
"
```

**Note:** The `-s` flag in curl suppresses progress output. Without it, you'll see curl's progress statistics mixed with the stream.

**Expected Behavior:**
- Text appears incrementally as it's generated
- Thinking process may be visible first
- Final response follows
- User sees progress, reducing perception of slowness

##### Option 2: Non-Streaming Response (Higher Token Limit)

**Command (non-streaming with higher token limit):**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-32B",
    "messages": [
      {"role": "user", "content": "What are the key advantages of using GPUs for AI inference, and how do they compare to CPUs?"}
    ],
    "max_tokens": 2048,
    "temperature": 0.7
  }'
```

**Note:** Using `max_tokens: 2048` ensures thinking completes before generating response. For very complex questions, use 4096.

**Expected Output:**
```json
{
  "id": "chatcmpl-<id>",
  "object": "chat.completion",
  "created": <timestamp>,
  "model": "Qwen/Qwen3-32B",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "<thinking process>...<final response>"
      },
      "finish_reason": "stop" or "length"
    }
  ],
  "usage": {
    "prompt_tokens": <n>,
    "completion_tokens": <n>,
    "total_tokens": <n>
  }
}
```

**What to Check:**
- Response is valid JSON
- `model` field shows "Qwen/Qwen3-32B"
- `choices[0].message.content` contains text (may include thinking + response)
- `usage.completion_tokens` shows total tokens used (thinking + response)
- `finish_reason` is "stop" (complete) or "length" (truncated - increase max_tokens)

**Token Allocation Guidelines:**

**Important:** Qwen3's `max_tokens` applies to **total output** (thinking + response). If thinking uses all tokens, no response is generated. Allocate generously:

- **Short responses**: `max_tokens: 512` (200-300 thinking + 200-300 response)
- **Medium responses**: `max_tokens: 1024` (400-500 thinking + 500-600 response) - **Recommended minimum**
- **Long responses**: `max_tokens: 2048` (800-1000 thinking + 1000-1200 response) - **Recommended for complex questions**
- **Very long**: `max_tokens: 4096` (1500-2000 thinking + 2000-2500 response)

**Rule of thumb:** Allocate 2-3x more tokens than you think you need. Qwen3's thinking can be extensive, especially for complex questions.

**Extract just the final response (filter thinking):**
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-32B",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "max_tokens": 256
  }' | python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data['choices'][0]['message']['content']
# Remove thinking tags if present
content = content.replace('<thinking>', '').replace('</thinking>', '')
# Or extract text after thinking markers
print(content.strip())
"
```

**Expected Output:**
```
Hello! How can I assist you today?
```

##### Understanding Qwen3's Thinking Process

Qwen3 uses a reasoning process that:
1. **Thinks first** (internal reasoning, may be visible in output)
2. **Then responds** (final answer to user)

This is why:
- Responses may seem slow initially (model is thinking)
- Higher `max_tokens` is needed (thinking + response)
- Streaming is recommended (shows progress)

**Troubleshooting:**
- **If you see curl progress output but no content**: Use `curl -s` flag to suppress progress output. The script needs clean JSON lines starting with `data: `.
- **If request appears to hang**: This is normal - Qwen3 is thinking. Use streaming to see progress (you'll see `reasoning_content` first).
- **If no content appears in stream**: Check that script handles both `reasoning_content` and `content` fields (see examples above).
- **If only thinking, no response (finish_reason: "length")**: **This is the most common issue!** Increase `max_tokens` to 2048 or 4096. Thinking used all tokens, leaving none for response.
- **If response is cut off**: Increase `max_tokens` further - both thinking and response need tokens
- **If thinking seems incomplete**: Increase `max_tokens` - Qwen3 needs enough tokens to complete its reasoning
- **If request times out**: Check `max_tokens` isn't too high, or increase timeout
- **If 500 error**: Check container logs: `docker logs aim-qwen3-32b | tail -20`
- **If "model not found"**: Verify model loaded correctly in logs

**Key Fix for Incomplete Output:**
If you see thinking but no response, or thinking cuts off mid-sentence:
1. Check `finish_reason` in the response - if it's "length", tokens ran out
2. Increase `max_tokens` to at least 2048 (4096 for complex questions)
3. Remember: `max_tokens` = thinking tokens + response tokens
4. Qwen3's thinking can be 500-1000+ tokens for complex questions

**Recommended Settings for Qwen3:**
```json
{
  "model": "Qwen/Qwen3-32B",
  "messages": [...],
  "max_tokens": 2048,
  "stream": true,
  "temperature": 0.7,
  "top_p": 0.9
}
```

**Why 2048 tokens?**
- Qwen3's thinking process can use 500-1000+ tokens for complex questions
- Response typically needs 500-1500 tokens
- 2048 ensures thinking completes AND response is generated
- If you see `finish_reason: "length"` with only thinking, increase to 4096

---

#### Step 5.5: Test Text Completions Endpoint

**Command:**
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "The AMD Inference Microservice (AIM) is",
    "max_tokens": 50
  }'
```

**Expected Output:**
```json
{
  "id": "cmpl-<id>",
  "object": "text_completion",
  "created": <timestamp>,
  "model": "Qwen/Qwen3-32B",
  "choices": [
    {
      "text": "<generated text>",
      "index": 0,
      "finish_reason": "length" or "stop",
      "logprobs": null
    }
  ],
  "usage": {
    "prompt_tokens": <n>,
    "completion_tokens": <n>,
    "total_tokens": <n>
  }
}
```

**What to Check:**
- Response is valid JSON
- `choices[0].text` contains generated continuation
- Token usage is shown

**Troubleshooting:**
- Similar to chat completions troubleshooting
- Some models may prefer chat format over completions

---

#### Step 5.6: Monitor GPU Usage During Inference

**While running inference, monitor GPU:**
```bash
rocm-smi --showmemuse --showuse
```

**Expected Output:**
```
=================================== % time GPU is busy ===================================
GPU[0]		: GPU use (%): <percentage>
GPU[0]		: GFX Activity: <value>
==========================================================================================
=================================== Current Memory Use ===================================
GPU[0]		: GPU Memory Allocated (VRAM%): <percentage>
GPU[0]		: GPU Memory Read/Write Activity (%): <percentage>
```

**What to Check:**
- GPU use increases during inference (may reach 50-100%)
- VRAM usage is high (85-95% for 32B model)
- Memory activity increases during processing

**Expected Behavior:**
- GPU use: 0-10% when idle, 50-100% during inference
- VRAM: 85-95% allocated for loaded model
- Memory activity: Increases during token generation

**Troubleshooting:**
- If GPU use stays at 0% during inference, GPU may not be utilized (check logs)
- If VRAM is very low, model may not have loaded correctly
- If memory activity is always 0%, check if inference is actually running

---

#### Step 5.7: Performance Validation

**Test Response Time:**
```bash
time curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello"}], "max_tokens": 10}' \
  -o /dev/null -s
```

**Expected Output:**
```
real	0m<seconds>.<ms>s
user	0m0.00Xs
sys	0m0.00Xs
```

**What to Check:**
- First request may take 10-60 seconds (cold start)
- Subsequent requests should be faster (5-30 seconds depending on length)
- Response time is reasonable for model size

**Test Multiple Requests:**
```bash
for i in {1..3}; do
  echo "Request $i:"
  time curl -X POST http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"messages": [{"role": "user", "content": "Count to 5."}], "max_tokens": 20}' \
    -o /dev/null -s
  echo ""
done
```

**Expected Behavior:**
- First request: Slower (may include initialization)
- Subsequent requests: Faster and more consistent

**Troubleshooting:**
- If all requests are very slow, check GPU utilization
- If requests fail intermittently, check container resource limits
- If response times are inconsistent, check for resource contention

---

#### Step 5.8: Final Validation Checklist

Before considering deployment complete, verify:

- [ ] Container is running: `docker ps | grep aim-qwen3-32b` shows "Up"
- [ ] API server is ready: Logs show "Application startup complete"
- [ ] Health endpoint responds (if available): `curl http://localhost:8000/health`
- [ ] Models endpoint works: `curl http://localhost:8000/v1/models` returns JSON
- [ ] Chat completions work: Request returns valid response with generated text
- [ ] GPU is utilized: `rocm-smi` shows GPU activity during inference
- [ ] VRAM is allocated: `rocm-smi --showmemuse` shows high VRAM usage
- [ ] Response times are acceptable: Requests complete in reasonable time
- [ ] No errors in logs: `docker logs aim-qwen3-32b` shows no critical errors

**If all checks pass, your AIM deployment is fully operational!**

## Key AIM Capabilities Demonstrated

### 1. Intelligent Profile Selection
- Automatically matches hardware capabilities with optimal performance profiles
- Supports multiple precision formats (FP8, FP16)
- Optimizes for latency or throughput based on configuration

### 2. Hardware-Aware Optimization
- Detects GPU model and architecture
- Configures vLLM with optimal parameters for MI300X
- Enables ROCm-specific optimizations (Aiter, Triton kernels)

### 3. OpenAI-Compatible API
- Full OpenAI API compatibility
- Supports chat completions, completions, embeddings
- Standard REST endpoints for easy integration

### 4. Model Features
- **Model**: Qwen3-32B with reasoning capabilities
- **Max Context Length**: 32,768 tokens
- **Precision**: FP16 (float16)
- **Tensor Parallelism**: 1 (single GPU)
- **Max Sequences**: 512 concurrent
- **Reasoning Parser**: Qwen3

## Container Configuration

### Docker Run Command
```bash
docker run -d --name aim-qwen3-32b \
  --device=/dev/kfd \
  --device=/dev/dri \
  --security-opt seccomp=unconfined \
  --group-add video \
  --ipc=host \
  --shm-size=8g \
  -p 8000:8000 \
  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 serve
```

### Key Docker Options
- `--device=/dev/kfd --device=/dev/dri`: GPU device access
- `--security-opt seccomp=unconfined`: Required for ROCm
- `--group-add video`: GPU access permissions
- `--ipc=host`: Shared memory for multi-process communication
- `--shm-size=8g`: Shared memory for model weights
- `-p 8000:8000`: API server port mapping

## AIM Commands Available

1. **`list-profiles`**: List all available performance profiles
2. **`dry-run`**: Preview selected profile and generated command
3. **`serve`**: Start the inference server
4. **`download-to-cache`**: Pre-download models to cache

## Performance Characteristics

- **Model Loading**: ~2.5 minutes for 32B model
- **GPU Memory**: 91% utilization during inference
- **API Response**: Sub-minute response times for typical queries
- **Concurrent Requests**: Supports up to 512 concurrent sequences

## Next Steps (Optional)

### Kubernetes/KServe Deployment
The repository includes comprehensive Kubernetes deployment examples:
- Location: `/root/aim-deploy/kserve/`
- Includes KServe integration
- Supports autoscaling with KEDA
- Observability with OpenTelemetry, Grafana, Prometheus

### Additional Models
Other AIM container images available:
- `amdenterpriseai/aim-meta-llama-llama-3-1-8b-instruct:0.8.4`
- `amdenterpriseai/aim-base:0.8`

## References

- **Blog Post**: https://rocm.blogs.amd.com/artificial-intelligence/enterprise-ai-aims/README.html
- **Deployment Repository**: https://github.com/amd-enterprise-ai/aim-deploy
- **AIM Catalog**: https://enterprise-ai.docs.amd.com/en/latest/aims/catalog/models.html

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue: Container Exits Immediately

**Symptoms:**
- Container status shows "Exited" shortly after starting
- `docker ps -a` shows container with exit code

**Diagnosis:**
```bash
docker logs aim-qwen3-32b
docker inspect aim-qwen3-32b | grep -A 10 State
```

**Common Causes:**
1. **GPU device access denied**
   - **Solution**: Verify device permissions: `ls -l /dev/kfd /dev/dri/card*`
   - Add user to groups: `sudo usermod -aG render,video $USER`
   - Or run container as root (if appropriate)

2. **ROCm not properly installed**
   - **Solution**: Verify ROCm: `rocm-smi --version`
   - Check kernel modules: `lsmod | grep amdgpu`

3. **Insufficient shared memory**
   - **Solution**: Increase shm-size: `--shm-size=16g` (instead of 8g)

4. **Port already in use**
   - **Solution**: Use different port: `-p 8001:8000` or find and stop conflicting service

---

#### Issue: GPU Not Detected in Container

**Symptoms:**
- Logs show "Detected 0 AMD GPU(s)"
- Profile selection fails

**Diagnosis:**
```bash
docker run --rm --device=/dev/kfd --device=/dev/dri \
  --security-opt seccomp=unconfined --group-add video \
  --ipc=host --shm-size=8g \
  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 list-profiles
```

**Solutions:**
1. **Verify device mapping**
   ```bash
   # Check devices exist on host
   ls -la /dev/kfd /dev/dri/card0
   
   # Test device access in container
   docker run --rm --device=/dev/kfd --device=/dev/dri \
     --security-opt seccomp=unconfined --group-add video \
     --ipc=host \
     amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 \
     bash -c "ls -la /dev/kfd /dev/dri/"
   ```

2. **Check ROCm in container**
   ```bash
   docker run --rm --device=/dev/kfd --device=/dev/dri \
     --security-opt seccomp=unconfined --group-add video \
     --ipc=host \
     amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 \
     bash -c "rocm-smi"
   ```

3. **Verify seccomp settings**
   - Ensure `--security-opt seccomp=unconfined` is included
   - Some systems may require additional security options

---

#### Issue: Model Loading Fails or Takes Too Long

**Symptoms:**
- Model download fails
- Loading progress stalls
- Container runs out of memory

**Diagnosis:**
```bash
docker logs aim-qwen3-32b | grep -i "error\|fail\|timeout"
docker stats aim-qwen3-32b --no-stream
rocm-smi --showmemuse
```

**Solutions:**
1. **Network issues during download**
   - Check connectivity: `ping -c 3 8.8.8.8`
   - Verify Docker Hub access: `curl -I https://hub.docker.com`
   - Some CSPs require proxy configuration

2. **Insufficient disk space**
   - Check available space: `df -h /`
   - Model weights can be 60GB+ for large models
   - Clean up: `docker system prune`

3. **Insufficient GPU memory**
   - Check VRAM: `rocm-smi --showmemuse`
   - For 32B model, need ~180GB+ VRAM
   - Consider smaller model or multi-GPU setup

4. **Memory allocation errors**
   - Increase shared memory: `--shm-size=16g` or `--shm-size=32g`
   - Check system RAM: `free -h`

---

#### Issue: API Server Not Responding

**Symptoms:**
- Container is running but API doesn't respond
- Connection refused or timeout errors

**Diagnosis:**
```bash
docker logs aim-qwen3-32b | tail -50
docker ps | grep aim-qwen3-32b
netstat -tuln | grep 8000
curl -v http://localhost:8000/health
```

**Solutions:**
1. **Server still starting**
   - Wait for "Application startup complete" in logs
   - Model loading can take 2-5 minutes for 32B model
   - Monitor logs: `docker logs -f aim-qwen3-32b`

2. **Port not mapped correctly**
   - Verify mapping: `docker ps | grep 8000`
   - Check if port is in use: `netstat -tuln | grep 8000`
   - Try different port: `-p 8001:8000`

3. **Firewall blocking**
   - Check firewall rules: `sudo iptables -L -n | grep 8000`
   - Some CSPs have security groups that need configuration

4. **Container networking issues**
   - Test from inside container: `docker exec aim-qwen3-32b curl http://localhost:8000/health`
   - If works inside but not outside, check port mapping

---

#### Issue: Inference Requests Fail or Timeout

**Symptoms:**
- API returns 500 errors
- Requests timeout
- No response generated

**Diagnosis:**
```bash
docker logs aim-qwen3-32b | tail -100
rocm-smi --showuse --showmemuse
docker stats aim-qwen3-32b --no-stream
```

**Solutions:**
1. **Model not fully loaded**
   - Wait for "Application startup complete"
   - Check model loading progress in logs

2. **GPU out of memory**
   - Check VRAM usage: `rocm-smi --showmemuse`
   - Reduce `max_tokens` in requests
   - Reduce `max-num-seqs` in profile (requires custom profile)

3. **Request format incorrect**
   - Verify JSON format: `echo '{"messages":[...]}' | python3 -m json.tool`
   - Check required fields are present
   - Ensure Content-Type header: `-H "Content-Type: application/json"`

4. **Resource exhaustion**
   - Check CPU/memory: `docker stats aim-qwen3-32b`
   - Check system resources: `top`, `free -h`
   - Restart container if needed: `docker restart aim-qwen3-32b`

---

#### Issue: Poor Performance

**Symptoms:**
- Very slow inference (minutes per request)
- Low GPU utilization
- High latency

**Diagnosis:**
```bash
rocm-smi --showuse
docker stats aim-qwen3-32b --no-stream
docker logs aim-qwen3-32b | grep -i "profile\|optimization"
```

**Solutions:**
1. **Wrong profile selected**
   - Check selected profile in logs
   - Verify it matches your GPU model
   - Try manual profile selection (advanced)

2. **GPU in low-power state**
   - Check power state: `rocm-smi --showpower`
   - Some GPUs need workload to wake up
   - First request may be slower

3. **System resource contention**
   - Check other processes using GPU: `rocm-smi`
   - Check CPU usage: `top`
   - Ensure sufficient system resources

4. **Network latency (if accessing remotely)**
   - Test locally first: `curl http://localhost:8000/...`
   - If remote access needed, consider port forwarding or load balancer

---

#### Issue: Container Keeps Restarting

**Symptoms:**
- Container status shows "Restarting"
- Exit code is non-zero
- Logs show repeated startup attempts

**Diagnosis:**
```bash
docker ps -a | grep aim-qwen3-32b
docker inspect aim-qwen3-32b | grep -A 10 RestartPolicy
docker logs aim-qwen3-32b | tail -100
```

**Solutions:**
1. **Check restart policy**
   - Default may be "always" causing restarts
   - Remove container and recreate without restart policy
   - Or set to "no": `--restart=no`

2. **Identify root cause**
   - Check exit code: `docker inspect aim-qwen3-32b | grep ExitCode`
   - Review logs for error pattern
   - Common causes: OOM, device access, configuration errors

3. **Fix underlying issue**
   - Address the root cause (see other troubleshooting sections)
   - Once fixed, container should stay running

---

### Getting Additional Help

If issues persist after trying the above solutions:

1. **Collect Diagnostic Information:**
   ```bash
   # System information
   uname -a
   docker --version
   rocm-smi --version
   
   # Container status
   docker ps -a | grep aim
   docker inspect aim-qwen3-32b
   
   # Recent logs
   docker logs aim-qwen3-32b 2>&1 | tail -200
   
   # GPU status
   rocm-smi
   rocm-smi --showmemuse --showuse
   
   # System resources
   free -h
   df -h /
   ```

2. **Check AIM Documentation:**
   - GitHub Repository: https://github.com/amd-enterprise-ai/aim-deploy
   - Open issues for known problems
   - Check release notes for version-specific issues

3. **Contact Support:**
   - For CSP-specific issues, contact your cloud provider support
   - For ROCm issues, check AMD ROCm documentation
   - For AIM-specific issues, open GitHub issue with diagnostic information

## Container Hygiene and Maintenance

This section covers best practices for managing AIM containers, cleaning up resources, and maintaining a clean Docker environment.

### Stopping AIM Containers

**Stop a specific container:**
```bash
docker stop aim-qwen3-32b
```

**Stop all running AIM containers:**
```bash
docker ps --filter "name=aim" --format "{{.Names}}" | xargs -r docker stop
```

**Stop all containers (use with caution):**
```bash
docker stop $(docker ps -q)
```

### Removing Containers

**Remove a stopped container:**
```bash
docker rm aim-qwen3-32b
```

**Remove container even if running (force):**
```bash
docker rm -f aim-qwen3-32b
```

**Remove all stopped AIM containers:**
```bash
docker ps -a --filter "name=aim" --format "{{.Names}}" | xargs -r docker rm
```

**Remove all stopped containers:**
```bash
docker container prune -f
```

### Cleaning Up Docker Resources

**Remove unused containers, networks, and images:**
```bash
docker system prune
```

**Remove all unused resources including volumes (more aggressive):**
```bash
docker system prune -a --volumes
```

**Remove only unused images:**
```bash
docker image prune -a
```

**Remove only unused volumes:**
```bash
docker volume prune
```

**Remove only unused networks:**
```bash
docker network prune
```

### Complete Cleanup Script

**Stop and remove all AIM containers:**
```bash
#!/bin/bash
# Stop all AIM containers
docker ps --filter "name=aim" --format "{{.Names}}" | xargs -r docker stop

# Remove all AIM containers
docker ps -a --filter "name=aim" --format "{{.Names}}" | xargs -r docker rm

# Optional: Remove AIM images (will need to pull again)
# docker rmi amdenterpriseai/aim-qwen-qwen3-32b:0.8.4

echo "AIM containers cleaned up"
```

### Checking Container Status

**List all containers (running and stopped):**
```bash
docker ps -a
```

**List only running containers:**
```bash
docker ps
```

**List containers by name pattern:**
```bash
docker ps -a --filter "name=aim"
```

**Check container resource usage:**
```bash
docker stats aim-qwen3-32b
```

**Check all container resource usage:**
```bash
docker stats
```

### Viewing Container Logs

**View recent logs:**
```bash
docker logs aim-qwen3-32b
```

**Follow logs in real-time:**
```bash
docker logs -f aim-qwen3-32b
```

**View last N lines:**
```bash
docker logs --tail 50 aim-qwen3-32b
```

**View logs with timestamps:**
```bash
docker logs -t aim-qwen3-32b
```

### Restarting Containers

**Restart a container:**
```bash
docker restart aim-qwen3-32b
```

**Start a stopped container:**
```bash
docker start aim-qwen3-32b
```

**Stop a running container:**
```bash
docker stop aim-qwen3-32b
```

### Managing Container Resources

**Check Docker disk usage:**
```bash
docker system df
```

**Detailed breakdown:**
```bash
docker system df -v
```

**Check specific container size:**
```bash
docker ps -s --filter "name=aim-qwen3-32b"
```

### Best Practices

1. **Regular Cleanup:**
   ```bash
   # Weekly cleanup of unused resources
   docker system prune -f
   ```

2. **Before Redeployment:**
   ```bash
   # Stop and remove old container before deploying new one
   docker stop aim-qwen3-32b
   docker rm aim-qwen3-32b
   ```

3. **Monitor Resource Usage:**
   ```bash
   # Keep an eye on disk space
   docker system df
   df -h /
   ```

4. **Preserve Important Containers:**
   ```bash
   # Tag important containers before cleanup
   docker tag amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 my-aim-backup:0.8.4
   ```

5. **Clean Up After Testing:**
   ```bash
   # Remove test containers and images
   docker ps -a --filter "name=test" --format "{{.Names}}" | xargs -r docker rm -f
   docker images --filter "dangling=true" -q | xargs -r docker rmi
   ```

### Troubleshooting Container Issues

**Container won't stop:**
```bash
# Force stop
docker kill aim-qwen3-32b

# Then remove
docker rm aim-qwen3-32b
```

**Container keeps restarting:**
```bash
# Check restart policy
docker inspect aim-qwen3-32b | grep -A 5 RestartPolicy

# Remove restart policy
docker update --restart=no aim-qwen3-32b
```

**Port already in use:**
```bash
# Find what's using the port
sudo lsof -i :8000
# Or
sudo netstat -tulpn | grep 8000

# Stop the conflicting container
docker ps | grep 8000
docker stop <container-id>
```

**Out of disk space:**
```bash
# Check usage
docker system df

# Clean up
docker system prune -a --volumes

# Check system disk
df -h /
```

**Container logs too large:**
```bash
# Truncate logs (requires container restart)
truncate -s 0 $(docker inspect --format='{{.LogPath}}' aim-qwen3-32b)

# Or configure log rotation in docker daemon
```

### Quick Reference Commands

```bash
# Stop AIM container
docker stop aim-qwen3-32b

# Remove AIM container
docker rm aim-qwen3-32b

# Stop and remove in one command
docker rm -f aim-qwen3-32b

# View container status
docker ps -a | grep aim

# View container logs
docker logs aim-qwen3-32b

# Check resource usage
docker stats aim-qwen3-32b

# Clean up unused resources
docker system prune -f

# Check disk usage
docker system df
```

## Conclusion

The AIM framework provides a streamlined way to deploy AI models on AMD Instinct GPUs with minimal configuration overhead.

This comprehensive validation guide ensures that anyone with access to a similar CSP node can verify each step of the deployment process and troubleshoot issues as they arise.
