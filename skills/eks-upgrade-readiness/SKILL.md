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
  Best Practices Guide covering infrastructure prerequisites, EKS Upgrade
  Insights, API deprecations (including Helm stored manifests and third-party
  CRDs), addon compatibility (live API + self-managed detection), full data
  plane inventory (MNG, self-managed ASGs, Karpenter, Auto Mode, Fargate),
  AL2→AL2023 migration, StatefulSet safety, PDB and topology spread
  validation, service quota headroom, capacity planning, pre-upgrade cluster
  health baseline, and post-upgrade functional validation — then produces a
  scored readiness verdict with prioritized remediation (mutations separated
  for operator approval) and deterministic test coverage. Do NOT use for ECS,
  general EKS troubleshooting unrelated to version upgrades, or EKS
  Anywhere/Outpost clusters.
metadata:
  author: LearningNewbie
  version: "2.0.0"
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
- Detect GitOps/IaC version ownership before upgrading

## Critical Warnings

- **This skill is read-only.** All commands are `describe*`, `list*`, `get*`.
  The upgrade itself is a recommendation for the operator — the agent does NOT
  execute `update-cluster-version`, `update-nodegroup-version`, or any mutating
  API. All mutation examples are in the Remediation Playbook (Step 14) and
  require explicit operator approval.
- **One minor version at a time.** EKS control plane upgrades can only proceed
  one minor version per operation (e.g., 1.30 → 1.31). Multi-hop requires
  sequential upgrades.
- **Version skew policy.** Starting Kubernetes 1.28+, kubelet supports N-3 skew
  from the control plane. For 1.27 and below, it is N-2.
- **Addons must be upgraded AFTER the control plane** (with specific exceptions
  noted in Step 8). Some addons have version constraints per EKS version.
- **Auto-upgrade policy.** Clusters past the 26-month lifecycle (14 months
  standard + 12 months extended support) will be auto-upgraded. Failure to
  proactively upgrade risks disruption.
- **UNKNOWN ≠ PASS.** Any gate that cannot be assessed due to missing data,
  access denial, or tool unavailability MUST be marked UNKNOWN, never PASS.
  The overall verdict MUST NOT be READY while any gate is UNKNOWN.

## Required Permissions

### AWS IAM Permissions (minimum for assessment)

```
eks:DescribeCluster
eks:ListClusters
eks:ListInsights
eks:DescribeInsight
eks:ListAddons
eks:DescribeAddon
eks:DescribeAddonVersions
eks:ListNodegroups
eks:DescribeNodegroup
eks:ListFargateProfiles
eks:DescribeFargateProfile
eks:ListUpdates
eks:DescribeUpdate
ec2:DescribeSubnets
ec2:DescribeInstances
ec2:DescribeLaunchTemplateVersions
ec2:DescribeCapacityReservations
ec2:DescribeImages
iam:GetRole
autoscaling:DescribeAutoScalingGroups
autoscaling:DescribeLaunchConfigurations
servicequotas:GetServiceQuota
```

### Kubernetes RBAC (if kubectl access available)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: upgrade-readiness-reader
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "services", "configmaps", "secrets", "namespaces"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list"]
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["get", "list"]
- apiGroups: ["karpenter.sh"]
  resources: ["nodepools", "nodeclaims"]
  verbs: ["get", "list"]
- apiGroups: ["karpenter.k8s.aws"]
  resources: ["ec2nodeclasses"]
  verbs: ["get", "list"]
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["customresourcedefinitions"]
  verbs: ["get", "list"]
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests"]
  verbs: ["get", "list"]
```

### AccessDenied Handling

When any API call returns `AccessDeniedException` or `Forbidden`:
1. Log which permission is missing
2. Mark the affected gate as **UNKNOWN** (not PASS, not N/A)
3. Continue with remaining checks
4. Include in the report: "Gate X: UNKNOWN — AccessDenied on `<API>`. Grant
   `<permission>` to assess."
5. The overall verdict cannot be READY while any gate is UNKNOWN

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
- Pagination exhausted ≠ complete. If an API returns a `nextToken` and you don't paginate, mark confidence LOW and note "results may be incomplete."

**Verdict rules:**
- READY: All gates PASS or WARN (no FAIL, no UNKNOWN)
- READY WITH WARNINGS: All gates PASS or WARN, with at least one WARN
- NOT READY: Any gate is FAIL
- CANNOT DETERMINE: Any gate is UNKNOWN (must investigate before upgrade)

Report format: `[PASS|FAIL|WARN|UNKNOWN|N/A] (confidence: HIGH) — <evidence>`

## Cost Awareness

- **EKS Insights API** (Step 3) is free — always use it first.
- **CloudWatch Logs Insights** queries (if used for deprecated API scanning) cost ~$0.0076/GB scanned. Default to 60-min windows.
- **Extended support** costs $0.60/cluster/hour after standard support ends — upgrading proactively saves money.
- **Surge nodes** during rolling replacement incur temporary EC2 cost for the overlap period.
- **Capacity Reservations** (ODCR) are billed whether used or not — create just before upgrade, cancel after.

---

## Step 1: Gather Cluster Context

```bash
aws eks describe-cluster --name <cluster-name> --region <region>
```

Extract:
- `cluster.version` — current Kubernetes version
- `cluster.platformVersion` — EKS platform version
- `cluster.status` — must be ACTIVE
- `cluster.kubernetesNetworkConfig` — serviceIpv4Cidr, ipFamily (IPv4 or IPv6)
- `cluster.logging.clusterLogging` — audit log enabled? (MUST be enabled before upgrade)
- `cluster.resourcesVpcConfig.subnetIds` — needed for IP availability check
- `cluster.tags` — detect IaC ownership (see Step 12)

Determine the **target version**: ask the user, or default to current + 1 minor.

Review the [EKS release calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html#kubernetes-release-calendar) to confirm the target version is in standard support.

## Step 2: Verify Infrastructure Prerequisites

Before any upgrade can proceed, AWS requires these resources:

### Subnet IP Availability

EKS needs up to 5 available IPs in the cluster subnets:
```bash
aws ec2 describe-subnets --subnet-ids \
  $(aws eks describe-cluster --name <cluster> --query 'cluster.resourcesVpcConfig.subnetIds' --output text) \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,AvailableIpAddressCount]' --output table
