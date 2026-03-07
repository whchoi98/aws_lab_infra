---
name: release
description: Deploy infrastructure changes to test accounts
---

1. Validate all templates (cfn-lint, cdk synth, terraform validate)
2. Deploy to lab-cf account first (canary)
3. Verify: stack status, EC2 instances, EKS cluster, app health
4. Deploy to lab-cdk and lab-terraform in parallel
5. Verify all 3 accounts match expected state
6. Update docs/runbooks/ with deployment notes
