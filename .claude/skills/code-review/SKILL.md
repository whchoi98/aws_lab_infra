---
name: code-review
description: Review IaC code (CF/CDK/TF) for best practices, security, naming conventions
---

Review the changed files for:
1. **Naming**: `lab-{vpc}-{tier}-{resource}-{az}{nn}` convention
2. **Tags**: Name, Environment, Project, ManagedBy required
3. **Graviton**: All instances must be arm64 (t4g/m7g/r7g)
4. **Security**: No public EC2, SSM access only, encrypted volumes
5. **Cross-stack**: Export names consistent, ImportValue correct
6. **CF Lint**: Run `cfn-lint` on YAML templates
7. **Terraform**: `terraform validate` and `terraform fmt`
