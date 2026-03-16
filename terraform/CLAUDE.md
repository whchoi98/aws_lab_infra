# Terraform Module

Terraform HCL 방식의 인프라 배포.

## Structure
- `main.tf` — 루트 모듈 (모든 서브모듈 호출)
- `modules/vpc/` — VPC01/VPC02 공유 모듈
- `modules/dmz-vpc/` — DMZ VPC 전용 (NFW, NAT GW, ALB)
- `modules/tgw/` — Transit Gateway + 라우팅
- `modules/data-services/` — Aurora + Valkey
- `modules/ecs-fargate/` — ECS Fargate ARM64 (bilingual 한/영)
- `modules/ecs-ec2/` — ECS EC2 Graviton (base 영어)
- `deploy.sh` — 전체 배포 래퍼 (init → plan → apply)

## ECS Modules
| Module | Launch Type | 앱 | Cloud Map | UI Health Check |
|--------|-------------|-----|-----------|-----------------|
| ecs-fargate | Fargate ARM64 | bilingual (한/영) | lab-shop-fg.local | /health |
| ecs-ec2 | EC2 t4g.large (ASG 3대) | base (영어) | lab-shop.local | /actuator/health |

- 5 서비스: ui, catalog+mysql, carts+dynamodb, checkout+redis, orders+postgresql
- DB sidecar: Fargate는 localhost (awsvpc), EC2는 links (bridge)
- 변수: `bilingual_ecr_uri` (Fargate만, ECR 이미지 URI)

## Key Patterns
- VPC01/VPC02가 동일 `modules/vpc/` 사용 (DRY)
- 변수: `cloudfront_prefix_list_id`, `db_password` (sensitive), `bilingual_ecr_uri`
- `terraform apply -var="..." -var="..."`
