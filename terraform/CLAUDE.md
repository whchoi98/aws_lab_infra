# Terraform Module

Terraform HCL 방식의 인프라 배포.

## Structure
- `main.tf` — 루트 모듈 (모든 서브모듈 호출)
- `modules/vpc/` — VPC01/VPC02 공유 모듈
- `modules/dmz-vpc/` — DMZ VPC 전용 (NFW, NAT GW, ALB)
- `modules/tgw/` — Transit Gateway + 라우팅
- `modules/data-services/` — Aurora + Valkey
- `deploy.sh` — 전체 배포 래퍼 (init → plan → apply)

## Key Patterns
- VPC01/VPC02가 동일 `modules/vpc/` 사용 (DRY)
- 변수: `cloudfront_prefix_list_id`, `db_password` (sensitive)
- `terraform apply -var="..." -var="..."`
