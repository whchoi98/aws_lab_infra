# ADR-001: EKS와 함께 ECS 2가지 Launch Type 추가

**Date**: 2026-03-16
**Status**: accepted

## Context
EKS 기반 쇼핑몰이 이미 운영 중이지만, 랩 참가자들이 ECS Fargate와 EC2 launch type도 비교 체험할 수 있어야 한다. 동일한 마이크로서비스 앱을 3가지 컨테이너 플랫폼(EKS, ECS Fargate, ECS EC2)에서 운영하는 것이 목표.

## Decision
- ECS Fargate (ARM64): bilingual-app (한/영, custom ECR) — awsvpc 네트워킹, Cloud Map A record
- ECS EC2 (t4g.large ASG): base-application (영어, public ECR) — bridge 네트워킹, Cloud Map SRV record
- 3가지 IaC(CF, CDK, Terraform) 모두에서 동일 구현
- DB sidecar는 EKS와 동일하게 같은 Task Definition 내 배치
- ALB + CloudFront 보안 패턴 동일 적용

## Consequences
- 랩 참가자가 EKS vs ECS Fargate vs ECS EC2를 동일 앱으로 비교 가능
- 리소스 비용 증가 (ECS EC2 ASG 3대 + Fargate Task 10개 추가)
- 유지보수 대상 증가 (CF 템플릿 2개, CDK 스택 2개, TF 모듈 2개)
