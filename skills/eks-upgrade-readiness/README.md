# EKS Upgrade Readiness Skill

A skill for AWS DevOps Agent that performs **read-only** upgrade readiness
assessments for Amazon EKS clusters, aligned with the
[AWS EKS Best Practices Guide — Cluster Upgrades](https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html).

## Purpose

EKS upgrades can fail or cause downtime when deprecated APIs, incompatible
addons, version-skewed node groups, or misconfigured PDBs are not caught
beforehand. This skill systematically checks every dimension the Best Practices
Guide calls out and produces a READY / NOT READY / READY WITH WARNINGS verdict
with a prioritized remediation plan.

## Key Capabilities

- **Infrastructure prerequisites** — subnet IP availability, IAM role, KMS key
- **EKS Upgrade Insights** — UPGRADE_READINESS findings from the EKS API
- **API deprecation analysis** — maps removed APIs to replacements, flags
  feature-specific removals (Dockershim, PodSecurityPolicy, in-tree storage)
- **Addon compatibility** — validates each addon against the target version,
  provides upgrade order
- **Node group readiness** — managed, Karpenter (Drift, expiry, EC2NodeClass),
  Cluster Autoscaler, Auto Mode, self-managed
- **PDB and topology spread** — detects drain blockers and availability risks
- **Capacity planning** — surge calculation, ODCR/FDCR guidance, blue-green
  alternative
- **Fargate** — restart requirements after control plane upgrade
- **Structured upgrade plan** — ordered execution with rollback gates

## Prerequisites

### IAM Permissions

The DevOps Agent role needs read access to EKS, EC2, and IAM (all covered by
`AIDevOpsAgentAccessPolicy`):

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
ec2:DescribeSubnets
ec2:DescribeInstances
ec2:DescribeCapacityReservations
iam:GetRole
```

### AWS Resources

- One or more Amazon EKS clusters (any version)
- Control plane logging enabled (recommended for post-upgrade debugging)

## Limitations

- **EKS clusters only.** Does not cover EKS Anywhere, Outposts, or Local Zones.
- **Read-only by design.** The skill produces recommendations; it never executes
  `update-cluster-version`, `update-nodegroup-version`, or any mutating API.
- **No kubectl access.** The skill uses AWS APIs only. For PDB/topology spread
  checks, it relies on EKS Upgrade Insights or asks the user for information.
- **Addon version data may lag.** Always verify with `describe-addon-versions`.

## Agent Types

- **Chat tasks** — ask for upgrade readiness assessments
- **Evaluation** — periodic upgrade readiness scans

## Uploading to AWS DevOps Agent

**Option A: Import from GitHub (recommended)**

If you have a [GitHub connection configured](https://docs.aws.amazon.com/devopsagent/latest/userguide/connecting-to-cicd-pipelines-connecting-github.html) in your Agent Space, you can import this skill directly from the repository. In the DevOps Agent web app, go to Settings → Add Skill → Import from repository, then
point to `skills/eks-upgrade-readiness`. See [Importing a skill from a repository](https://docs.aws.amazon.com/devopsagent/latest/userguide/about-aws-devops-agent-devops-agent-skills.html#creating-skills) for full instructions.


> **Note:** You cannot connect the `aws-samples` GitHub organization directly because the GitHub connection setup requires admin rights on the organization. Instead, connect your personal GitHub account and select any repository from it during the connection setup. Once a GitHub connection is established, you can import skills from any public repository, including this one, even if it wasn't selected during the connection setup.

**Option B: Upload as a zip file**

1. Zip the `eks-upgrade-readiness/` directory (only including allowed extensions):

```bash
cd skills
zip -r eks-upgrade-readiness.zip eks-upgrade-readiness/ \
  -i '*.md' '*.json' '*.yaml' '*.yml' \
  -x '*/README.md' '*/.skilleval.yaml' '*/CHANGELOG.md' '*/evals/*'
```

2. In the AWS DevOps Agent web app, navigate to the **Skills** page.
3. Click **Add skill** → **Upload skill**.
4. Drag and drop the `database-rds-devops.zip` file (max 6 MB).
5. Select the agent types: **Chat tasks** and **Incident RCA**.
6. Click **Upload**.

**Option C: Upload via the Asset API**

Use the DevOps Agent Asset API to programmatically manage skills — useful for CI/CD pipelines or automation workflows. Assign to `CHAT` and
`EVALUATION` agent types. See [Managing a skill end-to-end](https://docs.aws.amazon.com/devopsagent/latest/userguide/about-aws-devops-agent-managing-assets.html#managing-a-skill-end-to-end) for the full API workflow.

## How to Use This Skill

Describe the task in natural language — you do not need to name the skill.

### Example Prompts

```
"Is my EKS cluster prod-cluster in us-east-1 ready to upgrade to 1.31?"
"Check upgrade readiness for all my EKS clusters"
"What deprecated APIs would break if I upgrade to Kubernetes 1.32?"
"Plan the upgrade of my cluster from 1.30 to 1.31 including node groups"
"Are my addons compatible with EKS 1.31?"
"Will my PDBs block a node group upgrade?"
"I need to upgrade a 50-node cluster — what capacity do I need?"
"Compare in-place vs blue-green strategy for my 200-node cluster"
```

### Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| Full assessment | "upgrade readiness", "ready to upgrade" | All 11 steps, scored report |
| Targeted check | "deprecated APIs", "addon compatibility", "PDB check" | One dimension, focused |
| Planning | "upgrade plan", "upgrade runbook" | Execution order with rollback gates |
| Comparison | "blue-green vs in-place" | Strategy recommendation |

## Skill Structure

```
eks-upgrade-readiness/
├── SKILL.md                # Main skill instructions (11-step workflow)
├── README.md               # This file
├── CHANGELOG.md            # Version history
├── .skilleval.yaml         # Agent Skill Eval config
├── evals/
│   ├── evals.json          # 6 functional evaluation scenarios
│   └── eval_queries.json   # 12 trigger tests (6 positive, 6 negative)
└── references/
    ├── api-deprecations.md       # K8s API removal schedule by version
    ├── addon-version-matrix.md   # EKS addon compatibility per version
    ├── capacity-planning.md      # FDCR/ODCR surge capacity guidance
    └── upgrade-troubleshooting.md # Tools, feature removals, blue-green
```

## Safety

This skill operates in **read-only** mode:

- No cluster modifications — upgrade actions are recommendations only
- No `update-*`, `delete-*`, or `create-*` API calls
- All findings include evidence and specific remediation steps
- The operator reviews the report and decides whether to proceed

## Non-production disclaimer

> ⚠️ This skill is sample code, not intended for production use without
> additional review and testing. Validate in a non-production environment first.
> Compatibility data and version matrices are point-in-time references — always
> verify with `aws eks describe-addon-versions` for the latest data.
