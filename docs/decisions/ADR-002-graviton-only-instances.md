# ADR-002: Graviton (ARM64) 전용 인스턴스 전략

**Date**: 2026-03-16
**Status**: accepted

## Context
비용 최적화와 최신 AWS 아키텍처 학습을 위해 모든 컴퓨팅 리소스를 Graviton 기반으로 통일할지 결정 필요. x86과 혼용하면 AMI/이미지 관리가 복잡해진다.

## Decision
모든 컴퓨팅 리소스를 Graviton (ARM64) 전용으로 통일:
- EC2: t4g.large, m7g.xlarge
- EKS MNG: t4g.2xlarge, Karpenter arm64 NodePool
- ECS Fargate: ARM64 RuntimePlatform
- ECS EC2: t4g.large (ECS-optimized AL2023 ARM64 AMI)
- Lambda: arm64 아키텍처
- Aurora: db.r7g.large, Valkey: cache.r7g.large, OpenSearch: r7g.large.search
- MSK: kafka.m7g.large

## Consequences
- x86 인스턴스 대비 ~20% 비용 절감
- 모든 컨테이너 이미지가 ARM64 지원 필요 (public ECR retail-store-sample은 multi-arch 지원)
- x86 전용 소프트웨어 사용 불가 (랩 환경에서는 해당 없음)