```

**VPC CNI mode awareness:** IP requirements vary by networking mode:
- **Standard mode (IPv4):** Each pod consumes one secondary IP. Check `WARM_IP_TARGET` and `MINIMUM_IP_TARGET` in `aws-node` DaemonSet env vars.
- **Prefix delegation mode:** Each ENI slot allocates a /28 prefix (16 IPs). Higher pod density but fewer ENI slots consumed. Check: `ENABLE_PREFIX_DELEGATION=true` in aws-node.
- **Custom networking:** Pods use a different subnet than the node's primary ENI. Check `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` and `ENIConfig` CRDs for pod subnet IDs — validate those subnets too.
- **IPv6 mode:** Pods get IPv6 addresses from the VPC CIDR. Subnet exhaustion is not a concern, but verify dual-stack compatibility of workloads.
- **Security Groups for Pods:** Pods with `SecurityGroupPolicy` resources use branch ENIs. These consume additional ENI capacity and have instance-type limits.

Detection:
```bash
# Determine VPC CNI mode
kubectl get ds aws-node -n kube-system -o json | jq '.spec.template.spec.containers[0].env[] | select(.name | test("PREFIX_DELEGATION|CUSTOM_NETWORK|POD_SECURITY_GROUP"))'

# Check ENIConfig for custom networking
kubectl get eniconfigs -o jsonpath='{range .items[*]}{.metadata.name}: subnet={.spec.subnet}, sg={.spec.securityGroups}{"\n"}{end}'
```

If any subnet has fewer than 5 IPs (or fewer than surge requirement for prefix delegation mode), update cluster subnets before upgrading.

### EKS IAM Role

Verify the cluster IAM role exists and has correct trust policy:
```bash
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

## Step 3: Check EKS Upgrade Insights (Primary Signal)

**EKS Upgrade Insights is the primary authoritative signal for upgrade
readiness.** Always query it first and use its findings as the baseline.

```bash
aws eks list-insights --cluster-name <cluster> --region <region> \
  --filter '{"categories":["UPGRADE_READINESS"],"kubernetesVersions":["<target>"]}'
```

For each insight returned:
```bash
aws eks describe-insight --cluster-name <cluster> --id <insight-id> --region <region>
```

| Insight Status | Gate Result | Action |
|---------------|-------------|--------|
| ERROR | FAIL | BLOCKER — must fix before upgrade |
| WARNING | WARN | Recommended to fix, not blocking |
| PASSING | PASS | No action needed |
| No insights returned | UNKNOWN | API may not cover this version yet; continue other checks |
| AccessDenied | UNKNOWN | Missing `eks:ListInsights` / `eks:DescribeInsight` permission |

**Pagination:** `ListInsights` returns paginated results. Always follow
`nextToken` until exhausted. If you stop early, mark confidence as LOW.

> **Critical:** EKS Insights is authoritative but NOT comprehensive. It does NOT
> cover: Helm stored manifests, third-party CRD deprecations, StatefulSet config,
> Karpenter settings, service quotas, PDB safety, or capacity planning. All
> remaining steps are still required regardless of Insights result.

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

Detection (check **only the currently deployed revision**, not all history):
```bash
# List all Helm release secrets (latest revision per release only)
kubectl get secrets -A -l owner=helm,status=deployed \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

# Decode a single release (base64 → gzip → base64 → JSON)
kubectl get secret <release-secret> -n <namespace> -o jsonpath='{.data.release}' | \
  base64 -d | base64 -d | gunzip | jq -r '.manifest'
```

Scan the decoded `.manifest` field for `apiVersion` lines and compare against
the target version's removal list.

> Remediation for Helm manifests is in the Remediation Playbook (Step 14).

If Helm/secret access is unavailable, mark as UNKNOWN and recommend the user run
`helm mapkubeapis --dry-run` per release before upgrading.

### Third-Party CRD API Deprecations

Core Kubernetes API deprecations are well-documented, but third-party CRDs have
their own apiVersion lifecycles that break independently of K8s upgrades.

