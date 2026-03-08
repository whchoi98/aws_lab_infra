# Terraform 배포 가이드

## 실행 순서

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 0: 도구 + VSCode Server (CF 공통 템플릿)                    │
│  ┌─────────────────────┐  ┌────────────────────────────────┐   │
│  │ check-prerequisites │→│ 00.deploy-vscode-server        │   │
│  └─────────────────────┘  └────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Phase 1: Terraform 인프라 (한 번에 배포)                          │
│  ┌──────────────────────────────────────────────────────┐      │
│  │ terraform apply                                      │      │
│  │  → module.dmz_vpc (NFW + NAT GW + ALB + EC2)       │      │
│  │  → module.vpc01, module.vpc02 (Private VPC + EC2)   │      │
│  │  → module.tgw (Transit Gateway + Routes)            │      │
│  │  → module.data_services (Aurora + Valkey)           │      │
│  └──────────────────────────────────────────────────────┘      │
├─────────────────────────────────────────────────────────────────┤
│  Phase 2: EKS (eksctl 하이브리드)                                 │
│  ┌────────────────────┐  ┌──────────────────────┐              │
│  │ 03.eks-setup-env   │→│ 04.eks-create-cluster │              │
│  └────────────────────┘  └──────────────────────┘              │
├─────────────────────────────────────────────────────────────────┤
│  Phase 3: EKS 컴포넌트                                           │
│  ┌────────────────┐  ┌──────────────────────┐                  │
│  │ 05.deploy-lbc  │→│ 06.deploy-karpenter  │                  │
│  └────────────────┘  └──────────────────────┘                  │
├─────────────────────────────────────────────────────────────────┤
│  Phase 4: 앱 + 보안                                              │
│  ┌────────────────────┐  ┌──────────────────────────────────┐  │
│  │ 02.deploy-app.sh      │→│ deploy-cloudfront-protection     │  │
│  └────────────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
  ※ Phase 4에서 Data Services는 Phase 1에 포함 (별도 배포 불필요)
```

## 명령어 (복사-붙여넣기용)

```bash
# ━━━ Phase 0: 도구 + VSCode ━━━
source ../shared/00.check-prerequisites.sh
cd ../cloudformation/
./00.deploy-vscode-server.sh         # VSCode Server (CF 공통)

# ━━━ Phase 1: Terraform 인프라 (전체 한 번에) ━━━
cd ../terraform/
./deploy.sh                          # init → plan → apply (~25분)
# 또는 수동:
#   terraform init
#   terraform plan \
#     -var="cloudfront_prefix_list_id=pl-22a6434b" \
#     -var="db_password=Lab1234Qwer"
#   terraform apply -auto-approve \
#     -var="cloudfront_prefix_list_id=pl-22a6434b" \
#     -var="db_password=Lab1234Qwer"

# ━━━ Phase 2: EKS (eksctl 하이브리드) ━━━
cd ../cloudformation/
source ./03.eks-setup-env.sh         # DMZ VPC에서 Subnet 추출
./04.eks-create-cluster.sh           # eksctl 클러스터 생성 (~20분)

# ━━━ Phase 3: EKS 컴포넌트 ━━━
./05.deploy-lbc.sh                   # LBC v3.1.0 (Pod Identity)
./06.deploy-karpenter.sh             # Karpenter v1.9.0

# ━━━ Phase 4: 앱 + 보안 (Data Services는 Phase 1에 포함) ━━━
cd ../shared/
./02.deploy-app.sh bilingual            # 쇼핑몰
./03.deploy-cloudfront-protection.sh eksworkshop-tf lab-terraform

# ━━━ 검증 ━━━
./04.cloudwatch-queries.sh pod-cpu lab-terraform 60
cd ../terraform/ && terraform output

# ━━━ 정리 (필요시) ━━━
cd ../cloudformation/ && ./99.eks-cleanup.sh
cd ../terraform/ && terraform destroy \
  -var="cloudfront_prefix_list_id=pl-22a6434b" \
  -var="db_password=Lab1234Qwer"
```

## Terraform 모듈 구성

```
main.tf
 ├── module.dmz_vpc      ← DMZ VPC (10.11.0.0/16)
 │    ├── 12 Subnets + IGW + 2 NAT GW + Network Firewall
 │    ├── ALB + CloudFront (X-Custom-Secret)
 │    ├── 4 EC2 (t4g.large) + SSM Endpoints
 │    └── Outputs: vpc_id, subnet_ids, rt_ids
 │
 ├── module.vpc01        ← VPC01 (10.1.0.0/16) ─┐ modules/vpc/
 ├── module.vpc02        ← VPC02 (10.2.0.0/16) ─┘ (DRY 재사용)
 │    ├── 8 Subnets + 4 EC2 + SSM Endpoints
 │    └── No IGW, No NAT GW
 │
 ├── module.tgw          ← Transit Gateway
 │    ├── 3 Attachments
 │    ├── 0.0.0.0/0 → DMZ (static route)
 │    └── Return paths (NATGW/Attach RTs)
 │
 └── module.data_services ← Aurora + Valkey
      ├── Aurora MySQL (db.r7g.large × 2)
      └── Valkey 8.0 (cache.r7g.large × 2)
```

## 파일 구조

```
terraform/
├── deploy.sh              ← 전체 배포 래퍼
├── main.tf                ← 루트 모듈 (모든 모듈 호출)
├── variables.tf           ← 입력 변수
├── outputs.tf             ← 출력 값
├── providers.tf           ← AWS Provider >= 5.0
├── terraform.tfvars       ← 기본값
└── modules/
    ├── dmz-vpc/           ← DMZ VPC 전용 모듈
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── vpc/               ← VPC01/VPC02 공유 모듈 (DRY)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── tgw/               ← Transit Gateway
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── data-services/     ← Aurora + Valkey
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Terraform vs CF/CDK 차이점

| 항목 | Terraform | CloudFormation | CDK |
|------|:---:|:---:|:---:|
| Data Services | Phase 1에 포함 | Phase 4 별도 | Phase 3 별도 |
| VPC01/VPC02 | 동일 모듈 재사용 | 별도 템플릿 | 별도 Stack |
| 배포 단위 | 전체 한 번 | 스택별 순차 | 스택별 순차 |
| 상태 관리 | terraform.tfstate | CloudFormation | CloudFormation |
