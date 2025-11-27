# Kubernetes Deployment Quick Reference

Quick commands and reference for deploying AIM on Kubernetes.

## Quick Commands

### Deployment

```bash
# Full deployment with observability
./k8s/deploy-aim-k8s.sh --with-observability

# Basic deployment only
./k8s/deploy-aim-k8s.sh

# Manual deployment
kubectl apply -f kubernetes/
```

### Validation

```bash
# Automated validation
./scripts/validate-k8s-deployment.sh
```

# Manual checks
kubectl get pods -n aim
kubectl get svc -n aim
kubectl get hpa -n aim
```

### Testing

```bash
# Port forward
kubectl port-forward -n aim svc/aim-qwen3-32b 8000:8000

# Health check
curl http://localhost:8000/health

# Inference test
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Hello","max_tokens":10}'
```

### Observability

```bash
# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

### Scaling

```bash
# Manual scale
kubectl scale deployment aim-qwen3-32b -n aim --replicas=3

# Check HPA
kubectl get hpa -n aim
kubectl describe hpa aim-qwen3-32b-hpa -n aim
```

### Logs and Debugging

```bash
# View logs
kubectl logs -n aim -l app=aim-qwen3-32b -f

# Describe pod
kubectl describe pod -n aim -l app=aim-qwen3-32b

# Exec into pod
kubectl exec -it -n aim deployment/aim-qwen3-32b -- /bin/bash
```

### Cleanup

```bash
# Automated cleanup
./scripts/cleanup-aim-k8s.sh --with-observability
```

# Manual cleanup
kubectl delete namespace aim
kubectl delete namespace monitoring
```

## File Structure

```
.
├── kubernetes/
│   ├── namespace.yaml          # Namespace definition
│   ├── configmap.yaml          # Configuration
│   ├── serviceaccount.yaml     # RBAC
│   ├── deployment.yaml         # Main deployment
│   ├── service.yaml            # Service definition
│   ├── hpa.yaml                # Horizontal Pod Autoscaler
│   └── pdb.yaml                # Pod Disruption Budget
├── observability/
│   ├── prometheus-deployment.yaml
│   ├── grafana-deployment.yaml
│   └── grafana-dashboard.yaml
├── scripts/
│   ├── deploy-aim-k8s.sh
│   ├── validate-k8s-deployment.sh
│   └── cleanup-aim-k8s.sh
├── KUBERNETES-DEPLOYMENT.md    # Full documentation
└── kubernetes-quick-reference.md
```

## Common Issues

### Pod Pending
```bash
kubectl describe pod -n aim <pod-name>
# Check: node selector, resources, GPU availability
```

### Service Not Accessible
```bash
kubectl get endpoints -n aim
kubectl describe svc aim-qwen3-32b -n aim
```

### HPA Not Working
```bash
kubectl top pods -n aim
kubectl get deployment metrics-server -n kube-system
```

## Resource Requirements

- **Per Pod**: 1 GPU, 64Gi-200Gi RAM, 8-32 CPU cores
- **Min Cluster**: 1 GPU node with MI300X
- **Monitoring**: 2Gi RAM, 1 CPU for Prometheus; 512Mi RAM, 500m CPU for Grafana

## Configuration

Key configuration files:
- `kubernetes/configmap.yaml` - Service configuration
- `kubernetes/deployment.yaml` - Resource limits, node selectors
- `kubernetes/hpa.yaml` - Scaling thresholds

For detailed information, see [KUBERNETES-DEPLOYMENT.md](./KUBERNETES-DEPLOYMENT.md).

