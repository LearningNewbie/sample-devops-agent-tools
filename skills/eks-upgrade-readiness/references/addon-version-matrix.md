# EKS Addon Version Compatibility Matrix

This reference shows recommended addon versions per EKS Kubernetes version.
Always verify with `aws eks describe-addon-versions` for the latest data.

## Core Addons

| EKS Version | kube-proxy | vpc-cni | coredns | aws-ebs-csi-driver |
|-------------|------------|---------|---------|-------------------|
| 1.32 | v1.32.x | v1.19+ | v1.12+ | v1.38+ |
| 1.31 | v1.31.x | v1.18+ | v1.11+ | v1.35+ |
| 1.30 | v1.30.x | v1.18+ | v1.11+ | v1.33+ |
| 1.29 | v1.29.x | v1.16+ | v1.11+ | v1.28+ |
| 1.28 | v1.28.x | v1.15+ | v1.10+ | v1.25+ |

## Addon Upgrade Rules

### kube-proxy
- MUST match the control plane minor version (e.g., CP 1.31 → kube-proxy v1.31.x)
- Upgrade immediately after control plane upgrade completes
- Backward compatible within one minor version during upgrade window

### vpc-cni (amazon-vpc-cni-k8s)
- Generally backward compatible across 2-3 minor versions
- New features (prefix delegation, Security Groups for Pods, network policy)
  may require specific minimum versions
- Safe to run a newer vpc-cni on an older control plane

### coredns
- Backward compatible across multiple minor versions
- New EKS versions may require minimum coredns for new features
- Check `coredns:coredns/corefile-migration` for Corefile compatibility

### aws-ebs-csi-driver
- Version constraints driven by CSI spec version and sidecar compatibility
- Newer versions add volume snapshot, resize, and topology awareness features
- Check for deprecation of `kubernetes.io/aws-ebs` in-tree provisioner

## How to Check Compatibility

```bash
# List available versions for an addon on target EKS version
aws eks describe-addon-versions \
  --addon-name vpc-cni \
  --kubernetes-version 1.31 \
  --query 'addons[0].addonVersions[*].{version:addonVersion,default:compatibilities[0].defaultVersion}' \
  --output table

# Check current addon versions on a cluster
aws eks list-addons --cluster-name <cluster> --output text
for addon in $(aws eks list-addons --cluster-name <cluster> --output text --query 'addons[]'); do
  echo "$addon: $(aws eks describe-addon --cluster-name <cluster> --addon-name $addon --query 'addon.addonVersion' --output text)"
done
```

## Self-Managed Addons

If addons are deployed via Helm or manifests (not EKS managed):
- Check the addon's GitHub release notes for Kubernetes version support
- Karpenter: check `compatibility` in release notes
- AWS Load Balancer Controller: check `chart/values.yaml` for version constraints
- External DNS: generally version-agnostic but check release notes
- Cert Manager: check supported K8s versions in release matrix

## Upgrade Order

1. Control plane (always first, cannot be rolled back)
2. kube-proxy (must match CP version)
3. vpc-cni (backward compatible, safe to delay briefly)
4. coredns (backward compatible, safe to delay briefly)
5. aws-ebs-csi-driver / aws-efs-csi-driver
6. Other managed addons (adot, guardduty-agent, etc.)
7. Self-managed addons (via Helm upgrade or manifest apply)
