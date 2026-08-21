# AWS Pricing Reference — S3 and Cross-Region Transfer

This file covers the two cases that cannot use the standard `operation + regionCode` Pricing API pattern from SKILL.md:
1. **S3** — uses `usagetype` tiers, not `operation`
2. **Cross-region data transfer** — reference rates (Pricing API response is multi-destination and noisy; use table below)

---

## S3 Pricing Lookup

S3 has no `operation` field — use `usagetype` with the region prefix and tier:

```bash
aws pricing get-products \
  --service-code AmazonS3 \
  --filters '[{"Type":"TERM_MATCH","Field":"usagetype","Value":"<PREFIX>-Requests-<TIER>"}]' \
  --region us-east-1
```

Replace `<TIER>` with `Tier1` or `Tier2` based on the operation. For us-east-1 omit the prefix entirely (e.g. `Requests-Tier1`).

### S3 Tier Mapping

| Tier | Operations |
|---|---|
| `Tier1` | PUT, COPY, POST, LIST |
| `Tier2` | GET, SELECT, HEAD |

### Region Prefix Mapping

| Region | Prefix |
|---|---|
| us-east-1 | *(omit — bare `Requests-Tier1`)* |
| us-east-2 | USE2 |
| us-west-1 | USW1 |
| us-west-2 | USW2 |
| eu-west-1 | EU |
| eu-west-2 | EUW2 |
| eu-west-3 | EUW3 |
| eu-central-1 | EUC1 |
| eu-central-2 | EUC2 |
| eu-north-1 | EUN1 |
| eu-south-1 | EUS1 |
| ap-southeast-1 | APS1 |
| ap-southeast-2 | APS2 |
| ap-southeast-3 | APS4 |
| ap-southeast-4 | APS6 |
| ap-northeast-1 | APN1 |
| ap-northeast-2 | APN2 |
| ap-northeast-3 | APN3 |
| ap-south-1 | APS3 |
| ap-east-1 | APE1 |
| sa-east-1 | SAE1 |
| ca-central-1 | CAN1 |
| me-south-1 | MES1 |
| me-central-1 | MEC1 |
| af-south-1 | AFS1 |
| il-central-1 | ILC1 |

---

## Cross-Region Data Transfer Rates

Baseline rates — verify current values via the [Data Transfer pricing page](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer) if precision is required.

| Source region | Rate |
|---|---|
| us-east-1, us-east-2, us-west-* | $0.02/GB |
| eu-* | $0.02/GB |
| ap-northeast-1 (Tokyo) | $0.09/GB |
| ap-southeast-1 (Singapore) | $0.09/GB |
| ap-southeast-2 (Sydney) | $0.09/GB |
| ap-south-1 (Mumbai) | $0.086/GB |
| sa-east-1 (São Paulo) | $0.138/GB |

---

## Reference Links

[CloudWatch](https://aws.amazon.com/cloudwatch/pricing/) · [X-Ray](https://aws.amazon.com/xray/pricing/) · [Athena](https://aws.amazon.com/athena/pricing/) · [DynamoDB](https://aws.amazon.com/dynamodb/pricing/on-demand/) · [S3](https://aws.amazon.com/s3/pricing/) · [Kinesis](https://aws.amazon.com/kinesis/data-streams/pricing/) · [SQS](https://aws.amazon.com/sqs/pricing/) · [Lambda](https://aws.amazon.com/lambda/pricing/) · [Resource Explorer](https://aws.amazon.com/resource-explorer/pricing/) · [Data Transfer](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer)
