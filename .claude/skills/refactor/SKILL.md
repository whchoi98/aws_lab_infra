---
name: refactor
description: Refactor IaC code while maintaining consistency across CF/CDK/TF
---

When refactoring:
1. Apply the same change to all 3 IaC formats (CF, CDK, Terraform)
2. Maintain naming convention consistency
3. Update deploy scripts if resource names change
4. Run validation (cfn-lint, cdk synth, terraform validate)
5. Update CLAUDE.md if architecture changed
