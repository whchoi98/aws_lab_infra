# CloudFormation Module

Shell + CloudFormation 방식의 인프라 배포.

## Structure
- `00-15.*.sh` — 번호순 배포 스크립트 (18개)
- `99.eks-cleanup.sh` — 정리
- `templates/` — CloudFormation YAML 템플릿 (9개)

## Execution Order
00(check) → 00(vscode) → 01 → 02 → 03(source) → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11 → 12 → 13 → 14 → 15

## Scripts
| Script | Description |
|--------|-------------|
| 00.check-prerequisites.sh | 도구 자동 점검/설치 |
| 00.deploy-vscode-server.sh | VSCode Server (m7g.xlarge) |
| 01.deploy-all-vpcs.sh | 3 VPCs (병렬) |
| 02.deploy-tgw.sh | Transit Gateway |
| 03.eks-setup-env.sh | EKS 환경변수 (source) |
| 04.eks-create-cluster.sh | eksctl 클러스터 |
| 05.deploy-lbc.sh | LBC v3.1.0 (Pod Identity) |
| 06.deploy-karpenter.sh | Karpenter v1.9.0 |
| 07.deploy-valkey.sh | Valkey (cache.r7g.large x2) |
| 08.deploy-aurora.sh | Aurora MySQL (db.r7g.large x2) |
| 09.deploy-app.sh | 앱 배포 |
| 10.deploy-opensearch.sh | OpenSearch (r7g.large.search x2) |
| 11.create-s3-buckets.sh | S3 20 buckets |
| 12.create-dynamodb-tables.sh | DynamoDB 20 tables |
| 13.create-lambda-functions.sh | Lambda 20 functions |
| 14.deploy-msk.sh | MSK (kafka.m7g.large x2) |
| 15.enable-detailed-monitoring.sh | EC2 Detailed Monitoring |
| 99.eks-cleanup.sh | 정리 |

## Templates (9개)
| Template | Stack |
|----------|-------|
| vscode_server_secure.yaml | VSCode Server |
| 1.DMZVPC.yaml | DMZ VPC |
| 2.VPC01.yaml | VPC01 |
| 3.VPC02.yaml | VPC02 |
| 4.TGW.yaml | Transit Gateway |
| aurora-mysql-stack.yaml | Aurora MySQL |
| valkey-cluster-stack.yaml | Valkey |
| opensearch-stack.yaml | OpenSearch |
| msk-stack.yaml | MSK |

## Key Patterns
- 템플릿 경로: `${SCRIPT_DIR}/templates/`
- CF PrefixList: `aws ec2 describe-managed-prefix-lists`
- 스택 이름: DMZVPC, VPC01, VPC02, TGW, Valkey, Aurora, OpenSearch, MSK
- Export 패턴: `${AWS::StackName}-<suffix>`
