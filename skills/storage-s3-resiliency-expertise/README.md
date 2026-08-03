# S3 Resiliency Review Skill

A skill for AWS DevOps Agent that performs a structured, **read-only** resiliency,
security, and data protection review of Amazon S3 buckets and produces a rated
report with prioritized findings and remediation guidance.

## What it does

Given one or more S3 bucket names, the skill collects each bucket's configuration
using read-only control-plane API calls and evaluates it across nine dimensions:

1. **Versioning** — protection against overwrites and deletes
2. **Replication** — cross-region / cross-account redundancy (four-quadrant risk model)
3. **Object Lock** — immutability / WORM protection
4. **Bucket policy** — defensive Deny statements and transport security
5. **Block Public Access** — bucket- and account-level, cross-referenced with ACLs and policy
6. **Default encryption** — SSE-S3 / SSE-KMS / DSSE-KMS and Bucket Key
7. **Ownership controls** — ACL posture and BucketOwnerEnforced migration
8. **Server access logging** — logging or CloudTrail S3 data events for audit trail
9. **Static website hosting** — public-by-design exposure checks

Each bucket receives a **Resiliency Rating** (High / Medium / Low / Indeterminate)
with per-dimension findings. Reviews are routed automatically:

- **1 bucket** → full single-bucket report
- **2–20 buckets** → fleet report (summary matrix + details)
- **21+ buckets** → batched fleet review with a manifest for progress tracking and resume

## Prerequisites

The DevOps Agent role must have **read-only** permissions for the review to
produce complete results. These are IAM action names (which differ from the API
call names for some S3 operations):

```
s3:ListBucket
s3:ListAllMyBuckets
s3:GetBucketVersioning
s3:GetReplicationConfiguration
s3:GetBucketObjectLockConfiguration
s3:GetBucketPolicy
s3:GetBucketPublicAccessBlock
s3:GetAccountPublicAccessBlock
s3:GetEncryptionConfiguration
s3:GetBucketOwnershipControls
s3:GetBucketAcl
s3:GetBucketLogging
s3:GetBucketWebsite
s3:GetBucketCORS
s3:GetBucketLocation
cloudtrail:DescribeTrails
cloudtrail:GetEventSelectors
```

(`sts:GetCallerIdentity` is also used to resolve the account ID; it requires no
IAM permission.)

Most of these are covered by `AIDevOpsAgentAccessPolicy`. If a check lacks
permission, the skill reports it as "Unable to verify — access denied" and caps the
Resiliency Rating at Medium rather than guessing the configuration.

The skill **never** reads object data (`GetObject`) and **never** performs any
write, create, update, or delete operation.

## How to use it with DevOps Agent

Works with the **Chat** and **Investigations / Incident RCA** subagents. Describe
the task in natural language — you do not need to name the skill:

- "Run an S3 resiliency review on `my-production-bucket`."
- "Is my bucket `app-data-prod` safe? Audit its security and data protection."
- "Review these buckets for resiliency: `logs-bucket`, `assets-bucket`, `backups-bucket`."
- "What's the disaster recovery posture of `analytics-raw`?"
- "Check versioning, replication, and public access on `customer-uploads`."

The agent gathers configuration via its `use_aws` tool under the assumed role in the
target account, applies the finding logic, and returns a Markdown report artifact.

## Non-production disclaimer

> ⚠️ This skill is sample code, not intended for production use without additional
> review and testing. Users should validate in a non-production environment first.
