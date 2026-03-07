# Architecture

## Overview

Hub-Spoke 네트워크 위에 EKS 마이크로서비스 쇼핑몰을 운영하는 AWS 랩 플랫폼.

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
              │  ALB → EKS/EC2  │
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
| Aurora | aurora-mysql-stack.yaml | Aurora MySQL (Data Subnet) |
| Valkey | valkey-cluster-stack.yaml | ElastiCache Valkey (Data Subnet) |

### EKS (eksctl + Helm)
| Component | Version | Method |
|-----------|---------|--------|
| EKS | v1.33 | eksctl ClusterConfig |
| LBC | v2.13 | Helm + Pod Identity |
| Karpenter | v1.9.0 | Helm + Pod Identity |

### Application (shared/)
| App | Description |
|-----|-------------|
| base-application | AWS Retail Store Sample (영어, pre-built images) |
| bilingual-app | Custom Node.js Express SSR (한/영, Docker build) |

### Microservices (bilingual-app)
| Service | Image | DB Sidecar | Port |
|---------|-------|-----------|------|
| ui | Custom (ECR) | - | 8080 |
| catalog | retail-store-sample-catalog:0.8.0 | MySQL 8.0 (PVC) | 8080 |
| carts | retail-store-sample-cart:0.8.0 | DynamoDB Local | 8080 |
| checkout | retail-store-sample-checkout:0.8.0 | Redis 7 | 8080 |
| orders | retail-store-sample-orders:0.8.0 | PostgreSQL 16 | 8080 |

## Data Flow

```
User → CloudFront → ALB (Public Subnet) → UI Pod (Private Subnet)
  UI → Catalog API → MySQL
  UI → Carts API → DynamoDB Local
  UI → Checkout API → Redis
  UI → Orders API → PostgreSQL
```

## Security
- Network Firewall: IGW ingress inspection
- ALB: CloudFront Prefix List + X-Custom-Secret header
- EC2: Private subnet only, SSM access
- EKS: Pod Identity (IRSA replacement), KMS secrets encryption
- Karpenter: Scoped IAM policies, arm64-only NodePool
