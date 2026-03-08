# Shared — 3가지 배포 방식 공통 리소스

> **이 디렉토리는 CloudFormation / CDK / Terraform 어떤 방식으로 배포하든 공통으로 사용하는 스크립트와 앱 코드입니다.**

## 왜 shared/ 인가?

```
                    ┌─────────────┐
                    │   shared/   │ ← 3가지 방식 모두 여기를 사용
                    └──────┬──────┘
              ┌────────────┼────────────┐
              ▼            ▼            ▼
      cloudformation/    cdk/       terraform/
      (Phase 0~5)     (Phase 0~4)  (Phase 0~4)
```

- **인프라**(VPC, TGW, EKS)는 각 방식별 디렉토리에서 배포
- **앱, 보안, 모니터링**은 인프라 방식과 무관하게 동일 → `shared/`

## 디렉토리 구조

```
shared/
├── 📋 스크립트 (실행 순서)
│   ├── check-prerequisites.sh         ① 도구 점검/설치
│   ├── setup-test-profiles.sh         ② 3계정 AWS CLI 프로파일
│   ├── deploy-app.sh                  ③ 쇼핑몰 앱 배포
│   ├── deploy-cloudfront-protection.sh ④ CloudFront → ALB 보안
│   └── cloudwatch-queries.sh          ⑤ 로그 분석 쿼리
│
├── 📦 쇼핑몰 앱
│   ├── bilingual-app/                 한/영 커스텀 쇼핑몰
│   │   ├── ui/                        Node.js Express (Docker)
│   │   │   ├── Dockerfile
│   │   │   └── src/ (server.js, views/, locales/, css/)
│   │   ├── catalog/                   상품 카탈로그 + MySQL
│   │   ├── carts/                     장바구니 + DynamoDB
│   │   ├── checkout/                  결제 + Redis
│   │   ├── orders/                    주문 + PostgreSQL
│   │   └── kustomization.yaml
│   │
│   └── base-application/              영어 전용 (AWS 원본 이미지)
│       ├── ui/, catalog/, carts/, checkout/, orders/
│       └── kustomization.yaml
│
└── 🔒 보안 템플릿
    └── cloudfront-alb-protection.yaml  CloudFront CF 스택
```

## 실행 순서

```
┌─────────────────────────────────────────────────────────────────┐
│  ① 도구 점검 (모든 방식의 Phase 0에서 실행)                         │
│  ┌──────────────────────────┐                                   │
│  │ check-prerequisites.sh   │ aws, eksctl, kubectl, helm,       │
│  │                          │ jq, python3, docker, terraform    │
│  └──────────────────────────┘                                   │
├─────────────────────────────────────────────────────────────────┤
│  ② 테스트 계정 설정 (최초 1회)                                      │
│  ┌──────────────────────────┐                                   │
│  │ setup-test-profiles.sh   │ lab-cf, lab-cdk, lab-terraform    │
│  │                          │ 3개 AWS CLI 프로파일 설정            │
│  └──────────────────────────┘                                   │
├─────────────────────────────────────────────────────────────────┤
│  ③ 쇼핑몰 앱 배포 (인프라 + EKS 완료 후)                             │
│  ┌──────────────────────────┐                                   │
│  │ deploy-app.sh            │ bilingual → Docker build + ECR    │
│  │                          │ base → pre-built images           │
│  │                          │ kubectl apply -k                  │
│  └──────────────────────────┘                                   │
├─────────────────────────────────────────────────────────────────┤
│  ④ CloudFront 보안 (앱 배포 후)                                    │
│  ┌────────────────────────────────┐                             │
│  │ deploy-cloudfront-protection.sh│ ALB SG → CF Prefix List     │
│  │                                │ CloudFront + X-Lab-Secret   │
│  │                                │ 직접 ALB 접근 차단             │
│  └────────────────────────────────┘                             │
├─────────────────────────────────────────────────────────────────┤
│  ⑤ 모니터링/로그 분석 (운영 중 상시)                                  │
│  ┌──────────────────────────┐                                   │
│  │ cloudwatch-queries.sh    │ 21개 쿼리 (앱/EKS/DB/Lambda/NFW)  │
│  └──────────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────┘
```

## 사용법

### ① 도구 점검/설치

```bash
# 모든 배포 방식에서 가장 먼저 실행
source shared/check-prerequisites.sh

# 점검 대상: aws, eksctl, kubectl, helm, jq, python3
# 미설치 도구는 자동 설치 (ARM64/x86 자동 감지)
```

### ② 테스트 계정 프로파일 (최초 1회)

```bash
./shared/setup-test-profiles.sh

# 대화형으로 3개 계정 Access Key 입력
# 결과: ~/.aws/config에 lab-cf, lab-cdk, lab-terraform 프로파일 생성
# 검증: 각 계정 sts get-caller-identity 자동 테스트
```

### ③ 쇼핑몰 앱 배포

```bash
# 한/영 커스텀 쇼핑몰 (Docker build 필요)
./shared/deploy-app.sh bilingual
# → Docker build → ECR push → kubectl apply -k
# → ALB Ingress 자동 생성 (LBC)

# 영어 전용 (pre-built, Docker 불필요)
./shared/deploy-app.sh base
# → kubectl apply -k (AWS 공식 이미지 사용)

# 특정 kube-context 지정
./shared/deploy-app.sh bilingual eksworkshop-cf
```

### ④ CloudFront → ALB 보안

```bash
# EKS ALB를 CloudFront 뒤에 숨김
./shared/deploy-cloudfront-protection.sh [kube-context] [aws-profile]

# 예시:
./shared/deploy-cloudfront-protection.sh eksworkshop-cf lab-cf
./shared/deploy-cloudfront-protection.sh eksworkshop-cdk lab-cdk
./shared/deploy-cloudfront-protection.sh eksworkshop-tf lab-terraform

# 결과:
#   ✅ CloudFront HTTPS → ALB (200 OK)
#   ❌ 직접 ALB HTTP → timeout (차단)
```

