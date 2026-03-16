# Architecture

## Overview

Hub-Spoke 네트워크 위에 EKS + ECS 마이크로서비스 쇼핑몰을 운영하는 AWS 랩 플랫폼.

## Network Topology

```
                    Internet
                       │
              ┌────────┴────────┐
              │   CloudFront    │
              └────────┬────────┘
                       │
              ┌────────┴────────┐
              │  DMZ VPC (10.11)│
              │  NFW → NAT GW   │
              │  ALB → EKS/ECS  │
              │  Data: Aurora,  │
              │    Valkey       │
              └────────┬────────┘
                       │
              ┌────────┴────────┐
              │ Transit Gateway │
              └───┬─────────┬───┘
                  │         │
         ┌────────┴──┐ ┌───┴───────┐
         │  VPC01    │ │  VPC02    │
         │ (10.1)   │ │ (10.2)   │
         │ Workload  │ │ Workload  │
         └───────────┘ └───────────┘

  ┌──────────────────┐
  │ Mgmt VPC (10.254)│  VSCode Server (m7g.xlarge)
  │ CF→ALB→EC2       │  독립 (TGW 미연결)
  └──────────────────┘
```

## Components

### Infrastructure (cloudformation/templates/)
| Component | Template | Description |
|-----------|----------|-------------|
| DMZ VPC | 1.DMZVPC.yaml | Network Firewall, NAT GW, ALB, CloudFront |
| VPC01 | 2.VPC01.yaml | Private workload VPC |
| VPC02 | 3.VPC02.yaml | Private workload VPC |
| TGW | 4.TGW.yaml | Transit Gateway + cross-VPC routing |
| VSCode | vscode_server_secure.yaml | CF→ALB→EC2 개발환경 |
| Aurora | aurora-mysql-stack.yaml | Aurora MySQL (db.r7g.large x2, Data Subnet) |
| Valkey | valkey-cluster-stack.yaml | ElastiCache Valkey (cache.r7g.large x2, Data Subnet) |
| OpenSearch | opensearch-stack.yaml | OpenSearch (r7g.large.search x2, Data Subnet) |
| MSK | msk-stack.yaml | MSK Kafka (kafka.m7g.large x2) |
| ECS Fargate | ecs-shop-stack.yaml | ECS Fargate ARM64 bilingual (Cloud Map lab-shop-fg.local) |
| ECS EC2 | ecs-ec2-shop-stack.yaml | ECS EC2 t4g.large base (Cloud Map lab-shop.local) |

### EKS (eksctl + Helm)
| Component | Version | Method |
|-----------|---------|--------|
| EKS | v1.33 | eksctl ClusterConfig (8 nodes t4g.2xlarge, 15 addons) |
| LBC | v3.1.0 | Helm + Pod Identity |
| Karpenter | v1.9.0 | Helm + Pod Identity |

### ECS (CloudFormation / CDK / Terraform)
| Component | Launch Type | App | Cloud Map |
|-----------|-------------|-----|-----------|
| ECS Fargate | Fargate ARM64 | bilingual (한/영, ECR) | lab-shop-fg.local |
| ECS EC2 | EC2 t4g.large (ASG 3대) | base (영어, public ECR) | lab-shop.local |

- 5 서비스 × 2 클러스터, DB sidecar 동일 Task Definition 내 배치
- Service Discovery: Cloud Map (Fargate: A record, EC2: SRV record)

### Application (shared/)
| App | Description | 사용처 |
|-----|-------------|--------|
| base-application | AWS Retail Store Sample (영어, pre-built images) | EKS base, ECS EC2 |
| bilingual-app | Custom Node.js Express SSR (한/영, Docker build) | EKS bilingual, ECS Fargate |
| base-application-standalone | base UI 별도 배포 (ui-base namespace) | EKS 병렬 배포 |

### Microservices (공통)
| Service | Image | DB Sidecar | Port |
|---------|-------|-----------|------|
| ui (bilingual) | Custom ECR (lab-shop-ui) | - | 8080 |
| ui (base) | retail-store-sample-ui:1.2.1 | - | 8080 |
| catalog | retail-store-sample-catalog:1.2.1 | MySQL 8.0 | 8080 |
| carts | retail-store-sample-cart:1.2.1 | DynamoDB Local 2.0.0 | 8080 |
| checkout | retail-store-sample-checkout:1.2.1 | Redis 7 | 8080 |
| orders | retail-store-sample-orders:1.2.1 | PostgreSQL 16 | 8080 |

## Data Flow

```
User → CloudFront → ALB (Public Subnet) → UI (Private Subnet)
  UI → Catalog API → MySQL (sidecar)
  UI → Carts API → DynamoDB Local (sidecar)
  UI → Checkout API → Redis (sidecar)
  UI → Orders API → PostgreSQL (sidecar)

Platform variants:
  EKS: Pod (Kustomize) + K8s Service Discovery
  ECS Fargate: Task (awsvpc) + Cloud Map A record
  ECS EC2: Task (bridge) + Cloud Map SRV record
```

### Serverless Resources
| Service | Count | Config |
|---------|-------|--------|
| S3 | 20 buckets | KMS encrypted, public access blocked, versioned |
| DynamoDB | 20 tables | On-demand, PITR, deletion protection |
| Lambda | 20 functions | arm64, X-Ray tracing, python/node rotating |

## Security
- CloudFront → ALB: Prefix List + Custom Header (auto-applied on every deploy)
- Network Firewall: IGW ingress inspection
- EC2: Private subnet only, SSM access
- EKS: Pod Identity (IRSA replacement), KMS secrets encryption
- ECS: Task Execution Role + Task Role, SG inter-service isolation
- Karpenter: Scoped IAM policies, arm64-only NodePool
- S3: Public access blocked on all buckets
- DynamoDB: Deletion protection enabled
- All data services: Encrypted at rest + in transit
- GuardDuty: EKS Runtime Monitoring

## Monitoring
- EC2: Detailed Monitoring (1-min interval on all instances)
- EKS: Container Insights + 15 addons
- ECS: Container Insights enabled, CloudWatch Logs (7d retention)
- Aurora: Performance Insights (7d) + Enhanced Monitoring (60s)
- Lambda: X-Ray + Insights Layer
- MSK: CloudWatch Broker Logs
- NFW: Alert + Flow Logs
- App: pino JSON logging + X-Request-ID
- CloudWatch: 13+ log groups, 21 Insights queries (app 7, EKS 6, DB 3, Lambda 3, infra 2)
