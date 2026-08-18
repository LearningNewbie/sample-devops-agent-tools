# AWS Pricing Reference for Investigation Cost Estimation

## How to use this file

1. **Determine workload region** from the resource ARN or `aws_region` param — never default to agent space region.
2. **Query the Pricing API** using the template table below. **Always use `aws_region=us-east-1`** — the Pricing API endpoint only exists in us-east-1 and ap-south-1. Calling it from any other region (ap-northeast-1, sa-east-1, us-west-2, etc.) will fail with a connection error or AccessDeniedException. The workload region appears only as a `regionCode` filter value, never as the API endpoint region.
3. **Cache the result** as `rate_cache[(service, operation, workload_region)]` — one lookup per service+region per investigation.
4. **Fall back to floor rate** only on API failure

---

## Pricing API Query Templates

All queries follow this structure — always `aws_region=us-east-1`:
```bash
aws pricing get-products --service-code <CODE> --filters <FILTERS> --region us-east-1
```

| Service | ServiceCode | Filter field | Filter value | Floor rate | Formula |
|---|---|---|---|---|---|
| CW Logs Insights | `AmazonCloudWatch` | `usagetype` | `<PREFIX>-DataScanned-Bytes` | $0.005/GB ² | `scan_gb × rate` |
| CW GetMetricData | `AmazonCloudWatch` | `operation` | `GetMetricData` | $0.01/1K metrics | `(metrics × periods) / 1K × rate` |
| CW Contributor Insights | `AmazonCloudWatch` | `usagetype` | `<PREFIX>-CW:ContributorInsightEvents`| $0.020/1M | `rules × (events / 1M) × rate` |
| X-Ray GetTraceSummaries | `AWSXRay` | `operation` | `XRay-Traces-Scanned` | $0.50/1M traces | `traces / 1M × rate` |
| X-Ray BatchGetTraces | `AWSXRay` | `operation` | `XRay-Traces-Retrieved` | $0.50/1M traces | `traces / 1M × rate` |
| Athena SQL | `AmazonAthena` | `usagetype` | `<PREFIX>-DataScannedInTB` | $5.00/TB | `scan_tb × rate`; min 10MB |
| S3 GET/SELECT (Tier2) | `AmazonS3` | `usagetype` | `<PREFIX>-Requests-Tier2` | $0.0004/1K | `requests / 1K × rate` |
| S3 PUT/COPY/LIST (Tier1) | `AmazonS3` | `usagetype` | `<PREFIX>-Requests-Tier1` | $0.005/1K | `requests / 1K × rate` |


---

## S3 Tier Mapping

| Tier | usagetype | Operations | Floor |
|---|---|---|---|
| **Tier1** | `Requests-Tier1` | PUT, COPY, POST, **LIST** | $0.005/1K |
| **Tier2** | `Requests-Tier2` | **GET**, SELECT, HEAD | $0.0004/1K |

---

## Cross-Region Data Transfer Rates

> ⚠️ **Do NOT use a flat $0.02/GB for all regions.** Transfer rates vary significantly. AP → US is 4.5× higher than EU → US.

| Source region | Destination | Rate (confirmed via Pricing API) |
|---|---|---|
| us-east-1, us-east-2, us-west-* | Any other AWS region | $0.02/GB |
| eu-* | us-east-1 / other regions | $0.02/GB |
| ap-northeast-1 (Tokyo) | us-east-1 / other regions | $0.09/GB |
| ap-southeast-1 (Singapore) | us-east-1 / other regions | $0.09/GB |
| ap-southeast-2 (Sydney) | us-east-1 / other regions | $0.09/GB |
| ap-south-1 (Mumbai) | us-east-1 / other regions | $0.086/GB |
| sa-east-1 (São Paulo) | us-east-1 / other regions | $0.138/GB |

**Formula**: `returned_data_gb × regional_transfer_rate`

---

## Region Prefix Mapping

| Region | Prefix | Exceptions |
|---|---|---|
| us-east-1 | *(none)* | Contributor Insights: always `USE1-`; Lambda: bare `Request`; DynamoDB: bare `ReadRequestUnits` |
| us-east-2 | USE2 | |
| us-west-1 | USW1 | |
| us-west-2 | USW2 | |
| eu-west-1 | EU | X-Ray: `EUW1-` not `EU-` |
| eu-west-2 | EUW2 | |
| eu-west-3 | EUW3 | |
| eu-central-1 | EUC1 | |
| eu-north-1 | EUN1 | |
| ap-southeast-1 | APS1 | |
| ap-southeast-2 | APS2 | |
| ap-northeast-1 | APN1 | |
| ap-northeast-2 | APN2 | |
| ap-south-1 | APS3 | |
| sa-east-1 | SAE1 | |
| ca-central-1 | CAN1 | |
| me-south-1 | MES1 | |
| af-south-1 | AFS1 | |

---

## Free Operations (no cost, no lookup needed)

`logs:DescribeLogGroups`, `logs:FilterLogEvents`, `cloudtrail:LookupEvents`, `EC2/ECS/RDS Describe*`, `cloudwatch:GetMetricStatistics`, `dynamodb:DescribeTable`, `s3:HeadObject`, `lambda:GetFunction`, `lambda:GetFunctionConfiguration`, `kinesis:DescribeStream`, `kinesis:ListShards`, `kinesis:GetRecords`, `sqs:GetQueueAttributes`

---

## Reference Links

[CloudWatch](https://aws.amazon.com/cloudwatch/pricing/) · [X-Ray](https://aws.amazon.com/xray/pricing/) · [Athena](https://aws.amazon.com/athena/pricing/) · [DynamoDB](https://aws.amazon.com/dynamodb/pricing/on-demand/) · [S3](https://aws.amazon.com/s3/pricing/) · [Kinesis](https://aws.amazon.com/kinesis/data-streams/pricing/) · [SQS](https://aws.amazon.com/sqs/pricing/) · [Lambda](https://aws.amazon.com/lambda/pricing/) · [Resource Explorer](https://aws.amazon.com/resource-explorer/pricing/) · [Data Transfer](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer)
