# Legacy Module

cloudformation/ 으로 마이그레이션 완료된 이전 스크립트 아카이브.
**사용하지 마세요** — `cloudformation/` 디렉토리의 번호순 스크립트를 사용하세요.

## 마이그레이션 매핑
| Legacy | 현재 |
|--------|------|
| 1.install-dev-tools.sh | cloudformation/00.check-prerequisites.sh |
| 2.set-aws-env.sh | cloudformation/03.eks-setup-env.sh |
| 3.kms-setup.sh | cloudformation/03.eks-setup-env.sh (통합) |
| 4.deploy-all-vpcs.sh | cloudformation/01.deploy-all-vpcs.sh |
| 5.deploy-tgw.sh | cloudformation/02.deploy-tgw.sh |
| eks-*.sh | cloudformation/03~06 스크립트 |
| deploy-lbc.sh | cloudformation/05.deploy-lbc.sh |
