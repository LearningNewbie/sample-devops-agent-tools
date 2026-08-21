# Bedrock Adoption Readiness Assessor

Assess an AWS account's readiness to run Amazon Bedrock at production scale. Evaluates four dimensions: IAM governance, data retention (ZDR), quota and capacity headroom, and operational observability. Operates across both Standard Bedrock and Mantle (OpenAI models) surfaces.

## What This Skill Does

Runs a readiness assessment against your Bedrock configuration across both control planes and returns prioritized findings with specific remediation steps. Designed for teams preparing to scale Bedrock usage from experimentation to production.

**Phase 1 (this release):** D1 IAM, D2 ZDR, D3 Quota, D6 Observability - all API/metrics-driven, no dependency on customer configuration state.

**Phase 2 (future):** D4 Model Selection Fitness, D5 Cost Projection - require model invocation logging to be enabled.

**Example prompts:**
- "Review my Bedrock readiness for production"
- "Check if my Bedrock quotas can handle our projected growth"
- "Assess my Bedrock IAM permissions and ZDR configuration"
- "Am I ready to scale Bedrock to production?"
- "Bedrock operational review"
- "Audit my Bedrock security posture"

## Prerequisites

### IAM Permissions Required

The DevOps Agent role needs read-only access. Most required actions are covered by `AIDevOpsAgentAccessPolicy` (v10+):

```json
{
  "Effect": "Allow",
  "Action": [
    "bedrock:List*",
    "bedrock:Get*",
    "bedrock-runtime:List*",
    "iam:ListRoles",
    "iam:ListAttachedRolePolicies",
    "iam:ListRolePolicies",
    "iam:GetRolePolicy",
    "iam:GetPolicyVersion",
    "iam:ListPolicies",
    "organizations:ListPolicies",
    "organizations:DescribePolicy",
    "organizations:ListPoliciesForTarget",
    "servicequotas:ListServiceQuotas",
    "servicequotas:GetServiceQuota",
    "cloudwatch:GetMetricData",
    "cloudwatch:ListMetrics",
    "cloudwatch:DescribeAlarms",
    "cloudtrail:GetEventSelectors",
    "ec2:DescribeVpcEndpoints"
  ],
  "Resource": "*"
}
```

**Optional (for full D2 assessment):** `bedrock:GetAccountDataRetention` - if not available, the skill falls back to indirect evidence (Covered Model detection via CloudWatch metrics + SCP check).

**Note:** All operations are read-only. This skill does not modify any resources.

### AWS Resources

- At least one Bedrock model must have been invoked in the last 7 days for metrics-based analysis
- Organization-level SCP assessment requires the account to have Organizations API access (management account or delegated admin)

## How to Use with DevOps Agent

1. Upload this skill to your DevOps Agent Space
2. Select the "Chat tasks" subagent
3. Ensure the DevOps Agent role has the IAM permissions listed above
4. Ask natural language questions about Bedrock readiness

**Subagents:** Chat tasks, Evaluation

## Output

The skill generates a structured assessment report with:
- Overall readiness verdict (READY / READY WITH ACTIONS / NOT READY)
- Per-dimension status (ASSESSED / NOT_ASSESSED / INSUFFICIENT_DATA)
- Findings by severity with specific remediation steps
- Model inventory with per-model utilization metrics
- Priority actions sorted by urgency

## Key Features

- **Dual-surface assessment**: Checks both Standard Bedrock (AWS/Bedrock) and Mantle (AWS/BedrockMantle) namespaces
- **Per-model quota comparison**: Compares each model's peak against its specific quota (not account aggregate)
- **Cache-aware arithmetic**: Accounts for prompt caching in quota calculations (cache reads don't consume quota)
- **Covered Model detection**: Identifies compliance-relevant retention implications from metrics alone
- **Graceful degradation**: Never silently skips a dimension - reports NOT_ASSESSED with reason when data is unreachable
- **Multi-region**: Discovers and assesses all regions with Bedrock activity

## Limitations

- Phase 1 does not assess model selection fitness or cost optimization (requires invocation logging - Phase 2)
- Account-level data retention mode may require `bedrock:GetAccountDataRetention` permission not yet in standard DA policy (fallback available)
- Organization SCP assessment may be limited from member accounts without delegated admin access
- Mantle retention endpoint (`/v1/data_retention`) is a REST endpoint without SDK client - not directly assessable, uses indirect evidence

## Disclaimer

> This skill is sample code, not intended for production use without additional review and testing. Users should validate findings in a non-production environment first. Recommendations are based on AWS best practices as of the skill version date and may not reflect the latest service changes.
