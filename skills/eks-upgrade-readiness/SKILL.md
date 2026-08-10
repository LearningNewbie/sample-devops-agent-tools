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
  deprecations (including Helm stored manifests and third-party CRDs),
  addon compatibility, node group readiness, Karpenter and Cluster
  Autoscaler compatibility, StatefulSet safety, PDB and topology spread
  validation, service quota headroom, capacity planning, and Fargate
  considerations — then produces a prioritized upgrade plan with rollback
  gates and confidence-graded findings. Do NOT use for ECS, general EKS
  troubleshooting unrelated to version upgrades, or EKS Anywhere/Outpost
  clusters.
metadata:
  author: LearningNewbie
  version: "1.2.0"
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

## Grading and Confidence

Every check result must include a confidence level:

| Level | Meaning | When to Use |
|-------|---------|-------------|
| HIGH (90%+) | Confirmed from authoritative source | EKS Insights API, direct kubectl query, AWS API response |
| MEDIUM (60-89%) | Inferred from available data | Partial kubectl access, version matching heuristics |
| LOW (30-59%) | Limited data, possible gaps | No kubectl, no logging enabled, partial API access |
| UNKNOWN | Cannot determine | Tool unavailable, no data, access denied |

**False-positive guards — apply before fixing any verdict:**
- Empty query result ≠ PASS. An empty result means "no data" not "no problem." Mark UNKNOWN.
- No kubectl access ≠ N/A for everything. AWS APIs still work.
- EKS Insights PASSING ≠ skip other checks. Insights covers a subset — not Helm manifests, StatefulSets, quotas, or CRDs.
- Addon "compatible" ≠ "recommended." A compatible version may be significantly behind latest.

Report format: `[PASS|FAIL|WARN|N/A] (confidence: HIGH) — <evidence>`

## Cost Awareness

- **EKS Insights API** (Step 3) is free — always use it first.
- **CloudWatch Logs Insights** queries (if used for deprecated API scanning) cost ~$0.0076/GB scanned. Default to 60-min windows.
- **Extended support** costs $0.60/cluster/hour after standard support ends — upgrading proactively saves money.
- **Surge nodes** during rolling replacement incur temporary EC2 cost for the overlap period.
- **Capacity Reservations** (ODCR) are billed whether used or not — create just before upgrade, cancel after.

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

### Service Quota Headroom

Node group upgrades launch surge instances. If EC2 vCPU or EBS volume quotas
are tight, the rolling replacement **stalls silently** with no clear error.

```bash
# EC2 vCPU quota (On-Demand Standard instances)
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A \
  --query 'Quota.Value'

# Current vCPU usage
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceType]' --output text | sort | uniq -c

# EBS gp3 volume quota
aws service-quotas get-service-quota --service-code ebs --quota-code L-7A658000 \
  --query 'Quota.Value'

# Current gp3 volume count
aws ec2 describe-volumes --filters "Name=volume-type,Values=gp3" \
  --query 'length(Volumes)'
```

**Pass criteria:** Available quota headroom > surge_nodes × resources_per_node.
If quota is tight, recommend requesting an increase **before** starting the
upgrade. Also check gp2 quotas if gp2 volumes are still in use.

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

> **Note:** EKS Insights is the authoritative source for removed-API detection
> but it does NOT cover Helm stored manifests, third-party CRD deprecations,
> StatefulSet config, Karpenter settings, or service quotas. Do not skip the
> remaining steps just because Insights is PASSING.

## Step 4: API Deprecation Analysis

For deprecated API insights, extract affected resources and map to replacements.
See `references/api-deprecations.md` for the full removal schedule.

### Version-Specific Removal Gates

Only evaluate the gates relevant to the user's target version:

