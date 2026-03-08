# AWS CDK 배포 가이드

## 실행 순서

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 0: 도구 + VSCode Server (CF 공통 템플릿)                    │
│  ┌─────────────────────┐  ┌────────────────────────────────┐   │
│  │ check-prerequisites │→│ 00.deploy-vscode-server        │   │
│  └─────────────────────┘  └────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Phase 1: CDK 인프라 (한 번에 배포)                                │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ cdk deploy --all                                     │      │
│  │  → DmzVpcStack → Vpc01Stack → Vpc02Stack            │      │
│  │  → TgwStack → EksStack → (DataServicesStack)        │      │
│  └──────────────────────────────────────────────────────┘      │
├─────────────────────────────────────────────────────────────────┤
│  Phase 2: EKS (eksctl 하이브리드)                                 │
│  ┌────────────────────┐  ┌──────────────────────┐              │
│  │ 03.eks-setup-env   │→│ 04.eks-create-cluster │              │
│  └────────────────────┘  └──────────────────────┘              │
├─────────────────────────────────────────────────────────────────┤
│  Phase 3: EKS 컴포넌트 + 데이터 서비스                              │
│  ┌────────────────┐  ┌──────────────────────┐                  │
│  │ 05.deploy-lbc  │→│ 06.deploy-karpenter  │                  │
│  └────────────────┘  └──────────────────────┘                  │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ 07.deploy-valkey │  │ 08.deploy-aurora │                    │
│  └──────────────────┘  └──────────────────┘                    │
├─────────────────────────────────────────────────────────────────┤
│  Phase 4: 앱 + 보안                                              │
│  ┌────────────────────┐  ┌──────────────────────────────────┐  │
│  │ deploy-app.sh      │→│ deploy-cloudfront-protection     │  │
│  └────────────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 명령어 (복사-붙여넣기용)

```bash
# ━━━ Phase 0: 도구 + VSCode ━━━
source ../shared/check-prerequisites.sh
cd ../cloudformation/
./00.deploy-vscode-server.sh         # VSCode Server (CF 공통)

# ━━━ Phase 1: CDK 인프라 ━━━
cd ../cdk/
npm install
./deploy.sh                          # bootstrap → deploy --all (~25분)
# 또는 수동:
#   npx cdk bootstrap aws://ACCOUNT_ID/ap-northeast-2
#   npx cdk deploy --all --require-approval never \
#     --context cloudFrontPrefixListId=pl-22a6434b

# ━━━ Phase 2: EKS (eksctl 하이브리드) ━━━
cd ../cloudformation/
source ./03.eks-setup-env.sh         # DmzVpcStack에서 Subnet 추출
./04.eks-create-cluster.sh           # eksctl 클러스터 생성 (~20분)

# ━━━ Phase 3: EKS 컴포넌트 + 데이터 ━━━
./05.deploy-lbc.sh                   # LBC v3.1.0 (Pod Identity)
./06.deploy-karpenter.sh             # Karpenter v1.9.0
./07.deploy-valkey.sh                # Valkey (DMZVPCStackName=DmzVpcStack)
./08.deploy-aurora.sh                # Aurora

# ━━━ Phase 4: 앱 + 보안 ━━━
cd ../shared/
./deploy-app.sh bilingual            # 쇼핑몰
./deploy-cloudfront-protection.sh eksworkshop-cdk lab-cdk

# ━━━ 검증 ━━━
./cloudwatch-queries.sh pod-cpu lab-cdk 60

# ━━━ 정리 (필요시) ━━━
cd ../cloudformation/ && ./99.eks-cleanup.sh
cd ../cdk/ && npx cdk destroy --all
```

## CDK 스택 구성

```
App (bin/app.ts)
 ├── DmzVpcStack        ← VPC + NFW + NAT GW + ALB + CloudFront
 │    ├── 12 Subnets (Public/Private/Data/Attach/FW/NATGW × 2 AZ)
 │    ├── Network Firewall (Stateless + Stateful)
 │    ├── 4 EC2 (Private Subnet, t4g.large)
 │    └── ALB + CloudFront + SSM Endpoints
 │
 ├── Vpc01Stack         ← Private VPC (10.1.0.0/16)
 │    ├── 8 Subnets + 4 EC2 + SSM Endpoints
 │    └── No IGW, No NAT GW (TGW 경유)
 │
 ├── Vpc02Stack         ← Private VPC (10.2.0.0/16)
 │
 ├── TgwStack           ← Transit Gateway + Routes
 │    ├── 3 VPC Attachments
 │    ├── 0.0.0.0/0 → DMZ (static)
 │    └── Return paths (NATGW/Attach RT)
 │
 ├── EksStack           ← Placeholder (eksctl 사용)
 │
 └── DataServicesStack  ← Aurora + Valkey
```

## 파일 구조

```
cdk/
├── deploy.sh              ← 전체 배포 래퍼
├── package.json           ← aws-cdk-lib, constructs
├── tsconfig.json
├── cdk.json
├── bin/
│   └── app.ts             ← 엔트리포인트
└── lib/
    ├── config.ts           ← CIDR, Tags 설정
    ├── dmz-vpc-stack.ts    ← DMZ VPC (가장 큰 스택)
    ├── vpc01-stack.ts      ← VPC01
    ├── vpc02-stack.ts      ← VPC02
    ├── tgw-stack.ts        ← Transit Gateway
    ├── eks-stack.ts        ← EKS (placeholder)
    └── data-services-stack.ts ← Aurora + Valkey
```
