# CloudFormation Module

Shell + CloudFormation 방식의 인프라 배포.

## Structure
- `00-09.*.sh` — 번호순 배포 스크립트
- `99.eks-cleanup.sh` — 정리
- `templates/` — CloudFormation YAML 템플릿 (7개)
- `check-prerequisites.sh` — 도구 점검

## Execution Order
00 → 01 → 02 → 03(source) → 04 → 05 → 06 → 07 → 08 → 09

## Key Patterns
- 템플릿 경로: `${SCRIPT_DIR}/templates/`
- CF PrefixList: `aws ec2 describe-managed-prefix-lists`
- 스택 이름: DMZVPC, VPC01, VPC02, TGW, Valkey, Aurora
- Export 패턴: `${AWS::StackName}-<suffix>`
