---
name: eks-upgrade-readiness
description: Use this skill when a user asks to assess, plan, or validate an
  Amazon EKS cluster upgrade. Activate when you see requests mentioning
  "EKS upgrade", "Kubernetes version upgrade", "upgrade readiness",
  "upgrade plan", "pre-upgrade check", "version skew", "deprecated API",
  "addon compatibility", "node group upgrade", "control plane upgrade",
  "EKS end of support", "EKS extended support", "Karpenter drift",
  "kubelet version skew", or "blue-green cluster migration". This skill
  performs a comprehensive pre-upgrade assessment aligned with the AWS EKS
  Best Practices Guide covering infrastructure prerequisites, API
  deprecations, addon compatibility, node group readiness, Karpenter and
  Cluster Autoscaler compatibility, PDB and topology spread validation,
  capacity planning, and Fargate considerations — then produces a
  prioritized upgrade plan with rollback gates. Do NOT use for ECS,
  general EKS troubleshooting unrelated to version upgrades, or EKS
  Anywhere/Outpost clusters.
metadata:
  author: LearningNewbie
  version: "1.1.0"
  aws-devops-agent-skills.agent-types: "Chat tasks, Evaluation"
  aws-devops-agent-skills.aws-services: "Amazon EKS"
  aws-devops-agent-skills.technical-domains: "Containers"
---

# EKS Upgrade Readiness

Assess and plan Amazon EKS cluster upgrades with comprehensive pre-upgrade
validation aligned with the [EKS Best Practices Guide](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html).

## When to Use

Activate this skill when the user asks to:
- Check if an EKS cluster is ready to upgrade
- Plan an EKS version upgrade (control plane, node groups, or both)
- Identify deprecated Kubernetes APIs before upgrading
- Validate addon compatibility with a target version
- Assess node group upgrade strategy and capacity requirements
- Review Pod Disruption Budgets or topology spread for upgrade safety
- Understand EKS end-of-support, extended support, or auto-upgrade implications
- Evaluate Karpenter Drift or node expiry upgrade behavior
- Compare in-place vs blue-green upgrade strategies
- Create an upgrade runbook or checklist

## Critical Warnings

- **This skill is read-only.** All commands are `describe*`, `list*`, `get*`.
  The upgrade itself is a recommendation for the operator — the agent does NOT
  execute `update-cluster-version`, `update-nodegroup-version`, or any mutating
  API. All upgrade actions are presented as a plan for human approval.
- **One minor version at a time.** EKS control plane upgrades can only proceed
  one minor version per operation (e.g., 1.30 → 1.31). Multi-hop requires
  sequential upgrades.
- **Version skew policy.** Starting Kubernetes 1.28+, kubelet supports N-3 skew
  from the control plane. For 1.27 and below, it is N-2.
- **Addons must be upgraded AFTER the control plane.** Some addons have specific
  version constraints per EKS version.
- **Auto-upgrade policy.** Clusters past the 26-month lifecycle (14 months
  standard + 12 months extended support) will be auto-upgraded. Failure to
  proactively upgrade risks disruption.

## Step 1: Gather Cluster Context

```
aws eks describe-cluster --name <cluster-name> --region <region>
```

Extract:
- `cluster.version` — current Kubernetes version
- `cluster.platformVersion` — EKS platform version
- `cluster.status` — must be ACTIVE
- `cluster.kubernetesNetworkConfig.serviceIpv4Cidr`
- `cluster.logging.clusterLogging` — audit log enabled? (MUST be enabled before upgrade)
- `cluster.resourcesVpcConfig.subnetIds` — needed for IP availability check

Determine the **target version**: ask the user, or default to current + 1 minor.

