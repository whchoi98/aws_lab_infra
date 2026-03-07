# CDK Module

AWS CDK TypeScript 방식의 인프라 배포.

## Structure
- `bin/app.ts` — 엔트리포인트 (스택 인스턴스화)
- `lib/*.ts` — 6개 Stack 정의
- `deploy.sh` — 전체 배포 래퍼 (bootstrap → deploy --all)

## Stacks (의존성 순서)
1. DmzVpcStack → 2. Vpc01Stack → 3. Vpc02Stack → 4. TgwStack → 5. EksStack → 6. DataServicesStack

## Key Patterns
- L1 Constructs (CfnVPC 등) 사용 — CF와 1:1 매핑
- Cross-stack 참조: Stack props로 전달
- Context: `cloudFrontPrefixListId` (deploy 시 전달)
- `npm install && npx cdk deploy --all`