Check must be **vendor-aware and version-aware**: compare the installed CRD
version (from the controller's deployed image tag or Helm release) against
known deprecation timelines.

| Component | Deprecated API | Removed In | Replacement |
|-----------|---------------|------------|-------------|
| Istio < 1.22 | `networking.istio.io/v1alpha3` | Istio 1.24 | `networking.istio.io/v1` |
| cert-manager < 1.6 | `cert-manager.io/v1alpha2` | cert-manager 1.6 | `cert-manager.io/v1` |
| Karpenter < 0.33 | `karpenter.sh/v1alpha5` | Karpenter 0.33 | `karpenter.sh/v1beta1` → `v1` |
| Karpenter < 1.0 | `karpenter.sh/v1beta1` | Karpenter 1.0 | `karpenter.sh/v1` |
| Flux < 2.0 | `source.toolkit.fluxcd.io/v1beta1` | Flux 2.0 | `source.toolkit.fluxcd.io/v1` |
| Argo Rollouts < 1.6 | `argoproj.io/v1alpha1` (some fields) | Argo 1.6 | Check release notes |
| Prometheus Operator < 0.65 | `monitoring.coreos.com/v1alpha1` | PO 0.65 | `monitoring.coreos.com/v1` |

Detection:
```bash
# List all CRDs and their served versions
kubectl get crds -o jsonpath='{range .items[*]}{.metadata.name}: {range .spec.versions[*]}{.name}{" "}{end}{"\n"}{end}'

# Find CRDs with deprecated stored versions
kubectl get crds -o json | jq '.items[] | select(.status.storedVersions[] | test("alpha|beta")) | {name: .metadata.name, storedVersions: .status.storedVersions}'

# Check installed controller versions for risk assessment
kubectl get deploy -A -o json | jq '.items[] | select(.metadata.name | test("istio|cert-manager|karpenter|flux|argocd")) | {ns: .metadata.namespace, name: .metadata.name, image: .spec.template.spec.containers[0].image}'
```

### Detection Tools

In addition to EKS Insights, recommend:
- **kubent** (kube-no-trouble): `kubent` — scans live cluster for deprecated APIs
- **pluto**: `pluto detect-all-in-cluster` — similar, also supports Helm charts
- **kubectl-convert**: converts manifest files between API versions
  `kubectl-convert -f <file> --output-version <group>/<version>`
- **helm mapkubeapis**: fixes deprecated APIs in stored Helm release manifests

## Step 5: Addon Compatibility Check

### EKS Managed Addons (Live API)

Query the actual addon state and compatible versions — never rely solely on
static tables:

```bash
# List installed managed addons
aws eks list-addons --cluster-name <cluster> --region <region>

# For each addon, get current version and health
aws eks describe-addon --cluster-name <cluster> --addon-name <addon-name> \
  --query '{name:addon.addonName, version:addon.addonVersion, status:addon.status, health:addon.health}'

# Check compatible versions for target
aws eks describe-addon-versions --addon-name <addon-name> --kubernetes-version <target> \
  --query 'addons[0].addonVersions[*].{version:addonVersion,default:compatibilities[0].defaultVersion}' \
  --output table
```

**Pagination:** `DescribeAddonVersions` paginates. Always exhaust `nextToken`.

Build a compatibility matrix showing:
- Current version → recommended version for target
- Whether the upgrade requires `OVERWRITE` conflict resolution
- Whether configuration changes are needed

See `references/addon-version-matrix.md` for the static fallback reference
(use only when APIs are unavailable).

### Self-Managed Addon Detection

Many clusters run addons outside EKS management (via Helm, manifests, or
GitOps). These won't appear in `list-addons` but still need version validation.

Detection:
```bash
# Common self-managed addons by namespace/label
kubectl get deploy -A -o json | jq '.items[] | select(
  .metadata.name | test("aws-load-balancer|external-dns|metrics-server|cluster-autoscaler|cert-manager|ingress-nginx|argocd|flux")
) | {ns: .metadata.namespace, name: .metadata.name, image: .spec.template.spec.containers[0].image}'

# Check for Helm releases not tracked by EKS
kubectl get secrets -A -l owner=helm -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.labels.name}:{.metadata.labels.version}{"\n"}{end}' | sort -u
```

For each self-managed addon found:
1. Extract the image tag (version)
2. Check the addon's GitHub/docs for Kubernetes version support matrix
3. Flag if the installed version doesn't support the target K8s version

### Addon Upgrade Order

**Pre-upgrade (before control plane):**
1. Karpenter (if upgrading to a version that requires newer Karpenter — check release notes)
2. Cluster Autoscaler (version must match target CP minor version)
3. Admission webhooks that block API server startup (if incompatible with target)

**Post-upgrade (after control plane):**
1. kube-proxy (MUST match control plane minor version)
2. vpc-cni (usually backward compatible)
3. coredns (usually backward compatible)
4. EBS/EFS CSI drivers
5. Other managed addons
6. Self-managed addons (AWS LB Controller, Metrics Server, etc.)

## Step 6: Full Data Plane Inventory

A complete picture of the data plane is required. Missing any node population
means the upgrade plan has blind spots.

### Managed Node Groups (MNG)

```bash
# List all node groups (paginate!)
NODEGROUPS=$(aws eks list-nodegroups --cluster-name <cluster> --query 'nodegroups[]' --output text)

# For each node group, get full details
for ng in $NODEGROUPS; do
  aws eks describe-nodegroup --cluster-name <cluster> --nodegroup-name "$ng" \
    --query '{name:nodegroup.nodegroupName, version:nodegroup.version, 
      amiType:nodegroup.amiType, instanceTypes:nodegroup.instanceTypes,
      desiredSize:nodegroup.scalingConfig.desiredSize,
      maxSize:nodegroup.scalingConfig.maxSize,
      updateConfig:nodegroup.updateConfig,
      launchTemplate:nodegroup.launchTemplate,
      health:nodegroup.health.issues}'
done
```

For each MNG, record:
- Current K8s version vs target (version skew check)
- AMI type (AL2, AL2023, BOTTLEROCKET, WINDOWS_CORE, CUSTOM)
- Update strategy (`maxUnavailable` or `maxUnavailablePercentage`)
- Launch template ID and version (for custom AMI detection)
- Health issues (any existing problems block upgrade)

**MNG Update Algorithm:** When you initiate a node group update, EKS:
1. Creates new nodes with the updated config (up to `maxUnavailable` count)
2. Cordons old nodes
3. Drains old nodes (respects PDBs — will wait/retry for up to 15 min)
4. If drain fails after timeout, ForceEviction applies (pods deleted)
5. Old nodes are terminated
6. Repeats until all nodes are updated

Understanding this is critical for capacity planning — at peak, you have
`existing_nodes + maxUnavailable` nodes running simultaneously.

### Self-Managed Node Groups (ASGs)

Self-managed nodes are EC2 instances in ASGs that joined the cluster via
bootstrap script but aren't tracked by EKS node group APIs.

Detection:
```bash
# Find ASGs with EKS cluster tag
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?Tags[?Key=='kubernetes.io/cluster/<cluster>' || Key=='eks:cluster-name']].[AutoScalingGroupName,LaunchTemplate.LaunchTemplateId,LaunchTemplate.Version,DesiredCapacity]" \
  --output table

# Get launch template details for AMI ID
aws ec2 describe-launch-template-versions --launch-template-id <lt-id> \
  --versions <version> --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId'

# Resolve AMI to K8s version
aws ec2 describe-images --image-ids <ami-id> --query 'Images[0].[Name,Description]'
```

For self-managed nodes:
- Extract kubelet version from node labels (if kubectl available): `kubectl get nodes -l eks.amazonaws.com/nodegroup!=<any-mng> -o jsonpath='{range .items[*]}{.metadata.name}: {.status.nodeInfo.kubeletVersion}{"\n"}{end}'`
- Check if AMI is custom or EKS-optimized (from AMI name pattern)
- Identify bootstrap method (see AL2→AL2023 section)
- Note: self-managed nodes require manual launch template updates

### Karpenter Managed Nodes

```bash
# Check Karpenter version
kubectl get deploy karpenter -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# List NodePools and their config
kubectl get nodepools -o json | jq '.items[] | {
  name: .metadata.name,
  expireAfter: .spec.disruption.expireAfter,
  consolidateAfter: .spec.disruption.consolidateAfter,
  budgets: .spec.disruption.budgets
}'

# List EC2NodeClasses (AMI config)
kubectl get ec2nodeclasses -o json | jq '.items[] | {
  name: .metadata.name,
  amiFamily: .spec.amiFamily,
  amiSelectorTerms: .spec.amiSelectorTerms
}'

# Check feature gates (Drift)
kubectl get deploy karpenter -n kube-system -o json | jq '.spec.template.spec.containers[0].env[] | select(.name=="FEATURE_GATES")'
```

Karpenter checks:
- **Drift enabled:** Default on since v0.33. If explicitly disabled, nodes won't auto-replace.
- **expireAfter set (not Never):** `Never` means nodes stay forever on old AMIs.
- **Disruption budgets allow replacement:** `nodes: "0"` blocks all replacement.
- **amiSelectorTerms not pinned to specific AMI ID:** Pinned AMIs prevent version updates. Must use `amiFamily` or tag-based selectors.
- **Karpenter version compatibility:** Check release notes for minimum EKS version.
- **NodePool consolidation policy:** Note whether consolidation is active (affects timing of node replacement).

### EKS Auto Mode

If `cluster.computeConfig.enabled` is `true`:
- Data plane upgrades happen automatically after control plane upgrade
- Monitor with: `aws eks describe-cluster --name <cluster> --query 'cluster.computeConfig'`
- Verify PDBs won't block automatic rotation

### Fargate Profiles

```bash
# List Fargate profiles
aws eks list-fargate-profiles --cluster-name <cluster>

# Describe each profile
aws eks describe-fargate-profile --cluster-name <cluster> --fargate-profile-name <name> \
  --query '{name:fargateProfile.fargateProfileName, selectors:fargateProfile.selectors, subnets:fargateProfile.subnets}'
```

Fargate pods:
- Are automatically upgraded when redeployed after control plane upgrade
- Support the same version skew as managed node groups (N-3 for 1.28+)
- Require explicit restart after CP upgrade (see Step 11)

### Kubelet Version Inventory

Regardless of node management method, confirm actual kubelet versions running:
```bash
# Full kubelet version map (requires kubectl)
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: kubelet={.status.nodeInfo.kubeletVersion}, os={.status.nodeInfo.osImage}, arch={.metadata.labels.kubernetes\.io/arch}{"\n"}{end}'

# Summary: versions that violate skew policy
kubectl get nodes -o json | jq --arg target "<target-version>" '.items[] | select(.status.nodeInfo.kubeletVersion | test("v1\\.(\\d+)") | not) | {name: .metadata.name, version: .status.nodeInfo.kubeletVersion}'
```

**Version skew check:** For target version 1.X:
- If X >= 28: kubelet must be >= 1.(X-3) — i.e., N-3 allowed
- If X < 28: kubelet must be >= 1.(X-2) — i.e., N-2 allowed

Any node outside the skew window is a **FAIL** — it must be upgraded first or
the control plane upgrade will be blocked.

## Step 7: AL2 → AL2023 Migration Assessment

If any node group or EC2NodeClass uses AL2 (`amiType: AL2` or `amiFamily: AL2`),
and the target version is 1.33+, this is a **CRITICAL** blocker.

Even for targets < 1.33, flag AL2 usage as a **WARNING** — AL2 reaches end of
life June 2025, and migration should be planned.

### Launch Template Analysis

```bash
# Get launch template user data for bootstrap method detection
aws ec2 describe-launch-template-versions --launch-template-id <lt-id> \
  --versions <version> --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' | \
  base64 -d
```

Bootstrap differences:
| Aspect | AL2 (bootstrap.sh) | AL2023 (nodeadm) |
|--------|--------------------|--------------------|
| Bootstrap script | `/etc/eks/bootstrap.sh` | `nodeadm` with YAML NodeConfig |
| Config format | CLI flags | `/etc/nodeadm/nodeconfig.yaml` |
| Cgroup driver | cgroup v1 | cgroup v2 (unified) |
| IMDS | v1 enabled by default | v2 only (IMDSv2) |
| Container runtime | containerd (since 1.24) | containerd |
| Kernel | 5.10 | 6.1 |

### Custom AMI Detection

If a node group uses a custom AMI (not EKS-optimized):
```bash
# Check if AMI is EKS-optimized or custom
AMI_ID=$(aws ec2 describe-launch-template-versions --launch-template-id <lt-id> \
  --versions <version> --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId' --output text)
aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].Name' --output text
# EKS-optimized pattern: amazon-eks-node-<version>-*
# Custom: anything else
```

If custom AMI is detected:
- Flag that automated AMI updates won't work
- User must rebuild their AMI pipeline for AL2023 base
- Check if user data scripts are AL2-specific (yum vs dnf, systemd units, etc.)

### User Data / Bootstrap Compatibility

Check user data for AL2-specific patterns that break on AL2023:
- `--kubelet-extra-args` in bootstrap.sh → must convert to NodeConfig YAML
- `/etc/docker/daemon.json` → irrelevant on AL2023 (containerd only)
- `yum install` → must change to `dnf install`
- `/etc/sysctl.d/` settings → verify cgroup v2 compatibility
- IMDSv1 assumptions → AL2023 defaults to IMDSv2 only

### Cgroup v2 Compatibility

AL2023 uses cgroup v2 (unified hierarchy). Check for workloads that assume cgroup v1:
- Java apps with `-XX:+UseContainerSupport` (works on both, but check JDK version)
- Monitoring agents that read `/sys/fs/cgroup/memory/` (v1 path, not v2)
- Custom init containers that manipulate cgroup files directly

## Step 8: Upgrade Ordering and Pre-Upgrade Alignment

Some components must be updated **before** the control plane to avoid breakage
during the upgrade window.

### Pre-Upgrade (before `update-cluster-version`)

| Component | Condition | Reason |
|-----------|-----------|--------|
| Karpenter | Target requires newer Karpenter (check release notes) | Old Karpenter may not understand new K8s APIs |
| Cluster Autoscaler | Always (version must match CP minor) | CA reads API server; mismatch causes errors |
| Admission webhooks | If webhook `failurePolicy: Fail` and incompatible | Can block API server during upgrade |
| Custom controllers | If they use deprecated APIs removed in target | Controller crashes block workload operations |

### Post-Upgrade (after control plane is ACTIVE)

Standard addon and node group upgrade order (see Step 5 addon section).

### Webhook Compatibility Check

```bash
# List webhooks with Fail policy
kubectl get validatingwebhookconfigurations -o json | jq '.items[] | select(.webhooks[].failurePolicy == "Fail") | {name: .metadata.name, webhooks: [.webhooks[].name]}'
kubectl get mutatingwebhookconfigurations -o json | jq '.items[] | select(.webhooks[].failurePolicy == "Fail") | {name: .metadata.name, webhooks: [.webhooks[].name]}'
```

Webhooks with `failurePolicy: Fail` that target broad API groups can block the
control plane upgrade. If the webhook's backend service isn't compatible with
the new API server version, it will reject API calls during the upgrade window.

## Step 9: PDB, Topology Spread, and Workload Safety

### Pod Disruption Budgets

PDBs control voluntary disruption during node drains. Check for blockers:
- `maxUnavailable: 0` — **blocks ALL drains**
- `minAvailable` equals replica count — same effect
- PDB on single-replica deployments with no disruption allowed
- Orphaned PDBs (label selector matches no pods)

```bash
# List all PDBs with their config
kubectl get pdb -A -o json | jq '.items[] | {
  ns: .metadata.namespace, name: .metadata.name,
  minAvailable: .spec.minAvailable, maxUnavailable: .spec.maxUnavailable,
  currentHealthy: .status.currentHealthy, desiredHealthy: .status.desiredHealthy,
  disruptionsAllowed: .status.disruptionsAllowed
}'

# Find PDBs that block all disruption
kubectl get pdb -A -o json | jq '.items[] | select(.status.disruptionsAllowed == 0) | {ns: .metadata.namespace, name: .metadata.name}'
```

### TopologySpreadConstraints

Verify critical workloads have topology spread across AZs and hosts:
```bash
kubectl get deploy -A -o json | jq '.items[] | select(.spec.template.spec.topologySpreadConstraints == null and .spec.replicas > 1) | {ns: .metadata.namespace, name: .metadata.name, replicas: .spec.replicas}'
```

Workloads without topology spread may end up concentrated on a single AZ after
upgrade, creating a blast radius risk.

### StatefulSet Safety Checks

StatefulSets require extra care during upgrades. Check:

- **`terminationGracePeriodSeconds != 0`:** Zero grace period = data loss risk.
- **PVC retention policy:** `whenDeleted: Delete` = data loss if node removed.
  Correct check: look at the StatefulSet's `.spec.persistentVolumeClaimRetentionPolicy`, which controls what happens to PVCs when the StatefulSet scales down or is deleted — not when individual pods are rescheduled.
- **Single-replica StatefulSets without PDB:** Full downtime during drain.
- **Ordered update strategy:** `OrderedReady` means sequential pod updates (slower but safer). `Parallel` means all pods restart simultaneously.

```bash
# StatefulSets with dangerous config
kubectl get statefulsets -A -o json | jq '.items[] | {
  ns: .metadata.namespace, name: .metadata.name,
  replicas: .spec.replicas,
  gracePeriod: .spec.template.spec.terminationGracePeriodSeconds,
  pvcPolicy: .spec.persistentVolumeClaimRetentionPolicy,
  updateStrategy: .spec.updateStrategy.type
} | select(.gracePeriod == 0 or (.replicas == 1))'
```

### Scaled-to-Zero Workload Detection

```bash
kubectl get deployments -A --field-selector metadata.namespace!=kube-system -o json | \
  jq '.items[] | select(.spec.replicas == 0) | .metadata.namespace + "/" + .metadata.name'
kubectl get statefulsets -A -o json | \
  jq '.items[] | select(.spec.replicas == 0) | .metadata.namespace + "/" + .metadata.name'
```

Flag: "These workloads are currently scaled to zero. If restarted post-upgrade,
they may hit removed APIs or incompatible images. Validate separately."

## Step 10: Pre-Upgrade Cluster Health Baseline

Before starting the upgrade, confirm the cluster is in a healthy steady state.
Upgrading an already-unhealthy cluster compounds problems.

### Node Health

```bash
# All nodes must be Ready
kubectl get nodes -o json | jq '.items[] | select(.status.conditions[] | select(.type == "Ready" and .status != "True")) | .metadata.name'

# Check for nodes with other conditions (MemoryPressure, DiskPressure, PIDPressure)
kubectl get nodes -o json | jq '.items[] | .status.conditions[] | select(.type != "Ready" and .status == "True") | {node: .type, message: .message}'
```

If any node is NotReady, investigate before upgrading. FAIL this gate.

### Pending Certificate Signing Requests

```bash
kubectl get csr -o json | jq '.items[] | select(.status.conditions == null or (.status.conditions | length == 0)) | {name: .metadata.name, requestor: .spec.username}'
```

Pending CSRs indicate node registration issues. Resolve before upgrade.

### Crash-Looping System Pods

```bash
# Check kube-system pods for CrashLoopBackOff or Error
kubectl get pods -n kube-system -o json | jq '.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "CrashLoopBackOff" or .status.phase == "Failed") | {name: .metadata.name, status: .status.phase, reason: .status.containerStatuses[0].state.waiting.reason}'

# Also check monitoring and ingress namespaces
for ns in monitoring ingress-nginx kube-system; do
  kubectl get pods -n $ns --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null
done
```

Any crash-looping system pod is a WARN (investigate before upgrade).

### Metrics and DNS Baseline

```bash
# Verify metrics-server is responding
kubectl top nodes --no-headers 2>&1 | head -3

# Verify CoreDNS is resolving
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local 2>&1 | grep -i "address"
```

Record baseline values for post-upgrade comparison.

## Step 11: Fargate Considerations

If the cluster runs Fargate pods:
- Fargate nodes are automatically upgraded when pods are redeployed
- After control plane upgrade, **all Fargate pods must be restarted**
- Fargate supports the same version skew as managed node groups (N-3 for 1.28+)

> Restart command is in the Remediation Playbook (Step 14) — it is a mutation.

## Step 12: GitOps/IaC Version Ownership Detection

Detect how the cluster and node groups are managed so remediation actions route
through the correct tool — not applied directly.

### Detection

```bash
# Check cluster tags for IaC markers
aws eks describe-cluster --name <cluster> --query 'cluster.tags'

# Common tags indicating ownership:
# aws:cloudformation:stack-name → CloudFormation
# terraform:workspace, tf:managed-by → Terraform
# pulumi:project → Pulumi
# eksctl.cluster.k8s.io/v1alpha1 → eksctl
# argocd.argoproj.io/managed-by → ArgoCD
# kustomize.toolkit.fluxcd.io/name → Flux

# Check node group tags
for ng in $(aws eks list-nodegroups --cluster-name <cluster> --query 'nodegroups[]' --output text); do
  echo "=== $ng ==="
  aws eks describe-nodegroup --cluster-name <cluster> --nodegroup-name $ng --query 'nodegroup.tags'
done

# Check for Terraform state references
kubectl get configmap -n kube-system -l "app.kubernetes.io/managed-by=Helm" 2>/dev/null
```

### Routing Remediation

| Detected Owner | Remediation Path |
|---------------|-----------------|
| CloudFormation | Update CF template `Version` parameter, run stack update |
| Terraform | Update `cluster_version` in `.tf`, run `terraform plan` then `apply` |
| CDK | Update `version` in CDK construct, run `cdk deploy` |
| eksctl | Update `metadata.version` in cluster config YAML, run `eksctl upgrade cluster` |
| ArgoCD | Update version in Git source, let ArgoCD sync |
| Flux | Update version in Git source, let Flux reconcile |
| Pulumi | Update version in Pulumi program, run `pulumi up` |
| Manual / Unknown | Provide direct AWS CLI commands |

Include the detected ownership in the report and route all remediation steps
through the owning tool. Never suggest direct `aws eks update-cluster-version`
if the cluster is IaC-managed — that would cause drift.

## Step 13: Autoscaler Pause During Node Rotation

During node group upgrades, autoscalers can interfere with the rolling
replacement by scaling down newly-launched surge nodes or consolidating workloads
back to old nodes.

### Karpenter

Pause consolidation and voluntary disruption during upgrade:
```bash
# Check current disruption config
kubectl get nodepools -o json | jq '.items[] | {name: .metadata.name, consolidateAfter: .spec.disruption.consolidateAfter, budgets: .spec.disruption.budgets}'
```

> Remediation (pause commands) is in Step 14 — operator approval required.

### Cluster Autoscaler

```bash
# Check CA deployment annotations for pause indicators
kubectl get deploy cluster-autoscaler -n kube-system -o json | jq '.metadata.annotations'

# Check if scale-down is enabled
kubectl get cm cluster-autoscaler-status -n kube-system -o yaml 2>/dev/null | grep -i "scale-down"
```

> Remediation (pause commands) is in Step 14 — operator approval required.

### Report Recommendation

Always include in the upgrade plan:
- "Before starting node rotation, pause Karpenter consolidation and CA scale-down"
- "After all nodes are rotated, re-enable autoscaler policies"

## Step 14: Remediation Playbook (Operator Approval Required)

> ⚠️ **ALL commands in this section are MUTATIONS.** They modify cluster state.
> The agent MUST NOT execute these — present them as a playbook for the operator
> to review and run manually.

### 14.1 Helm Stored Manifest Fix

```bash
# Preview (safe)
helm mapkubeapis <release-name> -n <namespace> --dry-run

# Apply (mutating — requires operator approval)
helm mapkubeapis <release-name> -n <namespace>

# Commit the fix by upgrading the release
helm upgrade <release-name> <chart> -n <namespace>
```

### 14.2 Addon Conflict Resolution

```bash
# Force overwrite conflicts (mutating)
aws eks update-addon --cluster-name <cluster> \
  --addon-name <addon> --addon-version <version> \
  --resolve-conflicts OVERWRITE
```

### 14.3 Fargate Pod Restart

```bash
# Restart all Fargate deployments (mutating)
kubectl get deployments -A --field-selector metadata.namespace!=kube-system -o json | \
  jq -r '.items[] | select(.spec.template.metadata.annotations["iam.amazonaws.com/role"] != null or true) | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read ns name; do kubectl rollout restart deployment/$name -n $ns; done
```

### 14.4 PDB Temporary Adjustment

```bash
# Temporarily allow disruption (mutating)
kubectl patch pdb <name> -n <namespace> -p '{"spec":{"maxUnavailable":1}}'
# IMPORTANT: Revert after upgrade completes
```

### 14.5 Karpenter Consolidation Pause

```bash
# Pause consolidation during upgrade (mutating)
kubectl annotate nodepools --all "karpenter.sh/do-not-disrupt=true"
# IMPORTANT: Remove after node rotation completes
kubectl annotate nodepools --all "karpenter.sh/do-not-disrupt-"
```

### 14.6 Cluster Autoscaler Scale-Down Pause

```bash
# Pause CA scale-down (mutating)
kubectl annotate deploy cluster-autoscaler -n kube-system "cluster-autoscaler.kubernetes.io/safe-to-evict=false"
# Or patch CA config:
kubectl patch cm cluster-autoscaler-config -n kube-system -p '{"data":{"scale-down-enabled":"false"}}'
# IMPORTANT: Re-enable after upgrade
```

### 14.7 Node Group Upgrade Initiation

```bash
# For MNG (mutating)
aws eks update-nodegroup-version --cluster-name <cluster> --nodegroup-name <ng> \
  --kubernetes-version <target>

# For Karpenter — trigger drift by updating EC2NodeClass (mutating)
kubectl patch ec2nodeclass <name> -p '{"spec":{"amiFamily":"AL2023"}}'

# For self-managed — update launch template then rolling replace (mutating)
aws ec2 create-launch-template-version --launch-template-id <lt-id> \
  --source-version <current> --launch-template-data '{"ImageId":"<new-ami>"}'
```

## Step 15: Post-Upgrade Functional Validation

After the upgrade completes, run these smoke tests to confirm the cluster
functions correctly. Present these to the operator as a validation checklist.

### DNS Resolution
```bash
kubectl run dns-smoke --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
```

### Metrics Server
```bash
kubectl top nodes
kubectl top pods -n kube-system
```

### Pod Scheduling
```bash
kubectl run schedule-test --image=nginx:alpine --rm -it --restart=Never -- echo "scheduled OK"
```

### Load Balancer Health (if applicable)
```bash
# Check ALB/NLB target group health
aws elbv2 describe-target-health --target-group-arn <arn>
```

### IRSA / Pod Identity
```bash
# Verify a pod can assume its role
kubectl run irsa-test --image=amazon/aws-cli --rm -it --restart=Never \
  --overrides='{"spec":{"serviceAccountName":"<sa-with-role>"}}' -- sts get-caller-identity
```

### CoreDNS and kube-proxy Pods Running
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

### Compare Against Baseline
- Node count matches pre-upgrade count
- No new CrashLoopBackOff pods
- Metrics pipeline reporting (compare with Step 10 baseline)
- Application health checks passing (check readiness probes)

## Step 16: Generate Upgrade Plan and Report

### Pre-Upgrade Checklist

- [ ] Cluster in healthy state (Step 10 baseline passes)
- [ ] Subnet IPs available (>= 5 per subnet, mode-aware)
- [ ] EKS IAM role valid with correct trust policy
- [ ] KMS key accessible (if encryption enabled)
- [ ] Service quotas have headroom for surge (EC2 vCPU, EBS volumes)
- [ ] Control plane logging enabled (audit, authenticator)
- [ ] EKS Upgrade Insights: no ERROR findings (Step 3)
- [ ] Deprecated APIs remediated — live objects, Helm stored manifests, and CRDs
- [ ] Version-specific removals addressed (AL2, IPVS, PSP, Dockershim, in-tree storage)
- [ ] AL2→AL2023 migration planned if needed (Step 7)
- [ ] Addon compatibility verified via live API (Step 5)
- [ ] Self-managed addons identified and version-checked
- [ ] All node populations inventoried (MNG, self-managed, Karpenter, Fargate)
- [ ] Kubelet versions within skew tolerance
- [ ] Pre-upgrade component alignment done (Karpenter, CA, webhooks — Step 8)
- [ ] PDBs allow voluntary disruption (no blockers)
- [ ] StatefulSets have safe config (grace period, PVC policy)
- [ ] TopologySpreadConstraints on critical workloads
- [ ] Scaled-to-zero workloads identified and acknowledged
- [ ] Capacity available for surge nodes (or reservations in place)
- [ ] IaC ownership identified, remediation routed correctly (Step 12)
- [ ] Autoscaler pause plan documented (Step 13)
- [ ] Backup taken (Velero or AWS Backup)
- [ ] Post-upgrade validation plan ready (Step 15)

### Execution Order

1. **Pre-upgrade alignment** — upgrade Karpenter/CA/webhooks if needed
2. **Pause autoscalers** — consolidation + scale-down disabled
3. **Control plane** — `aws eks update-cluster-version` (15-40 min)
4. **Wait** for ACTIVE status
5. **kube-proxy** — `aws eks update-addon` (must match CP version)
6. **vpc-cni** — `aws eks update-addon`
7. **coredns** — `aws eks update-addon`
8. **Other managed addons** — one at a time
9. **Self-managed addons** — Helm upgrade or manifest apply
10. **Node groups** — one at a time, validate between each
11. **Karpenter nodes** — update EC2NodeClass, Drift handles replacement
12. **Self-managed nodes** — update launch template, rolling replacement
13. **Fargate pods** — restart deployments
14. **Re-enable autoscalers** — remove pause annotations
15. **Post-upgrade validation** — run smoke tests (Step 15)
16. **Update kubectl** client to match new version

### Rollback Gates (validate after each major step)

- API server responding: `kubectl get nodes`
- CoreDNS resolving: `kubectl run test --image=busybox --rm -it -- nslookup kubernetes`
- Critical workloads healthy (readiness probes passing)
- No unexpected CrashLoopBackOff or eviction storms
- Metrics pipeline functioning
- No rollback of node groups in progress

If any gate fails: STOP. Control plane upgrade is irreversible, but subsequent
steps can be halted.

### Rollback Matrix

| Component | Reversible? | How |
|-----------|------------|-----|
| Control plane | NO | Must fix forward |
| Addons | YES | Downgrade to previous version |
| Managed node groups | PARTIAL | Can halt; completed nodes stay at new version |
| Karpenter nodes | YES | Revert EC2NodeClass, delete drifted nodes |
| Self-managed nodes | YES | Revert launch template, terminate new nodes |
| Fargate pods | YES | Redeploy with previous config |

## Step 17: Report Format

```
## EKS Upgrade Readiness Report
**Cluster:** <name> (<region>)
**Current Version:** <current>
**Target Version:** <target>
**Assessment Date:** <date>
**IaC Owner:** <Terraform|CloudFormation|eksctl|Manual|...>
**Overall Readiness:** READY / NOT READY / READY WITH WARNINGS / CANNOT DETERMINE

### Pre-Upgrade Health Baseline
- [PASS/FAIL] (confidence: HIGH) All nodes Ready — <count>/<total>
- [PASS/FAIL] (confidence: HIGH) No pending CSRs
- [PASS/FAIL] (confidence: HIGH) No crash-looping system pods
- [PASS/FAIL] (confidence: HIGH) DNS resolution working
- [PASS/FAIL] (confidence: HIGH) Metrics server responding

### Infrastructure Prerequisites
- [PASS/FAIL] (confidence: HIGH) Subnet IP availability — <X> IPs available (mode: <prefix-delegation|standard|custom-networking>)
- [PASS/FAIL] (confidence: HIGH) EKS IAM role — valid trust policy
- [PASS/FAIL/N/A] (confidence: HIGH) KMS key access
- [PASS/FAIL] (confidence: HIGH) EC2 vCPU quota — <X> available vs <Y> needed
- [PASS/FAIL] (confidence: HIGH) EBS volume quota — <X> available vs <Y> needed

### EKS Upgrade Insights
- [PASS/FAIL/UNKNOWN] (confidence: HIGH) Insights result — <summary>

### Data Plane Inventory
- Managed Node Groups: <count> (versions: <list>)
- Self-Managed ASGs: <count> (versions: <list>)
- Karpenter NodePools: <count> (version: <karpenter-ver>)
- Fargate Profiles: <count>
- Total Nodes: <count>

### Blockers (must fix before upgrade)
1. [FAIL] (confidence: HIGH) <description> — <remediation reference>

### Warnings (recommended before upgrade)
1. [WARN] (confidence: MEDIUM) <description> — <recommendation>

### Passing Checks
1. [PASS] (confidence: HIGH) <description>

### Unknown / Not Assessed
1. [UNKNOWN] <gate> — <reason> (e.g., "AccessDenied on eks:ListInsights")

### Upgrade Plan
<execution order from Step 16>

### Post-Upgrade Validation Checklist
<from Step 15>

### Estimated Timeline
- Control plane: ~30 min
- Addons: ~5 min each
- Node groups: ~<X> min per group (based on size and maxUnavailable)
- Total: ~<Y> min
```

## References

See `references/` directory for:
- `api-deprecations.md` — full K8s API removal schedule by version
- `addon-version-matrix.md` — EKS addon compatibility per version (static fallback)
- `capacity-planning.md` — FDCR/ODCR and surge capacity guidance
- `upgrade-troubleshooting.md` — common failures, feature removals, and tools
