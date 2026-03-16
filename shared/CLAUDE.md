# Shared Module

3가지 IaC 방식 + EKS/ECS에서 공통으로 사용하는 리소스.

## Structure
- `bilingual-app/` — 한/영 쇼핑몰 (Node.js Express + Kustomize, EKS + ECS Fargate)
- `base-application/` — 원본 Retail Store Sample (영어, EKS + ECS EC2)
- `base-application-standalone/` — base UI 별도 배포 (EKS ui-base namespace)
- `02.deploy-app.sh` — EKS 앱 배포 (base/bilingual 선택, Docker 빌드, auto CloudFront)
- `05.deploy-base-app.sh` — EKS base 병렬 배포 (별도 namespace + ALB + CloudFront)
- `03.deploy-cloudfront-protection.sh` — CloudFront→ALB 보호 (Prefix List + Custom Header)
- `04.cloudwatch-queries.sh` — CloudWatch Insights 쿼리 21개 (app 7, EKS 6, DB 3, Lambda 3, infra 2)
- `cloudfront-alb-protection.yaml` — CloudFront ALB 보호 CF 템플릿 (EKS/ECS 공통 사용)
- `00.check-prerequisites.sh` — aws, eksctl, kubectl, helm, jq, python3 점검/설치
- `01.setup-test-profiles.sh` — 3계정 AWS CLI 프로파일 설정

## bilingual-app UI
- `ui/src/server.js` — Express SSR + pino JSON logging
- `ui/src/locales/ko.json`, `en.json` — i18n 번역
- `ui/src/views/` — EJS 템플릿
- `ui/Dockerfile` — Multi-stage node:20-alpine
- Docker 이미지: `<account>.dkr.ecr.<region>.amazonaws.com/lab-shop-ui`
