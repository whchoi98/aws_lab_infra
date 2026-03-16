# AWS Lab Infrastructure

AWS 네트워크 + EKS/ECS 기반 마이크로서비스 랩 플랫폼.
**3가지 IaC 도구**로 동일한 아키텍처를 구축합니다.
ECS는 Fargate(bilingual) + EC2(base) 2가지 launch type을 지원합니다.

## 아키텍처

```
                Internet
                   │
          ┌────────┴────────┐
          │   CloudFront    │ HTTPS + Custom Header
          └────────┬────────┘
                   │
          ┌────────┴────────┐
          │   DMZ VPC       │ 10.11.0.0/16
          │  ┌────────────┐ │
          │  │ Network FW │ │ Stateless + Stateful
          │  └────────────┘ │
          │  ┌────────────┐ │
          │  │ ALB → EKS  │ │ 8 Nodes (t4g.2xlarge)
          │  │ ALB → ECS  │ │ Fargate + EC2 (t4g.large)
          │  └────────────┘ │
          │  ┌────────────┐ │
          │  │ Aurora     │ │ db.r7g.large × 2
          │  │ Valkey     │ │ cache.r7g.large × 2
          │  └────────────┘ │
          │  EC2 × 4       │ t4g.large
          └────────┬────────┘
                   │
          ┌────────┴────────┐
          │ Transit Gateway │
          └───┬─────────┬───┘
              │         │
     ┌────────┴──┐ ┌───┴───────┐
     │  VPC01    │ │  VPC02    │
     │ 10.1/16  │ │ 10.2/16  │
     │ EC2 × 4  │ │ EC2 × 4  │
     └──────────┘ └───────────┘
```

## 3가지 배포 방식 비교

| | Shell + CloudFormation | AWS CDK | Terraform |
|---|:---:|:---:|:---:|
| **디렉토리** | `cloudformation/` | `cdk/` | `terraform/` |
| **언어** | YAML + Bash | TypeScript | HCL |
| **VPC 배포** | 스택별 순차 (5 stacks) | `cdk deploy --all` | `terraform apply` (한 번) |
| **EKS** | eksctl | eksctl (하이브리드) | eksctl (하이브리드) |
| **ECS Fargate** | ecs-shop-stack.yaml | EcsFargateStack | modules/ecs-fargate |
| **ECS EC2** | ecs-ec2-shop-stack.yaml | EcsEc2Stack | modules/ecs-ec2 |
| **Data Services** | Phase 4 별도 | Phase 3 별도 | Phase 1에 포함 |
| **VPC 재사용** | 별도 템플릿 | 별도 Stack | 동일 모듈 (DRY) |
| **가이드** | [README](cloudformation/README.md) | [README](cdk/README.md) | [README](terraform/README.md) |

## 빠른 시작

### 방식 1: Shell + CloudFormation
```bash
cd cloudformation/
source 00.check-prerequisites.sh        # 도구 점검
./00.deploy-vscode-server.sh         # VSCode
./01.deploy-all-vpcs.sh              # VPCs
./02.deploy-tgw.sh                   # TGW
source ./03.eks-setup-env.sh         # EKS 환경
./04.eks-create-cluster.sh           # EKS
./05.deploy-lbc.sh && ./06.deploy-karpenter.sh
./07.deploy-valkey.sh && ./08.deploy-aurora.sh
./09.deploy-app.sh bilingual         # EKS 쇼핑몰
./16.deploy-ecs-fargate.sh           # ECS Fargate bilingual
./17.deploy-ecs-ec2.sh               # ECS EC2 base
```

### 방식 2: AWS CDK
```bash
cd cloudformation/ && ./00.deploy-vscode-server.sh   # VSCode (공통)
cd ../cdk/ && ./deploy.sh            # CDK 전체 배포
cd ../cloudformation/
source ./03.eks-setup-env.sh && ./04.eks-create-cluster.sh
./05.deploy-lbc.sh && ./06.deploy-karpenter.sh
./07.deploy-valkey.sh && ./08.deploy-aurora.sh
cd ../shared/ && ./02.deploy-app.sh bilingual
./03.deploy-cloudfront-protection.sh eksworkshop-cdk lab-cdk
```

### 방식 3: Terraform
```bash
cd cloudformation/ && ./00.deploy-vscode-server.sh   # VSCode (공통)
cd ../terraform/ && ./deploy.sh      # TF 전체 배포 (Data Services 포함)
cd ../cloudformation/
source ./03.eks-setup-env.sh && ./04.eks-create-cluster.sh
./05.deploy-lbc.sh && ./06.deploy-karpenter.sh
cd ../shared/ && ./02.deploy-app.sh bilingual
./03.deploy-cloudfront-protection.sh eksworkshop-tf lab-terraform
```

## 계정당 리소스

| 리소스 | 타입 | 수량 |
|--------|:---:|:---:|
| VSCode Server | m7g.xlarge | 1 |
| VPC EC2 (DMZ/VPC01/VPC02) | t4g.large | 12 (4×3) |
| EKS Nodes | t4g.2xlarge | 8 |
| ECS EC2 Nodes | t4g.large | 3 (ASG) |
| ECS Fargate Tasks | ARM64 | 10 (5 서비스 × 2) |
| ECS EC2 Tasks | ARM64 | 10 (5 서비스 × 2) |
| Aurora MySQL | db.r7g.large | 2 |
| Valkey (ElastiCache) | cache.r7g.large | 2 |
| EKS App Pods | - | 15 |

## 모니터링 (CloudWatch)

```bash
cd shared/
./04.cloudwatch-queries.sh list                    # 21개 쿼리 목록
./04.cloudwatch-queries.sh pod-cpu lab-cf 60       # Pod CPU
./04.cloudwatch-queries.sh db-connections lab-cf 60 # Aurora DB
./04.cloudwatch-queries.sh lambda-duration lab-cf 60 # Lambda
./04.cloudwatch-queries.sh nfw-alerts lab-cf 60    # NFW 알림
```

## 보안

- **CloudFront**: HTTPS + Custom Header (X-Lab-Secret / X-Custom-Secret)
- **ALB**: CloudFront Prefix List SG (직접 접근 차단)
- **EC2**: Private Subnet + SSM only
- **EKS**: Pod Identity + KMS Secrets + GuardDuty
- **ECS**: Task Execution Role + Task Role, SG inter-service isolation
- **Network Firewall**: DMZ VPC 인바운드 검사
- **Aurora**: Performance Insights + Enhanced Monitoring
