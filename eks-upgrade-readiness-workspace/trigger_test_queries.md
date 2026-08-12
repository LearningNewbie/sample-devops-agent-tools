# EKS Upgrade Readiness - Trigger Test Queries

Test these queries with Claude Code to verify the skill activates correctly.

## Expected to TRIGGER the skill (should_trigger: true)

### Test 1: Basic upgrade readiness
```
I need to upgrade my EKS cluster from 1.29 to 1.30 in us-west-2. Can you check if we're ready? The cluster is called prod-payments and runs about 200 nodes with Karpenter.
```
**Expected:** Skill should activate and attempt to run readiness checks

### Test 2: Extended support deadline
```
We're on EKS 1.27 and getting emails about extended support ending soon. What do we need to do before the auto-upgrade kicks in? We have a ton of Helm releases and I'm worried about deprecated APIs.
```
**Expected:** Skill should activate and focus on API deprecation + timeline

### Test 3: Post-upgrade troubleshooting
```
kubectl is giving me 'unable to recognize' errors after we upgraded to 1.31 last week — some of our CronJobs and HPAs stopped working. Can you help figure out what broke?
```
**Expected:** Skill should activate to identify deprecated APIs

### Test 4: Safety validation
```
Is it safe to upgrade our staging EKS cluster to 1.32? We use the community ingress-nginx controller and have a bunch of StatefulSets running PostgreSQL. Also running AL2 nodes.
```
**Expected:** Skill should activate and check version-specific gates (AL2 availability for 1.32+)

### Test 5: Multi-version jump
```
My team wants to jump from EKS 1.28 to 1.31 — is that possible in one shot or do we need to go through each version? And what's the risk if we do blue-green instead?
```
**Expected:** Skill should activate and explain one-minor-version-at-a-time rule

### Test 6: IPVS mode check
```
Can you check if our kube-proxy is using IPVS mode? We're planning to go to 1.35 next quarter and I heard there might be issues.
```
**Expected:** Skill should activate and check version-specific gate (IPVS deprecated in 1.35)

### Test 7: Karpenter AMI behavior
```
We run Karpenter v0.32 with EC2NodeClasses pinned to a specific AMI. Will the nodes automatically pick up the new AMI after we upgrade the control plane to 1.30?
```
**Expected:** Skill should activate and assess Karpenter configuration

### Test 8: Service quota check
```
Can you check our service quotas for EC2 vCPUs and EBS volumes? We're about to do a rolling node group upgrade on a 100-node cluster and I want to make sure we have headroom.
```
**Expected:** Skill should activate for capacity planning / quota check

---

## Expected to NOT TRIGGER the skill (should_trigger: false)

### Test 9: API server throttling (general EKS troubleshooting)
```
I'm getting 429 throttling errors on my EKS cluster API server. kubectl get pods takes 5 seconds. The cluster is on 1.30 and has about 500 pods.
```
**Expected:** Skill should NOT activate (not upgrade-related)

### Test 10: Security review (not upgrade-specific)
```
Can you review the security posture of my EKS cluster? I want to check RBAC, pod security standards, network policies, and whether we're using IRSA or Pod Identity correctly.
```
**Expected:** Skill should NOT activate (security audit, not upgrade)

### Test 11: Initial Karpenter setup (not upgrade)
```
Help me set up Karpenter on my new EKS cluster. I need NodePools for both x86 and Graviton instances with consolidation enabled.
```
**Expected:** Skill should NOT activate (initial setup, not upgrade)

### Test 12: OOM troubleshooting (not upgrade-related)
```
My pods keep getting OOMKilled on my EKS cluster. The nodes show 85% memory utilization. How do I right-size the resource requests?
```
**Expected:** Skill should NOT activate (resource tuning, not upgrade)

### Test 13: ECS to EKS migration (not EKS upgrade)
```
I want to migrate my application from ECS to EKS. What's the best approach for a Java Spring Boot app with a PostgreSQL database?
```
**Expected:** Skill should NOT activate (migration, not upgrade)

### Test 14: Terraform generation (IaC, not upgrade assessment)
```
Can you generate a Terraform module for an EKS cluster with managed node groups, VPC CNI, and CoreDNS? Target version 1.30 in us-east-1.
```
**Expected:** Skill should NOT activate (infrastructure provisioning, not upgrade assessment)

### Test 15: Cost optimization (not upgrade-related)
```
Our EKS cluster costs are too high — $15K/month. Can you analyze where the money is going and suggest optimizations? We have 50% of nodes running at under 20% CPU.
```
**Expected:** Skill should NOT activate (cost analysis, not upgrade)

### Test 16: RDS upgrade (wrong service)
```
We need to upgrade our RDS PostgreSQL from 14 to 16. Can you check addon compatibility and if there are any breaking changes?
```
**Expected:** Skill should NOT activate (RDS, not EKS)

---

## How to Test

1. Open Claude Code in the terminal or desktop app
2. Make sure the eks-upgrade-readiness skill is installed
3. Type one of the test queries above
4. Observe whether Claude mentions using or consulting the eks-upgrade-readiness skill
5. For "should trigger" tests: verify the skill activates
6. For "should NOT trigger" tests: verify Claude answers without the skill

## Pass Criteria

- **Should trigger queries (1-8):** At least 7/8 should activate the skill (87.5% trigger rate)
- **Should NOT trigger queries (9-16):** All 8 should NOT activate the skill (100% precision)
- **Functional evals (evals.json):** 16 scenarios covering normal, edge, and failure cases
- **Deterministic rules:** UNKNOWN ≠ PASS, READY not allowed with UNKNOWN gates

## Notes

- Trigger rate depends on Claude's skill selection logic, not just the description
- Some edge cases (like query 8 about service quotas) might be borderline
- The skill description aims for high recall (catch all upgrade-related queries) while excluding non-upgrade EKS work
