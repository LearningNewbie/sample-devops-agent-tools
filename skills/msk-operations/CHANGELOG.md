# Changelog

## 1.0.1

- Add explicit read-only boundary to `SKILL.md` Critical Warnings — mutating
  MSK / CloudWatch commands are recommendations for the operator, not agent
  actions.
- Reframe mutating command references (`update-broker-storage`,
  `create-configuration`, `reboot-broker`) with operator-actor language.
- Guard the `reboot-broker` game-day exercise in
  `references/maintenance-operations.md` with a `UnderReplicatedPartitions = 0`
  precondition and scheduled-window framing.
- Rename README agent-type label "On-demand" → "Chat tasks" to match the
  frontmatter value and the rest of the repo.
- Note `kafka:GetBootstrapBrokers` as the single IAM action not covered by
  `AIDevOpsAgentAccessPolicy`; granted via the new `EnableMskOperations`
  block in `cloudformation/devops-agent-skill-policies.yaml`.

## 1.0.0

- Initial version
