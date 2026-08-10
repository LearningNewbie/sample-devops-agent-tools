# EKS Upgrade Capacity Planning

This reference covers capacity planning for EKS node group upgrades,
including surge node calculations and Capacity Reservation strategies.

## Surge Node Calculation

During a managed node group upgrade, nodes are replaced via rolling update:
1. ASG scales up (new nodes launched with updated launch template)
2. Old nodes are cordoned and drained
3. Old nodes are terminated
4. ASG scales back down

### Formula

```
Surge nodes per AZ = ceil(nodes_per_az * maxUnavailablePercentage / 100)
Total surge at peak = surge_per_az * number_of_azs
```

### Examples

| Nodes/AZ | maxUnavailable | Surge/AZ | Total (3 AZ) |
|----------|---------------|----------|--------------|
| 5 | 33% | 2 | 6 |
| 10 | 25% | 3 | 9 |
| 20 | 33% | 7 | 21 |
| 50 | 20% | 10 | 30 |

## Capacity Reservation Strategies

For large clusters or instance types with limited availability,
use EC2 Capacity Reservations to guarantee surge capacity.

### On-Demand Capacity Reservations (ODCR)

- Immediate availability, billed whether used or not
- Best for: short upgrade windows where you want guaranteed capacity
- Create just before upgrade, cancel immediately after

### Flexible Duration Capacity Reservations (FDCR)

- Scheduled future capacity, minimum 24-hour duration
- Best for: planned upgrades with known schedules
- Create days in advance, auto-activate at scheduled time

### Targeting Strategies

| Strategy | How It Works | When to Use |
|----------|-------------|-------------|
| Open match | Any instance in the AZ consumes slots | Single workload in the AZ |
| Targeted + Resource Group | Only ASG instances consume slots | Multiple workloads in same AZ |

### Resource Group + ASG Targeting (Recommended)

```bash
# 1. Create resource group
aws resource-groups create-group \
  --name eks-upgrade-capacity \
  --configuration \
    '{"Type":"AWS::EC2::CapacityReservationPool"}' \
    '{"Type":"AWS::ResourceGroups::Generic","Parameters":[{"Name":"allowed-resource-types","Values":["AWS::EC2::CapacityReservation"]}]}'

# 2. Add CRs to group
aws resource-groups group-resources \
  --group eks-upgrade-capacity \
  --resource-arns arn:aws:ec2:<region>:<account>:capacity-reservation/<cr-id>

# 3. Configure ASG to target the group
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <asg-name> \
  --capacity-reservation-specification \
    '{"CapacityReservationTarget":{"CapacityReservationResourceGroupArn":"arn:aws:resource-groups:<region>:<account>:group/eks-upgrade-capacity"}}'
```

### Important Notes

- FDCRs start as "targeted" — must switch to "open" after activation OR use resource group
- Cannot modify instance eligibility while instances are consuming the reservation
- If using "open" match, other workloads with the same instance type in the AZ may consume slots
- Calculate reservation size as: existing nodes + surge nodes (all get replaced during rolling update)

## When NOT to Use Capacity Reservations

- Instance types with broad availability (t3, m5, m6i in major regions)
- Small clusters (< 10 nodes) where InsufficientCapacity is unlikely
- Clusters using diversified instance types (Karpenter with multiple types)
- Spot-based node groups (CRs are for On-Demand only)

## Troubleshooting Capacity Issues During Upgrade

| Symptom | Cause | Resolution |
|---------|-------|-----------|
| `InsufficientInstanceCapacity` during upgrade | AZ lacks capacity for instance type | Use FDCR or switch to open CR match |
| CR shows "Available: 0" but no instances running | Other workloads consumed open CR slots | Switch to targeted + resource group |
| ASG not consuming targeted CR | Launch template missing CR specification | Use resource group targeting on ASG instead |
| FDCR not activating | Still in "Scheduled" state | Wait until start time; cannot modify while scheduled |