| Target | Check | Severity | Detail |
|--------|-------|----------|--------|
| ≥ 1.33 | AL2 AMI unavailable | Critical | Amazon Linux 2 AMIs are not published for EKS 1.33+. MNGs/Karpenter using `AL2` must migrate to **AL2023** or **Bottlerocket**. |
| ≥ 1.35 | kube-proxy IPVS mode deprecated | High | IPVS mode deprecated in 1.35, removed in 1.36. Check: `kubectl get cm kube-proxy-config -n kube-system -o yaml \| grep mode` |
| ≥ 1.36 | kube-proxy IPVS mode removed | Critical | Must migrate to iptables/nftables before this upgrade. |
| ≥ 1.25 | Dockershim removed | Critical | Pods mounting `docker.sock` or `dockershim.sock` will break. Scan with DDS. |
| ≥ 1.25 | PodSecurityPolicy removed | Critical | Migrate to Pod Security Admission (PSA) or Kyverno/OPA Gatekeeper. |
| ≥ 1.23 | In-tree EBS provisioner deprecated | High | `kubernetes.io/aws-ebs` StorageClass must migrate to `ebs.csi.aws.com`. |
| any | Unmaintained community ingress-nginx | Medium | Migrate to AWS LB Controller, Gateway API, or vendor-supported NGINX. |

Detection for AL2:
```bash
# Check MNG AMI types
aws eks list-nodegroups --cluster-name <cluster> --query 'nodegroups[]' --output text | \
  xargs -I {} aws eks describe-nodegroup --cluster-name <cluster> --nodegroup-name {} \
  --query 'nodegroup.amiType' --output text

# Check Karpenter EC2NodeClass amiFamily
kubectl get ec2nodeclasses -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.amiFamily}{"\n"}{end}'
```

### Helm Stored Manifest Scanning (Critical)

**This is the #1 missed upgrade blocker.** Helm stores the full rendered manifest
in release Secrets of type `helm.sh/release.v1`. Deprecated apiVersions there
are invisible to the live Kubernetes API AND invisible to `kubent`/`pluto` — but
they break `helm upgrade` after a cluster upgrade because Helm replays the
stored manifest.

Detection:
```bash
# List all Helm release secrets
kubectl get secrets -A -l owner=helm \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

# Decode a single release (base64 → gzip → base64 → JSON)
kubectl get secret <release-secret> -n <namespace> -o jsonpath='{.data.release}' | \
  base64 -d | base64 -d | gunzip | jq -r '.manifest'
```

Scan the decoded `.manifest` field for `apiVersion` lines and compare against
the target version's removal list.

Remediation:
```bash
helm mapkubeapis <release-name> -n <namespace> --dry-run  # preview
helm mapkubeapis <release-name> -n <namespace>            # apply
helm upgrade <release-name> <chart> -n <namespace>        # commit the fix
```

If Helm/secret access is unavailable, mark as N/A and recommend the user run
`helm mapkubeapis --dry-run` per release before upgrading.

### Third-Party CRD API Deprecations

Core Kubernetes API deprecations are well-documented, but third-party CRDs have
their own apiVersion lifecycles that break independently of K8s upgrades.

| Component | Deprecated API | Removed In | Replacement |
|-----------|---------------|------------|-------------|
| Istio < 1.22 | `networking.istio.io/v1alpha3` | Istio 1.24 | `networking.istio.io/v1` |
| cert-manager < 1.6 | `cert-manager.io/v1alpha2` | cert-manager 1.6 | `cert-manager.io/v1` |
| Karpenter < 0.33 | `karpenter.sh/v1alpha5` | Karpenter 0.33 | `karpenter.sh/v1beta1` → `v1` |
| Karpenter < 1.0 | `karpenter.sh/v1beta1` | Karpenter 1.0 | `karpenter.sh/v1` |
| Flux < 2.0 | `source.toolkit.fluxcd.io/v1beta1` | Flux 2.0 | `source.toolkit.fluxcd.io/v1` |

