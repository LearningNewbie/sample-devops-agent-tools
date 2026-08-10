# Changelog

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
