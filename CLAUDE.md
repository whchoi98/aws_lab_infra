# AWS Lab Infrastructure

AWS 네트워크 및 EKS 기반 마이크로서비스 랩 환경 구축 인프라 코드 저장소.
3가지 IaC 도구(CloudFormation, CDK, Terraform)로 동일 아키텍처를 구현.

## Tech Stack

- **CloudFormation**: YAML 템플릿 + Shell 스크립트
- **CDK**: TypeScript (aws-cdk-lib v2)
- **Terraform**: HCL (AWS Provider >= 5.0)
- **EKS**: eksctl, kubectl, Helm
- **Container**: Docker (Node.js Express UI)
- **Region**: ap-northeast-2 (서울)
- **Instances**: Graviton (t4g/m7g/r7g) 전용

## Project Structure

```
aws_lab_infra/
├── shared/                    # 공유 리소스
│   ├── bilingual-app/         # 한/영 쇼핑몰 (Node.js Express + EJS)
│   ├── base-application/      # 원본 Retail Store (영어)
│   ├── deploy-app.sh          # 앱 배포 (base/bilingual 선택)
│   ├── check-prerequisites.sh # 도구 자동 점검/설치
│   └── setup-test-profiles.sh # 3계정 AWS CLI 프로파일
│
├── cloudformation/            # Shell + CloudFormation 방식
│   ├── 00-09.*.sh             # 번호순 배포 스크립트
│   ├── 99.eks-cleanup.sh      # 정리
│   └── templates/             # CF YAML 템플릿 (7개)
│
├── cdk/                       # AWS CDK TypeScript
│   ├── deploy.sh              # 전체 배포 래퍼
│   ├── bin/app.ts             # 엔트리포인트
│   └── lib/*.ts               # 6개 Stack
│
├── terraform/                 # Terraform HCL
│   ├── deploy.sh              # 전체 배포 래퍼
│   ├── main.tf                # 루트 모듈
│   └── modules/               # 4개 서브모듈
│
├── legacy/                    # 이전 스크립트 (아카이브)
└── docs/                      # 문서
```

## Key Commands

### CloudFormation 배포 (번호순)
```bash
cd cloudformation/
./00.deploy-vscode-server.sh     # VSCode Server
./01.deploy-all-vpcs.sh          # 3 VPCs (병렬)
./02.deploy-tgw.sh               # Transit Gateway
source ./03.eks-setup-env.sh     # EKS 환경변수
./04.eks-create-cluster.sh       # eksctl 클러스터
./05.deploy-lbc.sh               # LBC (Pod Identity)
./06.deploy-karpenter.sh         # Karpenter v1.9.0
./07.deploy-valkey.sh            # Valkey (ElastiCache)
./08.deploy-aurora.sh            # Aurora MySQL
./09.deploy-app.sh [base|bilingual]  # 앱 배포
./99.eks-cleanup.sh              # 정리
```

### CDK 배포
```bash
cd cdk/
./deploy.sh                      # 전체 배포 (bootstrap → deploy --all)
```

### Terraform 배포
```bash
cd terraform/
./deploy.sh                      # 전체 배포 (init → plan → apply)
```

### 앱 배포 (공통)
```bash
cd shared/
./deploy-app.sh base             # 영어 Retail Store
./deploy-app.sh bilingual        # 한/영 커스텀 쇼핑몰
```

### Docker (bilingual-app UI)
```bash
cd shared/bilingual-app/ui/
docker build -t lab-shop-ui:latest .
```

## Conventions

### Naming
- Name 태그: `lab-{vpc}-{tier}-{resource}-{az}{nn}` (예: `lab-dmzvpc-private-ec2-a01`)
- DNS-safe, 소문자, 하이픈 구분
- EC2 넘버링: 2자리 (a01, b01)

### Tags (필수)
- `Name`: 명명 규칙에 따름
- `Environment`: lab
- `Project`: aws-lab-infra
- `ManagedBy`: cloudformation | cdk | terraform | eksctl | karpenter

### Instances (Graviton 전용)
- VSCode Server: `m7g.xlarge`
- VPC EC2: `t4g.large`
- EKS 노드 (MNG): `t4g.2xlarge`
- EKS 노드 (Karpenter): `t4g.* / m7g.*` (arm64)
- Aurora: `db.r7g.large`
- Valkey: `cache.r7g.large`

### Network CIDR
| VPC | CIDR | 용도 |
|-----|------|------|
| DMZ VPC | 10.11.0.0/16 | DMZ (NFW + NAT GW + ALB) |
| VPC01 | 10.1.0.0/16 | Workload |
| VPC02 | 10.2.0.0/16 | Workload |
| Mgmt VPC | 10.254.0.0/16 | VSCode Server |

### Subnet Tiers
| Tier | Mask | 용도 |
|------|------|------|
| Public | /24 | ALB (EC2 배치 금지) |
| Private | /19 | EKS, EC2 |
| Data | /21 | Aurora, Valkey, OpenSearch |
| Attach | /24 | TGW Attachment |

### EKS
- Pod Identity (IRSA 대체)
- Karpenter v1.9.0 (arm64 전용 NodePool)
- LBC v2.13 (Helm chart 1.13.0)

## Auto-Sync Rules

When exiting Plan Mode after making changes:
1. Update this CLAUDE.md if architecture or commands changed
2. Update docs/architecture.md if components changed
3. Update module CLAUDE.md files if module responsibilities changed

## Test Accounts

| Profile | Account | IaC Tool |
|---------|---------|----------|
| lab-cf | 288761758972 | Shell + CloudFormation |
| lab-cdk | 010526248743 | AWS CDK |
| lab-terraform | 654654438809 | Terraform |
