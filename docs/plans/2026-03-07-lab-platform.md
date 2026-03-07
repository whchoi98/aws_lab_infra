# AWS Lab Infrastructure Platform Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete AWS lab platform with VSCode Server, multi-VPC networking (with Network Firewall), EKS, data services, and sample app — deployable via CloudFormation, CDK, and Terraform across 3 accounts.

**Architecture:** Hub-Spoke network with DMZ VPC (Network Firewall + NAT GW + ALB) as hub, VPC01/VPC02 as spokes via Transit Gateway. EKS runs in DMZ VPC Private subnets. Data services (Aurora, Valkey, OpenSearch) in Data subnets. CloudFront -> ALB -> EC2/EKS pattern for public access. All 3 VPCs share identical subnet tier structure.

**Tech Stack:** CloudFormation YAML, AWS CDK (TypeScript), Terraform HCL, Shell scripts, Kustomize

---

## Subnet CIDR Design (all VPCs)

| Tier | AZ-a | AZ-b | Mask | Purpose |
|------|------|------|------|---------|
| Public | 10.X.1.0/24 | 10.X.2.0/24 | /24 | ALB (no EC2) |
| Private | 10.X.32.0/19 | 10.X.64.0/19 | /19 | EKS, EC2 |
| Data | 10.X.96.0/21 | 10.X.104.0/21 | /21 | Aurora, Valkey, OpenSearch, MSK |
| Attach | 10.X.251.0/24 | 10.X.252.0/24 | /24 | TGW Attachment |
| FW (DMZ only) | 10.11.241.0/24 | 10.11.242.0/24 | /24 | Network Firewall |
| NAT GW (DMZ only) | 10.11.245.0/24 | 10.11.246.0/24 | /24 | NAT Gateway |

X = 11 (DMZ), 1 (VPC01), 2 (VPC02)

---

## Phase 1: VSCode Server Setup Script

### Task 1: Create VSCode Server deploy script with interactive prompts

**Files:**
- Create: `cloudformation/0.deploy-vscode-server.sh`
- Reference: `vscode_server_secure.yaml`

**Steps:**
1. Create `cloudformation/` directory structure
2. Copy `vscode_server_secure.yaml` to `cloudformation/vscode_server_secure.yaml`
3. Create `cloudformation/0.deploy-vscode-server.sh` that:
   - Prompts for VSCode password (with validation >= 8 chars)
   - Prompts for AWS region (default: ap-northeast-2)
   - Looks up CloudFront Prefix List ID for the chosen region
   - Deploys the CF stack `mgmt-vpc`
   - Outputs CloudFront URL on completion
4. Make executable, commit

---

## Phase 2: Network Infrastructure (CloudFormation)

### Task 2: Create DMZ VPC CloudFormation template

**Files:**
- Create: `cloudformation/1.DMZVPC.yaml`

**Steps:**
1. Create new DMZVPC template with:
   - 8 subnet tiers: Public A/B, Private A/B, Data A/B, Attach A/B, FW A/B, NATGW A/B
   - IGW, NAT GW (per AZ in NATGW subnets)
   - AWS Network Firewall in FW subnets
   - Route tables: Public→IGW, Private→NFW→NATGW, Data→NATGW, Attach→TGW
   - ALB in Public subnets → Target Group for Private subnet EC2
   - CloudFront → ALB with custom header protection (same pattern as vscode_server_secure.yaml)
   - SSM VPC Endpoints
   - EC2 instances in Private subnets only (NO EC2 in Public)
   - AWS best-practice Tags: Name, Environment, Project, ManagedBy, CostCenter
   - Outputs: VPC ID, all Subnet IDs, SG IDs, ALB DNS, CloudFront URL
2. Validate template
3. Commit

### Task 3: Create VPC01 CloudFormation template

**Files:**
- Create: `cloudformation/2.VPC01.yaml`

**Steps:**
1. Same subnet structure as DMZ VPC but WITHOUT:
   - Network Firewall subnets
   - NAT GW subnets / NAT Gateway
   - IGW
   - CloudFront / ALB
2. Private/Data traffic routes to TGW → DMZ VPC for internet
3. SSM VPC Endpoints
4. EC2 instances in Private subnets
5. Same tagging convention
6. Commit

### Task 4: Create VPC02 CloudFormation template

