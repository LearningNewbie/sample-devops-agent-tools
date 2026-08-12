# Changelog

## 2.0.0

Major rewrite addressing PR #48 review feedback. Breaking changes to step
numbering and report format.

### Must-Fix Items Addressed

1. **EKS Upgrade Insights as primary signal** — Step 3 now explicitly declares
   Insights as the primary authoritative signal. UNKNOWN verdict (not PASS) when
   Insights is unavailable or returns no data. Pagination enforced.

2. **Complete data plane inventory** — New Step 6 inventories ALL node
   populations: Managed Node Groups (with DescribeNodegroup details),
   self-managed ASGs (via autoscaling API + launch template inspection),
   Karpenter (NodePools + EC2NodeClasses), Auto Mode, and Fargate profiles.
   Kubelet version map across all nodes with skew validation.

3. **Live addon API usage** — Step 5 uses `DescribeAddon` + `DescribeAddonVersions`
   as primary source. Self-managed addon detection via deployment/Helm scan.
   Static addon-version-matrix.md is now explicitly a fallback-only reference.

4. **AL2→AL2023 comprehensive migration** — New Step 7 covers launch template
   analysis, custom AMI detection, user data bootstrap differences (bootstrap.sh
   → nodeadm/NodeConfig), cgroup v2 compatibility, IMDSv2 defaults, yum→dnf.

5. **Mutations separated into Remediation Playbook** — New Step 14 consolidates
   ALL mutating commands (helm upgrade, rollout restarts, OVERWRITE addon
   updates, PDB patches, Karpenter annotation, CA pause). Clearly marked as
   requiring operator approval. Agent never executes these.

6. **Upgrade ordering refined** — New Step 8 explicitly defines pre-upgrade
   alignment (Karpenter, CA, webhooks may need update BEFORE control plane) vs
   post-upgrade addon/node-group sequence.

7. **Deterministic test cases** — evals.json expanded from 6 to 16 scenarios
   covering: N-2/N-3 mixed fleet, version skew violations, missing Insights
   (AccessDenied), custom bootstrap AL2→AL2023, pagination handling, Karpenter
   Drift disabled, GitOps/IaC detection, post-upgrade validation, self-managed
   addon detection, pre-upgrade health failure. Assertions enforce UNKNOWN≠PASS.

### Recommended Additions Addressed

1. **GitOps/IaC version ownership detection** — New Step 12 detects CF/TF/CDK/
   ArgoCD/Flux/eksctl from cluster/nodegroup tags and routes all remediation
   through the owning tool. Never suggests direct CLI if IaC-managed.

2. **VPC CNI networking modes awareness** — Step 2 subnet check is now mode-
   aware: standard, prefix delegation, custom networking, IPv6, Security Groups
   for Pods. Includes ENIConfig detection and mode-specific capacity gates.

3. **Autoscaler pause during rotation** — New Step 13 checks Karpenter
   consolidation policy and CA scale-down state. Pause commands in Step 14.

4. **Pre-upgrade cluster health baseline** — New Step 10 validates all nodes
   Ready, no pending CSRs, no crash-looping system pods, DNS resolution working,
   metrics-server responding. Any failure blocks the upgrade.

5. **Post-upgrade functional validation** — New Step 15 provides smoke tests:
   DNS, metrics-server, pod scheduling, LB health, IRSA/Pod Identity, baseline
   comparison.

### Additional Improvements

- Documented required AWS IAM permissions and Kubernetes RBAC ClusterRole
- Added AccessDenied handling protocol (mark UNKNOWN, never PASS)
- Added pagination requirements throughout (ListInsights, ListNodegroups, etc.)
- Helm scanning now checks deployed revision only (not full history)
- CRD checks are vendor-aware and version-aware (compare installed version)
- StatefulSet PVC check corrected (persistentVolumeClaimRetentionPolicy)
- MNG update algorithm documented (for capacity planning accuracy)
- Verdict rules formalized: CANNOT DETERMINE when any gate is UNKNOWN
- Trigger eval expanded to 16 queries (8 positive, 8 negative)
- Skill expanded from 11 to 17 steps
- Version bump to 2.0.0

## 1.2.0

- Add Helm manifest scanning — detects deprecated APIs in Helm release
- Add version-specific removal gates — AL2 AMI unavailability (≥1.33),
  kube-proxy IPVS deprecation (≥1.35/1.36), unmaintained ingress-nginx
- Add service quota headroom checks
- Add StatefulSet safety checks
- Add more comprehensive Karpenter checks
- Add scaled-to-zero workload detection
- Add grading guards with confidence levels
- Add third-party CRD API deprecation checks
- Add cost awareness section
- Add conditional evaluation logic — version-gated checks only when relevant
- Expand pre-upgrade checklist with new checks
- Version bump to 1.2.0

## 1.1.0

- Add infrastructure prerequisites check (subnet IPs, IAM role, KMS key)
- Add Karpenter Drift and node expiry handling
- Add TopologySpreadConstraints validation
- Add Fargate pod restart requirement (Step 9)
- Add feature-specific removals (Dockershim, PodSecurityPolicy, in-tree storage)
- Add detection tools: kubent, pluto, kubectl-convert, eksup, GoNoGo
- Add blue-green cluster alternative for large upgrades
- Add EKS release calendar and auto-upgrade policy context
- Add EKS Auto Mode awareness
- Add rollback matrix
- Expand from 9 steps to 11 steps
- Align fully with AWS EKS Best Practices Guide cluster-upgrades section

## 1.0.0

- Initial version
- 9-step upgrade readiness assessment workflow
- API deprecation analysis with version-specific removal matrix
- Addon compatibility check against target EKS version
- Node group version skew and AMI readiness validation
- Pod Disruption Budget validation for drain safety
- Capacity planning with surge calculation and reservation guidance
- Structured upgrade plan generation with rollback gates
- Reference documents for API deprecations, addon matrix, capacity planning, and troubleshooting
