# AWS Lab Infrastructure

AWS 네트워크 및 EKS/ECS 기반 마이크로서비스 랩 환경 구축 인프라 코드 저장소.
3가지 IaC 도구(CloudFormation, CDK, Terraform)로 동일 아키텍처를 구현.
ECS는 Fargate(bilingual) + EC2(base) 2가지 launch type으로 배포.

## Tech Stack

- **CloudFormation**: YAML 템플릿 + Shell 스크립트
- **CDK**: TypeScript (aws-cdk-lib v2)
- **Terraform**: HCL (AWS Provider >= 5.0)
- **EKS**: eksctl, kubectl, Helm
- **ECS**: Fargate ARM64 + EC2 Graviton (Cloud Map service discovery)
- **Container**: Docker (Node.js Express UI)
- **Region**: ap-northeast-2 (서울)
- **Instances**: Graviton (t4g/m7g/r7g) 전용

## Project Structure

```
aws_lab_infra/
├── shared/                    # 공유 리소스
│   ├── bilingual-app/         # 한/영 쇼핑몰 (Node.js Express + EJS)
│   ├── base-application/      # 원본 Retail Store (영어)
│   ├── base-application-standalone/ # base UI 별도 배포 (ui-base namespace)
│   ├── 02.deploy-app.sh          # EKS 앱 배포 (base/bilingual 선택)
│   ├── 05.deploy-base-app.sh     # EKS base 병렬 배포 (별도 ALB+CF)
│   ├── 00.check-prerequisites.sh # 도구 자동 점검/설치
│   └── 01.setup-test-profiles.sh # 3계정 AWS CLI 프로파일
│
├── cloudformation/            # Shell + CloudFormation 방식
│   ├── 00-17.*.sh             # 번호순 배포 스크립트 (20개)
│   ├── 99.eks-cleanup.sh      # 정리
│   └── templates/             # CF YAML 템플릿 (11개)
│
├── cdk/                       # AWS CDK TypeScript
│   ├── deploy.sh              # 전체 배포 래퍼
│   ├── bin/app.ts             # 엔트리포인트
│   └── lib/*.ts               # 8개 Stack
│
├── terraform/                 # Terraform HCL
│   ├── deploy.sh              # 전체 배포 래퍼
│   ├── main.tf                # 루트 모듈
│   └── modules/               # 6개 서브모듈
│
├── legacy/                    # 이전 스크립트 (아카이브)
└── docs/                      # 문서
```

## Key Commands

### CloudFormation 배포 (번호순, 21개 스크립트)
```bash
cd cloudformation/
./00.check-prerequisites.sh      # 도구 자동 점검/설치
./00.deploy-vscode-server.sh     # VSCode Server (m7g.xlarge)
./01.deploy-all-vpcs.sh          # 3 VPCs (병렬)
./02.deploy-tgw.sh               # Transit Gateway
source ./03.eks-setup-env.sh     # EKS 환경변수
./04.eks-create-cluster.sh       # eksctl 클러스터
./05.deploy-lbc.sh               # LBC (Pod Identity)
./06.deploy-karpenter.sh         # Karpenter v1.9.0
./07.deploy-valkey.sh            # Valkey (cache.r7g.large x2)
./08.deploy-aurora.sh            # Aurora MySQL (db.r7g.large x2, PI + Enhanced Monitoring)
./09.deploy-app.sh [base|bilingual]  # 앱 배포
./10.deploy-opensearch.sh        # OpenSearch (r7g.large.search x2)
./11.create-s3-buckets.sh        # S3 20 buckets (encrypted, versioned)
./12.create-dynamodb-tables.sh   # DynamoDB 20 tables (on-demand, PITR)
./13.create-lambda-functions.sh  # Lambda 20 functions (arm64, X-Ray)
./14.deploy-msk.sh               # MSK (kafka.m7g.large x2)
./15.enable-detailed-monitoring.sh  # EC2 Detailed Monitoring (1-min)
./16.deploy-ecs-fargate.sh       # ECS Fargate bilingual (ARM64, Docker build+ECR)
./17.deploy-ecs-ec2.sh           # ECS EC2 base (t4g.large ASG, public ECR)
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

### 앱 배포 (공통, auto CloudFront protection 포함)
```bash
cd shared/
./02.deploy-app.sh base             # 영어 Retail Store + CloudFront 보호 자동 적용
./02.deploy-app.sh bilingual        # 한/영 커스텀 쇼핑몰 + CloudFront 보호 자동 적용
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
- ECS EC2: `t4g.large` (ASG 3대)
- ECS Fargate: ARM64 (Graviton)
- Aurora: `db.r7g.large` x2 (PI + Enhanced Monitoring)
- Valkey: `cache.r7g.large` x2
- OpenSearch: `r7g.large.search` x2
- MSK: `kafka.m7g.large` x2

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
- LBC v3.1.0 (Helm chart 3.1.0)