**Files:**
- Create: `cloudformation/3.VPC02.yaml`

**Steps:**
1. Identical to VPC01 but with 10.2.0.0/16 CIDR
2. Commit

### Task 5: Create TGW CloudFormation template

**Files:**
- Create: `cloudformation/4.TGW.yaml`

**Steps:**
1. Transit Gateway with:
   - 3 VPC Attachments (DMZ, VPC01, VPC02) in Attach subnets
   - Route table: all VPC CIDRs + default route to DMZ
   - Cross-stack references via Fn::ImportValue
2. Commit

### Task 6: Create VPC/TGW deploy scripts

**Files:**
- Create: `cloudformation/1.deploy-all-vpcs.sh`
- Create: `cloudformation/2.deploy-tgw.sh`

**Steps:**
1. Deploy script with region prompt, parallel VPC deployment, status reporting
2. TGW deploy script (sequential, depends on VPCs)
3. Commit

---

## Phase 3: EKS (CloudFormation)

### Task 7: Create EKS setup and deploy scripts

**Files:**
- Create: `cloudformation/eks-setup-env.sh`
- Create: `cloudformation/eks-create-cluster.sh`
- Create: `cloudformation/eks-cleanup.sh`
- Create: `cloudformation/deploy-lbc.sh`

**Steps:**
1. Adapt existing scripts to new DMZVPC output names
2. EKS cluster in DMZ VPC Private subnets
3. Best practices: managed node groups, IRSA, EBS CSI, VPC CNI
4. Commit

---

## Phase 4: Data Services (CloudFormation)

### Task 8: Create Valkey (ElastiCache) stack

**Files:**
- Create: `cloudformation/valkey-cluster-stack.yaml`
- Create: `cloudformation/deploy-valkey.sh`

**Steps:**
1. Adapt existing template to use Data subnets instead of Private
2. Security group allows access from all 3 VPCs
3. Deploy script
4. Commit

### Task 9: Create Aurora MySQL stack

**Files:**
- Create: `cloudformation/aurora-mysql-stack.yaml`
- Create: `cloudformation/deploy-aurora.sh`

**Steps:**
1. Adapt existing template to use Data subnets
2. SG allows access from DMZ + VPC01 + VPC02
3. Interactive deploy script (prompts for DB name, user, password)
4. Commit

---

## Phase 5: Sample Application

### Task 10: Create sample application with EC2/EKS/Valkey/Aurora integration

**Files:**
- Create: `cloudformation/sample-app/` directory with Kustomize manifests
- Adapt: `base-application/` patterns

**Steps:**
1. App that connects to Aurora (catalog) and Valkey (session/cache)
2. Kubernetes deployments referencing real Aurora/Valkey endpoints
3. ConfigMaps with connection info from CF stack outputs
4. Deploy script
5. Commit

---

## Phase 6: CDK Version

### Task 11: CDK project initialization

**Files:**
- Create: `cdk/` directory with CDK TypeScript project

**Steps:**
1. `cdk init app --language typescript`
2. Stacks: VscodeServerStack, DmzVpcStack, Vpc01Stack, Vpc02Stack, TgwStack, EksStack, DataServicesStack, SampleAppStack
3. Same architecture as CF version
4. Commit

### Task 12-16: Implement each CDK stack
(One task per stack, mirroring CF templates)

---

## Phase 7: Terraform Version

### Task 17: Terraform project initialization

**Files:**
- Create: `terraform/` directory with module structure

**Steps:**
1. Modules: vscode-server, vpc, tgw, eks, data-services, sample-app
2. Environments: dev (single tfvars)
3. Same architecture as CF version
4. Commit

### Task 18-22: Implement each Terraform module
(One task per module, mirroring CF templates)

---

## Phase 8: Multi-Account Testing

### Task 23: Create AWS CLI profiles for 3 accounts

**Files:**
- Create: `setup-test-profiles.sh`

**Steps:**
1. Configure named profiles: lab-cf, lab-cdk, lab-terraform
2. Test connectivity for each
3. Commit

### Task 24-26: Deploy and verify per account
- Task 24: CF deployment to whchoi030701
- Task 25: CDK deployment to whchoi030702
- Task 26: Terraform deployment to whchoi030703

Each task follows: deploy → verify → document results

---

## Execution Order

Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7 → Phase 8

Verify after each phase completes (steps 1-6 verification as requested).
