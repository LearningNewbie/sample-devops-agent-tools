# EKS Upgrade Readiness — AWS DevOps Agent Skill

A comprehensive Amazon EKS upgrade readiness assessment skill for
[AWS DevOps Agent](https://docs.aws.amazon.com/devopsagent/latest/userguide/about-aws-devops-agent.html).
Performs pre-upgrade validation covering API deprecations, addon compatibility,
node group readiness, PDB validation, and capacity planning — then produces a
prioritized upgrade plan with rollback gates.

> ⚠️ **Non-production disclaimer.** This skill is sample code, not intended for
> production use without additional review and testing. Users should validate in
> a non-production environment first.

## Purpose

Give AWS DevOps Agent the domain knowledge to perform thorough EKS upgrade
readiness assessments. The skill covers the full upgrade lifecycle:

1. **Pre-upgrade assessment** — identify blockers before they cause downtime
2. **Compatibility validation** — APIs, addons, node versions, PDBs
3. **Capacity planning** — surge node requirements and reservation strategies
4. **Upgrade planning** — ordered execution steps with rollback gates
5. **Report generation** — structured output with READY/NOT READY verdict

## Key Capabilities

- Check EKS Upgrade Insights API for UPGRADE_READINESS findings
- Identify deprecated Kubernetes APIs and map to replacements
- Validate addon version compatibility against target EKS version
- Assess node group version skew and AMI readiness (AL2, AL2023, Bottlerocket)
- Detect problematic Pod Disruption Budgets that block drains
- Evaluate Karpenter and Cluster Autoscaler compatibility
- Calculate surge capacity requirements and recommend reservation strategies
- Generate step-by-step upgrade plans with validation gates

## Prerequisites

### IAM Permissions

The AWS DevOps Agent role needs read access to EKS and EC2:

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
eks:ListUpdates
eks:DescribeUpdate
ec2:DescribeInstances
ec2:DescribeCapacityReservations
```

All of these are covered by the AWS managed policy `AIDevOpsAgentAccessPolicy`.

### Agent Types

- **Chat tasks** — ask the agent to assess upgrade readiness for a cluster
- **Evaluation** — periodic upgrade readiness scans

## Example Prompts

- "Is my EKS cluster prod-cluster in us-east-1 ready to upgrade to 1.31?"
- "Check upgrade readiness for all my EKS clusters"
- "What deprecated APIs would break if I upgrade to Kubernetes 1.32?"
- "Plan the upgrade of my cluster from 1.30 to 1.31 including node groups"
- "Are my addons compatible with EKS 1.31?"
- "Check if my PDBs will block a node group upgrade"
- "I need to upgrade a 50-node cluster — what's the capacity plan?"

## Skill Structure

```
skills/eks-upgrade-readiness/
├── SKILL.md                  # Main skill instructions
├── README.md                 # This file
├── CHANGELOG.md              # Version history
├── .skilleval.yaml           # Agent Skill Eval config
├── evals/
│   ├── evals.json            # Functional evaluation scenarios
│   └── eval_queries.json     # Trigger test queries
└── references/
    ├── api-deprecations.md   # K8s API removal schedule by version
    ├── addon-version-matrix.md # EKS addon compatibility
    ├── capacity-planning.md  # FDCR and surge capacity guidance
    └── upgrade-troubleshooting.md # Common failures and fixes
```

## Upload Instructions

1. Zip the skill directory:
   ```bash
   cd skills/eks-upgrade-readiness
   zip -r eks-upgrade-readiness.zip . -x "*.DS_Store" "evals/report.json" "evals/benchmark.json" "evals/trigger_report.json"
   ```
2. Upload to your DevOps Agent space via the console
3. Select agent types: "Chat tasks" and "Evaluation"
4. Verify activation with: "Check EKS upgrade readiness for cluster X"
