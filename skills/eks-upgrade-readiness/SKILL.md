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

## Safety First

**Before doing anything, load `references/safety-invariants.md`.** It defines
the knowledge hierarchy, hard rules, operation classification, and uncertainty
handling. Keep it in context for the entire assessment.

## Critical Warnings

- **This skill is read-only.** All commands are `describe*`, `list*`, `get*`.
  The agent does NOT execute mutating APIs. Mutations are in Step 14 and
  require explicit operator approval.
- **One minor version at a time.** EKS control plane upgrades proceed one
  minor version per operation (e.g., 1.30 → 1.31).
- **Version skew policy.** 1.28+: kubelet supports N-3. Below 1.28: N-2.
- **Addons must be upgraded AFTER the control plane** (exceptions in Step 8).
- **Auto-upgrade policy.** Clusters past the 26-month lifecycle will be
  auto-upgraded. Proactive upgrade avoids disruption.
- **Control plane rollback (July 2026+).** 7-day rollback window after upgrade.
  Conditional, not guaranteed — skill checks eligibility.
- **UNKNOWN ≠ PASS.** Any gate that cannot be assessed MUST be UNKNOWN, never
  PASS. Overall verdict cannot be READY while any gate is UNKNOWN.

## Evidence Completeness

Uses `references/required-check-registry.yaml` to track checks performed,
skipped, or blocked. EC = checks_performed / total_applicable × 100%.
EC < 50% produces a mandatory warning.

## Grading and Confidence

| Level | Meaning | When to Use |
|-------|---------|-------------|
| HIGH (90%+) | Confirmed from authoritative source | EKS Insights API, direct kubectl query, AWS API response |
| MEDIUM (60-89%) | Inferred from available data | Partial kubectl access, version matching heuristics |
| LOW (30-59%) | Limited data, possible gaps | No kubectl, no logging enabled, partial API access |
| UNKNOWN | Cannot determine | Tool unavailable, no data, access denied |

**False-positive guards:**
- Empty query result ≠ PASS (mark UNKNOWN)
- No kubectl ≠ N/A for everything (AWS APIs still work)
- EKS Insights PASSING ≠ skip other checks (covers a subset only)
- Addon "compatible" ≠ "recommended"
- Pagination not exhausted → confidence LOW

**Verdict rules:**
- READY: All gates PASS or WARN
- READY WITH WARNINGS: At least one WARN, no FAIL/UNKNOWN
- NOT READY: Any gate FAIL
- CANNOT DETERMINE: Any gate UNKNOWN

Format: `[PASS|FAIL|WARN|UNKNOWN|N/A] (confidence: HIGH) — <evidence>`

## Cost Awareness

- **EKS Insights API** (Step 3) is free — always use first.
- **CloudWatch Logs Insights** cost ~$0.0076/GB scanned. Default to 60-min windows.
- **Extended support** costs $0.60/cluster/hour — upgrading saves money.
- **Surge nodes** incur temporary EC2 cost during overlap period.

## Required Permissions

**AWS IAM** — see README.md "Prerequisites → IAM Permissions" for the full
read-only action list (`eks:Describe*`, `eks:List*`, `ec2:Describe*`,
`autoscaling:Describe*`, `iam:GetRole`, `servicequotas:GetServiceQuota`).

