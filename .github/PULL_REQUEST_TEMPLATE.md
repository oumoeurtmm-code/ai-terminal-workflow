## Summary

<!-- What does this PR change? 1-3 bullet points. -->

-
-

## Type of Change

- [ ] Bug fix (script or documentation error)
- [ ] New lab project
- [ ] Enhancement to existing lab
- [ ] Documentation update
- [ ] FinOps content
- [ ] Repo structure / templates

## Lab(s) Affected

- [ ] 01 — Static Website
- [ ] 02 — EC2 + VPC + Security Groups
- [ ] 03 — RDS + EC2 (planned)
- [ ] 04 — Lambda + API Gateway (planned)
- [ ] 05 — Multi-tier ALB + Auto Scaling (planned)
- [ ] Repo-level (README, templates, etc.)

## Checklist

### All Changes
- [ ] Tested locally (scripts run without errors)
- [ ] No hardcoded resource names — environment variables used
- [ ] All new AWS resources have tagging applied (Project, Environment, ManagedBy)

### Script Changes
- [ ] `deploy.sh` exports all resource IDs needed by `cleanup.sh`
- [ ] `cleanup.sh` handles already-deleted resources gracefully (no hard failures)
- [ ] Cleanup script verified — runs `resourcegroupstaggingapi get-resources` and returns `[]`

### Documentation Changes
- [ ] README includes architecture diagram (Mermaid preferred)
- [ ] Step-by-step walkthrough includes screenshot prompts
- [ ] Exam notes added for certification-relevant concepts
- [ ] FinOps cost table updated
- [ ] Relative paths used (no hardcoded user paths)

## Screenshots

<!-- If this adds or changes console steps, attach screenshots. -->

## Related Issues

<!-- Closes #XX -->