Detection:
```bash
# List all CRDs and their served versions
kubectl get crds -o jsonpath='{range .items[*]}{.metadata.name}: {range .spec.versions[*]}{.name}{" "}{end}{"\n"}{end}'

# Find CRDs with deprecated stored versions
kubectl get crds -o json | jq '.items[] | select(.status.storedVersions[] | test("alpha|beta")) | {name: .metadata.name, storedVersions: .status.storedVersions}'
```

### Detection Tools

In addition to EKS Insights, recommend:
- **kubent** (kube-no-trouble): `kubent` — scans live cluster for deprecated APIs
- **pluto**: `pluto detect-all-in-cluster` — similar, also supports Helm charts
- **kubectl-convert**: converts manifest files between API versions
  `kubectl-convert -f <file> --output-version <group>/<version>`
- **helm mapkubeapis**: fixes deprecated APIs in stored Helm release manifests

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

If Karpenter is detected, evaluate all of the following:

- **Drift enabled:** Karpenter detects when nodes use AMIs from a previous
  version and automatically cordons, drains, and replaces them. Verify Drift is
  enabled in feature gates (default on v0.33+). If disabled, nodes won't
  auto-replace on AMI change.
  ```bash
  kubectl get deploy karpenter -n kube-system -o json | jq '.spec.template.spec.containers[0].env[] | select(.name=="FEATURE_GATES")'
  ```

- **Node expiry set (not Never):** Every NodePool must have
  `spec.disruption.expireAfter` set to a finite value. `Never` means nodes stay
  forever on old AMIs — defeating the purpose of an upgrade.
  ```bash
  kubectl get nodepools -o jsonpath='{range .items[*]}{.metadata.name}: expireAfter={.spec.disruption.expireAfter}{"\n"}{end}'
  ```

- **Disruption budgets allow replacement:** Check `spec.disruption.budgets`
  allows at least 1 node to be disrupted (not `nodes: "0"`). A zero budget
  blocks all automatic replacement.
  ```bash
  kubectl get nodepools -o json | jq '.items[] | {name: .metadata.name, budgets: .spec.disruption.budgets}'
  ```

- **EC2NodeClass amiSelectorTerms not pinned:** If `amiSelectorTerms` pin a
  specific AMI ID, Karpenter won't pick up the new version AMI. Must update
  selectors to use `amiFamily` or tag-based lookup.
  ```bash
  kubectl get ec2nodeclasses -o json | jq '.items[] | {name: .metadata.name, amiSelectorTerms: .spec.amiSelectorTerms}'
  ```

- **Karpenter version compatibility:** Check Karpenter release notes for minimum
  EKS version support. Example: Karpenter 0.37+ required for EKS 1.30+.
  ```bash
  kubectl get deploy karpenter -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'
  ```

### Cluster Autoscaler

If Cluster Autoscaler (not Karpenter) is used:
- Version must match the control plane minor version (tightly coupled)
- Upgrade CA image tag to match target K8s version

### Self-Managed Nodes

- Check if using custom AMIs with pinned versions
- Must manually update launch template AMI after control plane upgrade
- Use `eksctl` or automation tools for rolling replacement

## Step 7: PDB, Topology Spread, and Workload Safety

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

### StatefulSet Safety Checks

StatefulSets require extra care during upgrades because they are ordered and
often stateful. Unsafe defaults cause data loss during node drains.

- **`minReadySeconds > 0`:** Prevents premature "ready" during rolling node
  replacement. Zero means a pod is declared ready instantly, risking data
  inconsistency in clustered databases.
  ```bash
  kubectl get statefulsets -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: minReadySeconds={.spec.minReadySeconds}{"\n"}{end}'
  ```

- **`terminationGracePeriodSeconds != 0`:** Zero grace period means unsafe
  termination during drain — data loss risk for anything doing graceful shutdown.
  ```bash
  kubectl get statefulsets -A -o json | jq '.items[] | select(.spec.template.spec.terminationGracePeriodSeconds == 0) | .metadata.namespace + "/" + .metadata.name'
  ```