### ECS
| Launch Type | Cluster | 앱 | 이미지 | Cloud Map |
|-------------|---------|-----|--------|-----------|
| Fargate ARM64 | lab-shop-ecs-fargate | bilingual (한/영) | Custom ECR (lab-shop-ui) | lab-shop-fg.local |
| EC2 t4g.large | lab-shop-ecs | base (영어) | public ECR (retail-store-sample) | lab-shop.local |

- 5개 서비스: ui, catalog+mysql, carts+dynamodb, checkout+redis, orders+postgresql
- DB sidecar: 같은 Task Definition 내 컨테이너 (bridge: links, awsvpc: localhost)
- Service Discovery: Cloud Map (SRV for bridge, A for awsvpc)
- ALB + CloudFront 보안 패턴 동일 (Prefix List + Custom Header)

### EKS Addons (15개)
| Category | Addon | Version |
|----------|-------|---------|
| Networking | vpc-cni | latest |
| Networking | coredns | latest |
| Networking | kube-proxy | latest |
| Storage | aws-ebs-csi-driver | latest |
| Storage | aws-efs-csi-driver | v2.3.0 |
| Storage | aws-fsx-csi-driver | v1.8.0 |
| Storage | aws-mountpoint-s3-csi-driver | v2.3.0 |
| Storage | snapshot-controller | v8.5.0 |
| Observability | amazon-cloudwatch-observability | v4.10.1 |
| Observability | adot (OpenTelemetry) | v0.141.0 |
| Observability | eks-node-monitoring-agent | v1.5.2 |
| Observability | aws-network-flow-monitoring-agent | v1.1.3 |
| Observability | metrics-server | latest |
| Security | aws-guardduty-agent | v1.12.1 |
| Security | eks-pod-identity-agent | latest |

### Data Services
| Service | Spec | Count | Features |
|---------|------|-------|----------|
| Aurora MySQL | db.r7g.large | 2 nodes | Performance Insights (7d), Enhanced Monitoring (60s) |
| Valkey | cache.r7g.large | 2 nodes | Encrypted at rest + in transit |
| OpenSearch | r7g.large.search | 2 nodes | Encrypted, Data Subnet |
| MSK | kafka.m7g.large | 2 brokers | CloudWatch Broker Logs |

### Serverless Resources
| Service | Count | Config |
|---------|-------|--------|
| S3 | 20 buckets | KMS encrypted, public access blocked, versioned |
| DynamoDB | 20 tables | On-demand, PITR, deletion protection |
| Lambda | 20 functions | arm64, X-Ray tracing, python/node rotating |

### Monitoring
- EC2: Detailed Monitoring (1-min interval on all instances)
- EKS: Container Insights + 15 addons
- ECS: Container Insights enabled, CloudWatch Logs (/ecs/lab-shop/*, 7d retention)
- Aurora: Performance Insights (7d) + Enhanced Monitoring (60s)
- Lambda: X-Ray + Insights Layer
- MSK: CloudWatch Broker Logs
- NFW: Alert + Flow Logs
- App: pino JSON logging + X-Request-ID
- CloudWatch: 13+ log groups, 21 Insights queries (app 7, EKS 6, DB 3, Lambda 3, infra 2)

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
| whchoitest | 061525506239 | CloudFormation (배포 테스트) |