Review the [EKS release calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html#kubernetes-release-calendar) to confirm the target version is in standard support.

## Step 2: Verify Infrastructure Prerequisites

Before any upgrade can proceed, AWS requires these resources:

### Subnet IP Availability
EKS needs up to 5 available IPs in the cluster subnets:
```
aws ec2 describe-subnets --subnet-ids \
  $(aws eks describe-cluster --name <cluster> --query 'cluster.resourcesVpcConfig.subnetIds' --output text) \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,AvailableIpAddressCount]' --output table
```
If any subnet has fewer than 5 IPs, update cluster subnets before upgrading.

### EKS IAM Role
Verify the cluster IAM role exists and has correct trust policy:
```
ROLE_ARN=$(aws eks describe-cluster --name <cluster> --query 'cluster.roleArn' --output text)
aws iam get-role --role-name ${ROLE_ARN##*/} --query 'Role.AssumeRolePolicyDocument'
```
Must have `eks.amazonaws.com` as trusted service with `sts:AssumeRole`.

### KMS Key (if encryption enabled)
If secret encryption is enabled, verify the cluster role has permission to use the KMS key.

Report any failures as **BLOCKER** — the upgrade will fail without these.

## Step 3: Check EKS Upgrade Insights

```
aws eks list-insights --cluster-name <cluster> --region <region> \
  --filter '{"categories":["UPGRADE_READINESS"],"kubernetesVersions":["<target>"]}'
```

For each insight:
```
aws eks describe-insight --cluster-name <cluster> --id <insight-id> --region <region>
```

| Status | Action |
|--------|--------|
| ERROR | BLOCKER — must fix before upgrade |
| WARNING | Recommended to fix |
| PASSING | No action needed |

## Step 4: API Deprecation Analysis

For deprecated API insights, extract affected resources and map to replacements.
See `references/api-deprecations.md` for the full removal schedule.

### Feature-Specific Removals

**PodSecurityPolicy (removed 1.25):** Must migrate to Pod Security Standards
(PSS) or a policy-as-code solution (OPA Gatekeeper, Kyverno) before upgrading.

**Dockershim (removed 1.25):** If workloads mount the Docker socket, they will
break. Use [Detector for Docker Socket (DDS)](https://github.com/aws-containers/kubectl-detector-for-docker-socket) to scan.

**In-tree storage drivers (deprecated 1.23):** Must install the EBS CSI driver
before upgrading to 1.23+. Check with:
```
kubectl get sc -o jsonpath='{.items[*].provisioner}' | tr ' ' '\n' | sort -u
```
Any provisioner using `kubernetes.io/aws-ebs` (in-tree) must migrate to `ebs.csi.aws.com`.

### Detection Tools

In addition to EKS Insights, recommend:
- **kubent** (kube-no-trouble): `kubent` — scans live cluster for deprecated APIs
- **pluto**: `pluto detect-all-in-cluster` — similar, also supports Helm charts
- **kubectl-convert**: converts manifest files between API versions
  `kubectl-convert -f <file> --output-version <group>/<version>`

## Step 5: Addon Compatibility Check

```
aws eks list-addons --cluster-name <cluster> --region <region>
```

For each addon, check compatible versions for the target:
```
aws eks describe-addon-versions --addon-name <addon> --kubernetes-version <target>
```

Build a compatibility matrix. See `references/addon-version-matrix.md`.

**Addon upgrade order:**
1. Control plane (always first)
2. kube-proxy (MUST match control plane minor version)
3. vpc-cni (usually backward compatible)
4. coredns (usually backward compatible)
5. EBS/EFS CSI drivers
6. Other managed addons
7. Self-managed addons (AWS LB Controller, Metrics Server, etc.)

**If addons are self-managed** (Helm/manifests, not EKS managed), recommend
migrating to EKS Add-ons for simplified upgrade management.

## Step 6: Node Group Readiness

```
aws eks list-nodegroups --cluster-name <cluster> --region <region>
```

For each node group, check:
- `version` vs target (must be within N-3 for 1.28+, N-2 for older)
- `updateConfig.maxUnavailable` or `maxUnavailablePercentage`
- `instanceTypes` — capacity availability
- `amiType` — AL2, AL2023, Bottlerocket, Windows
- `launchTemplate` — custom LT with pinned AMI?
- `health.issues` — existing problems

**EKS Auto Mode:** If the cluster uses Auto Mode, data plane upgrades happen
automatically after control plane upgrade. Monitor to verify compliance with PDBs.

### Karpenter Managed Nodes

If Karpenter is used:
- **Drift feature:** Karpenter detects when nodes use AMIs from a previous
  version and automatically cordons, drains, and replaces them. Verify Drift is
  enabled in feature gates.
- **Node expiry (ttlSecondsUntilExpired):** Nodes beyond this age are replaced
  with latest AMI automatically. Ensure PDBs are configured to avoid disruption.
- **EC2NodeClass amiSelectorTerms:** Check if AMIs are pinned to a specific
  version (prevents auto-update). Must update selectors for new version.
- **Karpenter version compatibility:** Check Karpenter release notes for minimum
  EKS version support.

### Cluster Autoscaler

If Cluster Autoscaler (not Karpenter) is used:
- Version must match the control plane minor version (tightly coupled)
- Upgrade CA image tag to match target K8s version

### Self-Managed Nodes

- Check if using custom AMIs with pinned versions
- Must manually update launch template AMI after control plane upgrade
- Use `eksctl` or automation tools for rolling replacement

## Step 7: PDB and Topology Spread Validation

### Pod Disruption Budgets

PDBs control voluntary disruption during node drains. Check for blockers:
- `maxUnavailable: 0` — **blocks ALL drains**
- `minAvailable` equals replica count — same effect
- PDB on single-replica deployments with no disruption allowed
- Orphaned PDBs (label selector matches no pods)

Recommendations:
- Ensure at least `maxUnavailable: 1` for all PDBs during upgrade
- For stateful workloads, confirm data persistence before draining

### TopologySpreadConstraints

Verify critical workloads have topology spread across AZs and hosts:
```yaml
topologySpreadConstraints:
- maxSkew: 2
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: DoNotSchedule
- maxSkew: 2
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
```
Workloads without topology spread may end up concentrated on a single AZ after
upgrade, creating a blast radius risk.

## Step 8: Capacity Planning

See `references/capacity-planning.md` for detailed guidance.

Calculate surge requirements:
- Nodes per AZ × maxUnavailablePercentage = simultaneous replacements
- Consider Capacity Reservations (ODCR or FDCR) for large upgrades

| Cluster Size | Strategy | Notes |
|---|---|---|
| < 10 nodes | Rolling, maxUnavailable=1 | Safe, slow |
| 10-50 nodes | Rolling 25% | Good balance |
| 50-200 nodes | Rolling 33% | Needs capacity headroom |
| > 200 nodes | Blue-green node groups or blue-green clusters | See below |

### Blue-Green Cluster Alternative

For very large clusters or multi-hop upgrades (skipping versions), consider a
blue-green cluster strategy:
- Benefits: can jump multiple versions, able to roll back to old cluster
- Downsides: API endpoint and OIDC change, 2x cluster cost during migration,
  load balancers and DNS cannot easily span clusters, stateful workload migration

Refer to `references/upgrade-troubleshooting.md` for details.

## Step 9: Fargate Considerations

If the cluster runs Fargate pods:
- Fargate nodes are automatically upgraded when pods are redeployed
- After control plane upgrade, **restart all Fargate deployments**:
  ```
  kubectl get deployments -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' --no-headers | \
    while read ns name; do kubectl rollout restart deployment/$name -n $ns; done
  ```
- Fargate supports the same version skew as managed node groups (N-3 for 1.28+)

## Step 10: Generate Upgrade Plan

### Pre-Upgrade Checklist
- [ ] Subnet IPs available (>= 5 per subnet)
- [ ] EKS IAM role valid with correct trust policy
- [ ] KMS key accessible (if encryption enabled)
- [ ] Control plane logging enabled (audit, authenticator)
- [ ] All UPGRADE_READINESS insights at PASSING or WARNING (no ERROR)
- [ ] Deprecated APIs remediated or confirmed non-blocking
- [ ] Feature-specific removals addressed (PSP, Dockershim, in-tree storage)
- [ ] Addon compatibility verified for target version
- [ ] Node groups within version skew tolerance
- [ ] Karpenter/CA version compatible with target
- [ ] PDBs allow voluntary disruption (no maxUnavailable: 0 blockers)
- [ ] TopologySpreadConstraints on critical workloads
- [ ] Capacity available for surge nodes (or reservations in place)
- [ ] Backup taken (Velero or AWS Backup)

### Execution Order
1. **Control plane** — `aws eks update-cluster-version` (15-40 min)
2. **Wait** for ACTIVE status
3. **kube-proxy** — `aws eks update-addon` (must match CP version)
4. **vpc-cni** — `aws eks update-addon`
5. **coredns** — `aws eks update-addon`
6. **Other managed addons** — one at a time
7. **Self-managed addons** — Helm upgrade or manifest apply
8. **Node groups** — one at a time, validate between each
9. **Karpenter nodes** — update EC2NodeClass AMI selectors, Drift handles the rest
10. **Self-managed nodes** — update launch template, rolling replacement
11. **Fargate pods** — restart deployments
12. **Update kubectl** client to match new version

### Rollback Gates (validate after each step)
- API server responding: `kubectl get nodes`
- CoreDNS resolving: `kubectl run test --image=busybox --rm -it -- nslookup kubernetes`
- Critical workloads healthy (readiness probes passing)
- No unexpected CrashLoopBackOff or eviction storms
- Metrics pipeline functioning

If any gate fails: STOP. Control plane upgrade is irreversible, but subsequent
steps can be halted.

### Rollback Matrix
| Component | Reversible? | How |
|-----------|------------|-----|
| Control plane | NO | Must fix forward |
| Addons | YES | Downgrade to previous version |
| Managed node groups | PARTIAL | Can halt; completed nodes stay at new version |
| Karpenter nodes | YES | Revert EC2NodeClass, delete nodes |
| Self-managed nodes | YES | Revert launch template, terminate new nodes |
| Fargate pods | YES | Redeploy with previous config |

## Step 11: Report Format

```
## EKS Upgrade Readiness Report
**Cluster:** <name> (<region>)
**Current Version:** <current>
**Target Version:** <target>
**Assessment Date:** <date>
**Overall Readiness:** READY / NOT READY / READY WITH WARNINGS

### Infrastructure Prerequisites
- [PASS/FAIL] Subnet IP availability
- [PASS/FAIL] EKS IAM role
- [PASS/FAIL] KMS key access (if applicable)

### Blockers (must fix)
1. [BLOCKER] <description> — <remediation>

### Warnings (recommended)
1. [WARNING] <description> — <recommendation>

### Passing Checks
1. [PASS] <description>

### Upgrade Plan
<execution order from Step 10>

### Estimated Timeline
- Control plane: ~30 min
- Addons: ~5 min each
- Node groups: ~<X> min per group
- Total: ~<Y> min

### Tools Recommended
- kubent / pluto (deprecated API scanning)
- kubectl-convert (manifest migration)
- eksup (ClowdHaus upgrade guidance CLI)
- Velero / AWS Backup (pre-upgrade backup)
```

## References

See `references/` directory for:
- `api-deprecations.md` — full K8s API removal schedule by version
- `addon-version-matrix.md` — EKS addon compatibility per version
- `capacity-planning.md` — FDCR/ODCR and surge capacity guidance
- `upgrade-troubleshooting.md` — common failures, feature removals, and tools