- **PVC retention policy:** Flag `whenDeleted: Delete` as a data loss risk if a
  node is removed during upgrade.
  ```bash
  kubectl get statefulsets -A -o json | jq '.items[] | select(.spec.persistentVolumeClaimRetentionPolicy.whenDeleted == "Delete") | .metadata.namespace + "/" + .metadata.name'
  ```

- **Single-replica StatefulSets without PDB:** These experience full downtime
  during node drain with no protection. Flag as HIGH severity.

### Scaled-to-Zero Workload Detection

Deployments/StatefulSets at 0 replicas are invisible during upgrade validation.
If restarted post-upgrade, they may hit removed APIs or incompatible images.

```bash
# Deployments at 0 replicas (excluding kube-system)
kubectl get deployments -A --field-selector metadata.namespace!=kube-system -o json | \
  jq '.items[] | select(.spec.replicas == 0) | .metadata.namespace + "/" + .metadata.name'

# StatefulSets at 0 replicas
kubectl get statefulsets -A -o json | \
  jq '.items[] | select(.spec.replicas == 0) | .metadata.namespace + "/" + .metadata.name'
```

Flag in the report: "These workloads are currently scaled to zero. Confirm they
are intentionally inactive or validate their API compatibility separately before
restarting post-upgrade."

## Step 8: Capacity Planning

See `references/capacity-planning.md` for detailed guidance.

Calculate surge requirements:
- Nodes per AZ × maxUnavailablePercentage = simultaneous replacements
- Consider Capacity Reservations (ODCR or FDCR) for large upgrades
- Verify service quotas (Step 2) can handle the surge

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
- [ ] Service quotas have headroom for surge (EC2 vCPU, EBS volumes)
- [ ] Control plane logging enabled (audit, authenticator)
- [ ] All UPGRADE_READINESS insights at PASSING or WARNING (no ERROR)
- [ ] Deprecated APIs remediated — live objects, Helm stored manifests, and CRDs
- [ ] Version-specific removals addressed (AL2 AMI, IPVS, PSP, Dockershim, in-tree storage)
- [ ] Third-party CRD apiVersions compatible with target
- [ ] Addon compatibility verified for target version
- [ ] Node groups within version skew tolerance
- [ ] Karpenter Drift enabled, expireAfter set, budgets allow disruption, AMIs not pinned
- [ ] Cluster Autoscaler version matches target (if CA used)
- [ ] PDBs allow voluntary disruption (no maxUnavailable: 0 blockers)
- [ ] StatefulSets have safe terminationGracePeriod and minReadySeconds
- [ ] TopologySpreadConstraints on critical workloads
- [ ] Scaled-to-zero workloads identified and acknowledged
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
- [PASS/FAIL] (confidence: HIGH) Subnet IP availability — <X> IPs available
- [PASS/FAIL] (confidence: HIGH) EKS IAM role — valid trust policy
- [PASS/FAIL] (confidence: HIGH) KMS key access (if applicable)
- [PASS/FAIL] (confidence: HIGH) EC2 vCPU quota — <X> available vs <Y> needed
- [PASS/FAIL] (confidence: HIGH) EBS volume quota — <X> available vs <Y> needed

### Blockers (must fix)
1. [BLOCKER] (confidence: HIGH) <description> — <remediation>

### Warnings (recommended)
1. [WARNING] (confidence: MEDIUM) <description> — <recommendation>

### Passing Checks
1. [PASS] (confidence: HIGH) <description>

### Not Assessed
1. [N/A] <check> — <reason> (e.g., "Helm access unavailable")

### Upgrade Plan
<execution order from Step 10>

### Estimated Timeline
- Control plane: ~30 min
- Addons: ~5 min each
- Node groups: ~<X> min per group
- Total: ~<Y> min

### Tools Recommended
- kubent / pluto (deprecated API scanning)
- helm mapkubeapis (Helm stored manifest fix)
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
