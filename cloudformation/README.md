# Shell + CloudFormation 배포 가이드

## 실행 순서

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 0: 도구 + VSCode Server                                  │
│  ┌─────────────────────┐  ┌────────────────────────────────┐   │
│  │ check-prerequisites │→│ 00.deploy-vscode-server        │   │
│  └─────────────────────┘  └────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  Phase 1: 네트워크                                               │
│  ┌──────────────────────┐  ┌──────────────────┐                │
│  │ 01.deploy-all-vpcs   │→│ 02.deploy-tgw    │                │
│  │ (DMZVPC+VPC01+VPC02) │  │ (Transit GW)    │                │
│  └──────────────────────┘  └──────────────────┘                │
├─────────────────────────────────────────────────────────────────┤
│  Phase 2: EKS                                                   │
│  ┌────────────────────┐  ┌──────────────────────┐              │
│  │ 03.eks-setup-env   │→│ 04.eks-create-cluster │              │
│  │ (source 실행)       │  │ (eksctl)             │              │
│  └────────────────────┘  └──────────────────────┘              │
├─────────────────────────────────────────────────────────────────┤
│  Phase 3: EKS 컴포넌트                                           │
│  ┌────────────────┐  ┌──────────────────────┐                  │
│  │ 05.deploy-lbc  │→│ 06.deploy-karpenter  │                  │
│  │ (LBC v3.1.0)  │  │ (Karpenter v1.9.0)  │                  │
│  └────────────────┘  └──────────────────────┘                  │
├─────────────────────────────────────────────────────────────────┤
│  Phase 4: 데이터 서비스                                           │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ 07.deploy-valkey │  │ 08.deploy-aurora │  (병렬 가능)        │
│  └──────────────────┘  └──────────────────┘                    │
├─────────────────────────────────────────────────────────────────┤
│  Phase 5: 앱 + 보안                                              │
│  ┌────────────────────┐  ┌──────────────────────────────────┐  │
│  │ 09.deploy-app      │→│ deploy-cloudfront-protection     │  │
│  │ (bilingual/base)   │  │ (CloudFront → ALB 보안)          │  │
│  └────────────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 명령어 (복사-붙여넣기용)

```bash
# ━━━ Phase 0: 도구 + VSCode ━━━
cd cloudformation/
source 00.check-prerequisites.sh
./00.deploy-vscode-server.sh

# ━━━ Phase 1: 네트워크 ━━━
./01.deploy-all-vpcs.sh          # DMZVPC + VPC01 + VPC02 (병렬 배포, ~15분)
./02.deploy-tgw.sh               # Transit Gateway (~5분)

# ━━━ Phase 2: EKS ━━━
source ./03.eks-setup-env.sh     # 환경변수 + KMS + EKS 버전 입력
./04.eks-create-cluster.sh       # eksctl 클러스터 생성 (~20분)

# ━━━ Phase 3: EKS 컴포넌트 ━━━
./05.deploy-lbc.sh               # LBC v3.1.0 (Pod Identity)
./06.deploy-karpenter.sh         # Karpenter v1.9.0

# ━━━ Phase 4: 데이터 서비스 ━━━
./07.deploy-valkey.sh            # Valkey 8.0 (cache.r7g.large, ~15분)
./08.deploy-aurora.sh            # Aurora MySQL (db.r7g.large, ~20분)

# ━━━ Phase 5: 앱 + 보안 ━━━
./09.deploy-app.sh bilingual     # 한/영 쇼핑몰 (Docker build + ECR push)
cd ../shared/
./03.deploy-cloudfront-protection.sh eksworkshop-cf lab-cf

# ━━━ 검증 ━━━
./04.cloudwatch-queries.sh pod-cpu lab-cf 60
./04.cloudwatch-queries.sh db-connections lab-cf 60

# ━━━ 정리 (필요시) ━━━
cd ../cloudformation/
./99.eks-cleanup.sh
```

## 배포 결과물

| 리소스 | CF 스택 이름 | 수량 |
|--------|------------|:---:|
| VSCode Server | mgmt-vpc | EC2 1대 (m7g.xlarge) |
| DMZ VPC + NFW | DMZVPC | EC2 4대 + NAT GW 2 + NFW |
| VPC01 | VPC01 | EC2 4대 |
| VPC02 | VPC02 | EC2 4대 |
| Transit Gateway | TGW | 3 Attachment |
| EKS | eksctl-eksworkshop-* (4 stacks) | 8 Nodes |
| Valkey | Valkey | 2 Nodes (Multi-AZ) |
| Aurora | Aurora | 2 Instances (Primary+Replica) |
| 쇼핑몰 | (K8s) | 15 Pods |
| CloudFront | lab-shop-cloudfront | HTTPS 보안 |

## 파일 구조

```
cloudformation/
├── 00.deploy-vscode-server.sh     ← Phase 0
├── 01.deploy-all-vpcs.sh          ← Phase 1
├── 02.deploy-tgw.sh               ← Phase 1
├── 03.eks-setup-env.sh            ← Phase 2 (source)
├── 04.eks-create-cluster.sh       ← Phase 2
├── 05.deploy-lbc.sh               ← Phase 3
├── 06.deploy-karpenter.sh         ← Phase 3
├── 07.deploy-valkey.sh            ← Phase 4
├── 08.deploy-aurora.sh            ← Phase 4
├── 09.deploy-app.sh               ← Phase 5
├── 99.eks-cleanup.sh              ← 정리
├── 00.check-prerequisites.sh         ← 도구 점검
└── templates/                     ← CF YAML 템플릿
    ├── vscode_server_secure.yaml
    ├── 1.DMZVPC.yaml
    ├── 2.VPC01.yaml
    ├── 3.VPC02.yaml
    ├── 4.TGW.yaml
    ├── aurora-mysql-stack.yaml
    └── valkey-cluster-stack.yaml
```