**Kubernetes RBAC** (only if `kubectl` access is available — the assessment
still runs on AWS APIs alone without it, at lower confidence for CRD/Helm/PDB
checks). Read-only `ClusterRole` covering every `kubectl get`/`describe` used
in this skill:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: eks-upgrade-readiness-readonly
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - pods
      - configmaps
      - secrets
      - events
      - persistentvolumeclaims
      - certificatesigningrequests
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["admissionregistration.k8s.io"]
    resources:
      - validatingwebhookconfigurations
      - mutatingwebhookconfigurations
    verbs: ["get", "list", "watch"]
  - apiGroups: ["karpenter.sh"]
    resources: ["nodepools", "nodeclaims"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["karpenter.k8s.aws"]
    resources: ["ec2nodeclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["crd.k8s.amazonaws.com"]
    resources: ["eniconfigs"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes"]
    verbs: ["get", "list", "watch"]
```

Bind with a `ClusterRoleBinding` to the identity the agent assumes (e.g. via
IRSA/Pod Identity or an EKS access entry). `secrets` read access is required
only for the Helm stored-manifest scan (Step 4) — omit that rule and accept
UNKNOWN on Helm checks if a customer's security policy disallows it.

---

## Step 1: Gather Cluster Context

```bash
aws eks describe-cluster --name <cluster-name> --region <region>
```

Extract: `cluster.version`, `platformVersion`, `status` (must be ACTIVE),
`kubernetesNetworkConfig`, `logging.clusterLogging` (audit log must be enabled),
`resourcesVpcConfig.subnetIds`, `tags` (IaC ownership detection).

Determine **target version**: ask user or default to current + 1 minor.
Confirm target is in standard support via the EKS release calendar.

## Step 2: Verify Infrastructure Prerequisites

Check these — failures are **BLOCKERs**:

1. **Subnet IP availability** — need ≥5 IPs per cluster subnet. Mode-aware:
   standard IPv4, prefix delegation, custom networking, IPv6, SGP.
   Use `aws ec2 describe-subnets` with cluster subnet IDs.
2. **EKS IAM role** — verify role exists with `eks.amazonaws.com` trust.
3. **KMS key** (if encryption enabled) — verify cluster role has key access.
4. **Service quota headroom** — EC2 vCPU (L-1216C47A) and EBS gp3 (L-7A658000)
   must have room for surge nodes. Use `aws service-quotas get-service-quota`.

VPC CNI mode detection:
```bash
kubectl get ds aws-node -n kube-system -o json | jq '.spec.template.spec.containers[0].env[] | select(.name | test("PREFIX_DELEGATION|CUSTOM_NETWORK|POD_SECURITY_GROUP"))'
```

## Step 3: Check EKS Upgrade Insights

**Primary authoritative signal.** Always query first.

```bash
aws eks list-insights --cluster-name <cluster> \
  --filter '{"categories":["UPGRADE_READINESS"],"kubernetesVersions":["<target>"]}'
aws eks describe-insight --cluster-name <cluster> --id <insight-id>
```

| Status | Gate | Action |
|--------|------|--------|
| ERROR | FAIL | Must fix before upgrade |
| WARNING | WARN | Recommended fix |
| PASSING | PASS | No action |
| None returned | UNKNOWN | Continue other checks |

**Critical:** Insights does NOT cover Helm stored manifests, CRD deprecations,
StatefulSets, Karpenter, service quotas, PDBs, or capacity planning.

## Step 4: API Deprecation Analysis

Check version-specific removal gates relevant to user's target:
- ≥1.33: AL2 AMI unavailable (Critical)
- ≥1.35: kube-proxy IPVS deprecated; ≥1.36: removed
- ≥1.25: Dockershim and PodSecurityPolicy removed
- ≥1.23: In-tree EBS provisioner deprecated

**Helm stored manifests** — the #1 missed blocker. Scan latest deployed
release secrets for deprecated `apiVersion` lines:
```bash
kubectl get secrets -A -l owner=helm,status=deployed
# Decode: base64 -d | base64 -d | gunzip | jq -r '.manifest'
```

**Third-party CRD deprecations** — check Istio, cert-manager, Karpenter,
Flux, Argo, Prometheus Operator versions against known deprecation timelines.

Tools: `kubent`, `pluto detect-all-in-cluster`, `helm mapkubeapis --dry-run`.
See `references/api-deprecations.md` for full removal schedule.

## Step 5: Addon Compatibility Check

**Managed addons:** Use live API to build compatibility matrix:
```bash
aws eks list-addons --cluster-name <cluster>
aws eks describe-addon --cluster-name <cluster> --addon-name <name>
aws eks describe-addon-versions --addon-name <name> --kubernetes-version <target>
```

**Self-managed addons:** Detect via namespace/label scanning (aws-load-balancer,
external-dns, metrics-server, cluster-autoscaler, cert-manager, ingress-nginx,
argocd, flux). Extract image tag and validate against K8s support matrix.

**Upgrade order:** Pre-CP: Karpenter, Cluster Autoscaler, incompatible webhooks.
Post-CP: kube-proxy → vpc-cni → coredns → CSI drivers → others → self-managed.

See `references/addon-version-matrix.md` for static fallback reference.

## Step 6: Full Data Plane Inventory

Inventory ALL node populations. See `references/data-plane-inventory.md` for
complete detection commands.

- **MNG:** `aws eks list-nodegroups` + `describe-nodegroup` for each
- **Self-managed ASGs:** Find by cluster tag in `describe-auto-scaling-groups`
- **Karpenter:** NodePools, EC2NodeClasses, controller version and health
- **Auto Mode:** Check `cluster.computeConfig.enabled`
- **Fargate:** `aws eks list-fargate-profiles` + describe each
- **Kubelet versions:** `kubectl get nodes` — confirm within skew window

Version skew: target 1.X → kubelet must be ≥1.(X-3) for X≥28, ≥1.(X-2) for X<28.
Violations are **FAIL**.

## Step 7: AL2 → AL2023 Migration Assessment

If AL2 detected and target ≥1.33: **CRITICAL** blocker.
If AL2 detected and target <1.33: **WARNING** (AL2 EOL June 2025).

Assess: bootstrap method (bootstrap.sh vs nodeadm), custom AMIs, user data
compatibility (yum→dnf, kubelet-extra-args→NodeConfig), cgroup v2 workload
compatibility, IMDSv2 readiness.

See `references/al2-al2023-migration.md` for full detection commands and
migration strategy.

## Step 8: Upgrade Ordering and Pre-Upgrade Alignment

**Pre-CP:** Karpenter (if needed), Cluster Autoscaler (must match target),
admission webhooks with `failurePolicy: Fail`, custom controllers using
deprecated APIs.

**Post-CP:** Standard addon and node group upgrade order (Step 5).

Webhook check:
```bash
kubectl get validatingwebhookconfigurations -o json | jq '.items[] | select(.webhooks[].failurePolicy == "Fail")'
kubectl get mutatingwebhookconfigurations -o json | jq '.items[] | select(.webhooks[].failurePolicy == "Fail")'
```

## Step 9: PDB, Topology Spread, and Workload Safety

**PDB blockers:** `maxUnavailable: 0`, `minAvailable` == replicas, orphaned PDBs:
```bash
kubectl get pdb -A -o json | jq '.items[] | select(.status.disruptionsAllowed == 0)'
```

**Pre-drain safety (DRAIN-01 to DRAIN-06):** Bare pods, emptyDir data loss,
custom finalizers, EBS AZ-pinning, webhook deadlock, CoreDNS SPOF.
See `references/pre-drain-safety.md` for full detection commands.

**TopologySpreadConstraints:** Flag multi-replica deployments without topology spread.

**StatefulSet safety:** Check `terminationGracePeriodSeconds != 0`, PVC retention
policy, single-replica without PDB, update strategy.

**Scaled-to-zero workloads:** Detect and flag for separate validation.

## Step 10: Pre-Upgrade Cluster Health Baseline

Confirm healthy steady state before upgrade. Failures compound on unhealthy clusters.

- **Node health:** All nodes Ready, no MemoryPressure/DiskPressure/PIDPressure
- **Pending CSRs:** Indicate node registration issues
- **Crash-looping system pods:** Check kube-system, monitoring, ingress namespaces
- **Metrics and DNS baseline:** Verify metrics-server and CoreDNS responding

Record baselines for post-upgrade comparison.

## Step 11: Fargate Considerations

Fargate pods upgrade when redeployed after CP upgrade. All Fargate pods must be
restarted post-upgrade. Restart command is in Step 14 (mutation, requires approval).

## Step 12: Management Plane and IaC Ownership Detection

Detect management method to route remediation correctly:

| Detection | Management Plane | Mutation Routing |
|-----------|-----------------|-----------------|
| ACK CRD + Cluster CR | ACK | Patch ACK Cluster CR |
| ACK CR with `kro.run/owned` | KRO over ACK | Patch kro instance |
| Tags: `terraform:*` | Terraform | Update .tf, `terraform apply` |
| Tags: `aws:cloudformation:*` | CloudFormation | Update template, stack update |
| Tags: `aws:cdk:*` | CDK | Update construct, `cdk deploy` |
| Tags: `eksctl.cluster.k8s.io/*` | eksctl | Update config, `eksctl upgrade` |
| Labels: `argocd.argoproj.io/*` | ArgoCD | Update Git source, sync |
| Labels: `kustomize.toolkit.fluxcd.io/*` | Flux | Update Git source, reconcile |
| Tags: `pulumi:*` | Pulumi | Update program, `pulumi up` |
| None found | unknown | Block mutations until confirmed |

Route ALL remediation through the owning tool — never suggest direct AWS CLI
when IaC is detected (causes drift).

## Step 13: Autoscaler Pause During Node Rotation

During upgrades, autoscalers can interfere with rolling replacement. Check
current Karpenter consolidation config and Cluster Autoscaler scale-down state.
Recommend pausing both before node rotation and re-enabling after completion.

Pause commands are in Step 14 (mutations, require operator approval).

## Step 14: Remediation Playbook (Operator Approval Required)

> ⚠️ **ALL commands in this section are MUTATIONS.** The agent MUST NOT execute
> these — present as a playbook for operator review.

- **14.1** Helm stored manifest fix: `helm mapkubeapis` + `helm upgrade`
- **14.2** Addon conflict resolution: `aws eks update-addon --resolve-conflicts OVERWRITE`
- **14.3** Fargate pod restart: `kubectl rollout restart` across namespaces
- **14.4** PDB temporary adjustment: `kubectl patch pdb` (revert after upgrade)
- **14.5** Karpenter pause: `kubectl annotate nodepools --all "karpenter.sh/do-not-disrupt=true"`
- **14.6** CA scale-down pause: patch CA config `scale-down-enabled=false`
- **14.7** Node group upgrade: MNG via `update-nodegroup-version`, Karpenter via
  EC2NodeClass patch (drift), self-managed via launch template update

## Step 15: Post-Upgrade Functional Validation

Present as validation checklist for operator:
- DNS resolution (nslookup kubernetes.default)
- Metrics server (kubectl top nodes/pods)
- Pod scheduling (run test pod)
- Load balancer health (target group check)
- IRSA / Pod Identity (sts get-caller-identity from pod)
- CoreDNS and kube-proxy pods running
- Compare against Step 10 baseline (node count, no new CrashLoopBackOff)

## Step 16: Generate Upgrade Plan and Report

**Execution Order:**
1. Pre-upgrade alignment (Karpenter/CA/webhooks)
2. Pause autoscalers
3. Control plane upgrade (15-40 min)
4. Wait for ACTIVE status
5. kube-proxy → vpc-cni → coredns → other managed addons
6. Self-managed addons
7. Node groups (one at a time, validate between)
8. Karpenter nodes (drift-based)
9. Self-managed nodes (launch template update)
10. Fargate pods (restart)
11. Re-enable autoscalers
12. Post-upgrade validation

**Rollback Matrix:**

| Component | Reversibility | Method |
|-----------|--------------|--------|
| Control plane | CONDITIONAL (7-day window) | `aws eks update-cluster-version --kubernetes-version <N-1>` |
| Addons | FULL | Downgrade to previous version |
| MNG | PARTIAL | Can halt; completed nodes stay |
| Karpenter nodes | FULL | Revert EC2NodeClass |
| Self-managed | FULL | Revert launch template |
| Fargate | FULL | Redeploy previous config |

**Rollback eligibility:** Cluster upgraded (not created) at current version,
within 7 days, single version only, status ACTIVE, no incompatible features.
Check: `aws eks list-insights --filter '{"categories":["ROLLBACK_READINESS"]}'`

## Step 17: Report Format

```
## EKS Upgrade Readiness Report
**Cluster:** <name> (<region>)
**Current Version:** <current>
**Target Version:** <target>
**Assessment Date:** <date>
**Management Plane:** <detected>
**Evidence Completeness:** <X>% (<performed>/<applicable>)
**Overall Readiness:** READY / NOT READY / READY WITH WARNINGS / CANNOT DETERMINE

### Pre-Upgrade Health Baseline
- [PASS/FAIL] (confidence: HIGH) All nodes Ready
- [PASS/FAIL] (confidence: HIGH) No pending CSRs
- [PASS/FAIL] (confidence: HIGH) No crash-looping system pods
- [PASS/FAIL] (confidence: HIGH) DNS resolution working
- [PASS/FAIL] (confidence: HIGH) Metrics server responding

### Infrastructure Prerequisites
- [PASS/FAIL] (confidence: HIGH) Subnet IP availability (mode: <type>)
- [PASS/FAIL] (confidence: HIGH) EKS IAM role valid
- [PASS/FAIL/N/A] (confidence: HIGH) KMS key access
- [PASS/FAIL] (confidence: HIGH) EC2 vCPU quota headroom
- [PASS/FAIL] (confidence: HIGH) EBS volume quota headroom

### EKS Upgrade Insights
- [PASS/FAIL/UNKNOWN] (confidence: HIGH) <summary>

### Data Plane Inventory
- Managed Node Groups: <count> (versions: <list>)
- Self-Managed ASGs: <count> (versions: <list>)
- Karpenter NodePools: <count> (version: <ver>)
- Fargate Profiles: <count>
- Total Nodes: <count>

### Blockers (must fix)
1. [FAIL] (confidence: HIGH) <description> — <remediation>

### Warnings (recommended)
1. [WARN] (confidence: MEDIUM) <description> — <recommendation>

### Passing Checks
1. [PASS] (confidence: HIGH) <description>

### Unknown / Not Assessed
1. [UNKNOWN] <gate> — <reason>

### Upgrade Plan
<execution order from Step 16>

### Rollback Window
- Rollback eligibility: ELIGIBLE / NOT ELIGIBLE / CHECK AFTER UPGRADE
- Window: 7 days from CP upgrade completion
- Note: Add-ons and node groups must be rolled back BEFORE CP

### Pre-Drain Risks
- Bare pods (DRAIN-01): <count>
- EmptyDir data loss (DRAIN-02): <count>
- EBS AZ-pinning (DRAIN-04): <count>
- Webhook deadlock (DRAIN-05): <assessment>
- CoreDNS SPOF (DRAIN-06): <status>

### Estimated Timeline
- Control plane: ~30 min
- Addons: ~5 min each
- Node groups: ~<X> min per group
- Total: ~<Y> min
```

## References

See `references/` directory for:
- `safety-invariants.md` — Hard safety rules, knowledge hierarchy, operation classification
- `required-check-registry.yaml` — All 60+ checks with IDs, categories, and severity
- `pre-flight-checks.yaml` — Blocking vs warning checks, timeouts, soak periods, rollback conditions
- `api-deprecations.md` — Full K8s API removal schedule by version
- `addon-version-matrix.md` — EKS addon compatibility per version (static fallback)
- `capacity-planning.md` — FDCR/ODCR and surge capacity guidance
- `upgrade-troubleshooting.md` — Common failures, feature removals, and tools
- `karpenter-checks.md` — Full 14-check Karpenter registry (KARP-01 to KARP-14)
- `pre-drain-safety.md` — DRAIN-01 to DRAIN-06 detection and remediation
- `al2-al2023-migration.md` — AL2→AL2023 migration assessment details
- `data-plane-inventory.md` — MNG, self-managed, Karpenter, Auto Mode, Fargate inventory commands