### ⑤ CloudWatch 로그 분석

```bash
./shared/cloudwatch-queries.sh [query-name] [profile] [minutes]

# 쿼리 목록 보기
./shared/cloudwatch-queries.sh list

# ── 앱 로그 (7개) ──
./shared/cloudwatch-queries.sh error-logs lab-cf 60        # 에러 로그
./shared/cloudwatch-queries.sh slow-requests lab-cf 30     # 느린 요청 (>1초)
./shared/cloudwatch-queries.sh request-count lab-cf 60     # 서비스별 요청 수
./shared/cloudwatch-queries.sh status-codes lab-cf 60      # HTTP 상태 코드
./shared/cloudwatch-queries.sh backend-latency lab-cf 60   # 백엔드 지연
./shared/cloudwatch-queries.sh cart-actions lab-cf 60       # 장바구니 활동
./shared/cloudwatch-queries.sh order-actions lab-cf 60      # 주문 활동

# ── Container Insights (6개) ──
./shared/cloudwatch-queries.sh pod-cpu lab-cf 60           # Pod CPU Top 10
./shared/cloudwatch-queries.sh pod-memory lab-cf 60        # Pod 메모리 Top 10
./shared/cloudwatch-queries.sh pod-restarts lab-cf 1440    # Pod 재시작 (24시간)
./shared/cloudwatch-queries.sh node-cpu lab-cf 60          # 노드 CPU
./shared/cloudwatch-queries.sh node-network lab-cf 60      # 노드 네트워크
./shared/cloudwatch-queries.sh container-errors lab-cf 60  # 컨테이너 에러

# ── DB Insights (3개) ──
./shared/cloudwatch-queries.sh db-slow-queries lab-cf 60   # Aurora 느린 쿼리
./shared/cloudwatch-queries.sh db-connections lab-cf 60    # DB 연결 수
./shared/cloudwatch-queries.sh db-cpu lab-cf 60            # DB CPU 사용률

# ── Lambda Insights (3개) ──
./shared/cloudwatch-queries.sh lambda-errors lab-cf 60     # Lambda 에러
./shared/cloudwatch-queries.sh lambda-duration lab-cf 60   # Lambda 실행 시간
./shared/cloudwatch-queries.sh lambda-cold-starts lab-cf 60 # Cold Start

# ── 인프라 (2개) ──
./shared/cloudwatch-queries.sh nfw-alerts lab-cf 60        # NFW 알림
./shared/cloudwatch-queries.sh nfw-flow lab-cf 60          # NFW 플로우
```

## bilingual-app vs base-application

| | bilingual-app | base-application |
|---|:---:|:---:|
| **언어** | 한국어 + English | English only |
| **UI** | Custom Node.js Express SSR | AWS 공식 이미지 |
| **Docker 빌드** | 필요 (ECR push) | 불필요 |
| **로깅** | JSON (pino) + X-Request-ID | 기본 stdout |
| **주소 형식** | 한국 표준 (시/도/구/동/도로명) | US 형식 |
| **이미지** | `{account}.dkr.ecr.{region}.amazonaws.com/lab-shop-ui` | `public.ecr.aws/aws-containers/*` |

### bilingual-app 마이크로서비스

```
                     ┌─────────┐
    CloudFront → ALB → │   UI    │ ← Node.js Express (ECR)
                     └────┬────┘
          ┌──────────┬────┴────┬──────────┐
          ▼          ▼        ▼          ▼
      Catalog    Carts    Orders    Checkout
      (MySQL)  (DynamoDB) (PostgreSQL) (Redis)
        ↑          ↑         ↑          ↑
      PVC 5Gi   Sidecar   Sidecar    Sidecar
```

| Service | Image | DB | Replicas |
|---------|-------|-----|:---:|
| ui | Custom ECR | - | 2 |
| catalog | retail-store-sample-catalog:0.8.0 | MySQL 8.0 (PVC) | 2+1 |
| carts | retail-store-sample-cart:0.8.0 | DynamoDB Local | 2+1 |
| checkout | retail-store-sample-checkout:0.8.0 | Redis 7 | 2+1 |
| orders | retail-store-sample-orders:0.8.0 | PostgreSQL 16 | 2+1 |

## 각 배포 방식에서 shared/ 사용 시점

```
CloudFormation 방식                CDK 방식                     Terraform 방식
──────────────                   ──────────                   ──────────────
00.deploy-vscode-server         00.deploy-vscode-server       00.deploy-vscode-server
01.deploy-all-vpcs              cdk deploy --all              terraform apply
02.deploy-tgw                   ─────────────────             ─────────────────
03.eks-setup-env                03.eks-setup-env              03.eks-setup-env
04.eks-create-cluster           04.eks-create-cluster         04.eks-create-cluster
05.deploy-lbc                   05.deploy-lbc                 05.deploy-lbc
06.deploy-karpenter             06.deploy-karpenter           06.deploy-karpenter
07.deploy-valkey                07.deploy-valkey              ─── (이미 포함) ───
08.deploy-aurora                08.deploy-aurora              ─── (이미 포함) ───
┌─────────────────────────────────────────────────────────────────────────┐
│  ▼▼▼ 여기서부터 shared/ 사용 ▼▼▼                                         │
│  shared/deploy-app.sh bilingual          ← 앱 배포                      │
│  shared/deploy-cloudfront-protection.sh  ← 보안 설정                     │
│  shared/cloudwatch-queries.sh            ← 모니터링                      │
└─────────────────────────────────────────────────────────────────────────┘
```
