# AIM Quick Reference Guide

## Container Management

### Start AIM Container
```bash
docker run -d --name aim-qwen3-32b \
  -e PYTHONUNBUFFERED=1 \
  --device=/dev/kfd --device=/dev/dri \
  --security-opt seccomp=unconfined \
  --group-add video \
  --ipc=host \
  --shm-size=8g \
  -p 8000:8000 \
  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 serve
```

### View Logs
```bash
docker logs aim-qwen3-32b
docker logs -f aim-qwen3-32b  # Follow logs
```

### Stop Container
```bash
docker stop aim-qwen3-32b
docker rm aim-qwen3-32b
```

## AIM Commands

### List Available Profiles
```bash
docker run --rm --device=/dev/kfd --device=/dev/dri \
  --security-opt seccomp=unconfined --group-add video \
  --ipc=host --shm-size=8g \
  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 list-profiles
```

### Dry Run (Preview Configuration)
```bash
docker run --rm --device=/dev/kfd --device=/dev/dri \
  --security-opt seccomp=unconfined --group-add video \
  --ipc=host --shm-size=8g \
  amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 dry-run
```

### Get Help
```bash
docker run --rm amdenterpriseai/aim-qwen-qwen3-32b:0.8.4 --help
```

## API Testing

### Check Server Health
```bash
curl http://localhost:8000/health
```

### List Available Models
```bash
curl http://localhost:8000/v1/models | python3 -m json.tool
```

### Chat Completions

**Streaming (Recommended for Qwen3 - shows progress during thinking):**
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

**Non-Streaming (with higher token limit for thinking + response):**
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

**Important Token Allocation:**
- **Qwen3's `max_tokens` = thinking tokens + response tokens**
- **Minimum recommended**: `max_tokens: 2048` (ensures thinking completes + response generated)
- **For complex questions**: `max_tokens: 4096`
- **If only thinking, no response**: Increase `max_tokens` - thinking used all tokens
- **Rule of thumb**: Allocate 2-3x more tokens than you think you need

**Process Streaming Response (shows thinking + response):**
```bash
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen3-32B", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 2048, "stream": true}' \
  | python3 -c "
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
                reasoning = delta.get('reasoning_content', '')
                content = delta.get('content', '')
                if reasoning:
                    print(reasoning, end='', flush=True)
                if content:
                    print(content, end='', flush=True)
        except:
            pass
print()
"
```

**Process Streaming Response (final response only, filters thinking):**
```bash
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen3-32B", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 2048, "stream": true}' \
  | python3 -c "
import sys, json
for line in sys.stdin:
    if line.startswith('data: '):
        data = line[6:].strip()
        if data == '[DONE]':
            break
        try:
            chunk = json.loads(data)
            if 'choices' in chunk and len(chunk['choices']) > 0:
                content = chunk['choices'][0].get('delta', {}).get('content', '')
                if content:
                    print(content, end='', flush=True)
        except:
            pass
print()
"
```

**Note:** Use `curl -s` to suppress progress output. Qwen3 streams `reasoning_content` (thinking) first, then `content` (response).

### Text Completions
```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "The future of AI is",
    "max_tokens": 50
  }'
```

## System Monitoring

### Check GPU Status
```bash
rocm-smi
rocm-smi --showmemuse
rocm-smi --showuse
```

### Check Container Status
```bash
docker ps | grep aim
docker stats aim-qwen3-32b
```

## Environment Variables

AIM automatically sets these for optimal performance:
- `GPU_ARCHS=gfx942`
- `HSA_NO_SCRATCH_RECLAIM=1`
- `VLLM_USE_AITER_TRITON_ROPE=1`
- `VLLM_ROCM_USE_AITER=1`
- `VLLM_ROCM_USE_AITER_RMSNORM=1`

## Available AIM Images

- `amdenterpriseai/aim-qwen-qwen3-32b:0.8.4` - Qwen3 32B model
- `amdenterpriseai/aim-meta-llama-llama-3-1-8b-instruct:0.8.4` - Llama 3.1 8B
- `amdenterpriseai/aim-base:0.8` - Base AIM image

## Troubleshooting

### Container won't start
- Check GPU devices: `ls -la /dev/kfd /dev/dri/`
- Verify ROCm: `rocm-smi`
- Check Docker permissions

### Model loading slowly
- First run downloads model weights (~60GB for Qwen3-32B)
- Subsequent runs use cached weights
- Check network connection for model download

### API not responding
- Check container logs: `docker logs aim-qwen3-32b`
- Verify port mapping: `docker ps | grep 8000`
- Wait for "Application startup complete" in logs

### Qwen3 appears slow or unresponsive
- **This is normal** - Qwen3 uses a thinking/reasoning process
- Use **streaming** (`"stream": true`) to see progress
- **Critical**: Increase `max_tokens` to **2048 minimum** (4096 for complex questions)
- **If only thinking, no response**: `max_tokens` too low - thinking used all tokens
- **If thinking cuts off**: Increase `max_tokens` - need enough for complete reasoning
- First response may take 30-60 seconds (model is thinking)
- Subsequent responses are faster
- Remember: `max_tokens` = thinking tokens + response tokens (both need allocation)

