#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DmzVpcStack } from '../lib/dmz-vpc-stack';
import { Vpc01Stack } from '../lib/vpc01-stack';
import { Vpc02Stack } from '../lib/vpc02-stack';
import { TgwStack } from '../lib/tgw-stack';
import { EksStack } from '../lib/eks-stack';
import { DataServicesStack } from '../lib/data-services-stack';
import { EcsFargateStack } from '../lib/ecs-fargate-stack';
import { EcsEc2Stack } from '../lib/ecs-ec2-stack';
import { LAB_CONFIG } from '../lib/config';

const app = new cdk.App();

const env: cdk.Environment = {
  region: LAB_CONFIG.region,
  account: process.env.CDK_DEFAULT_ACCOUNT,
};

// ============================================================================
// VPC Stacks (no inter-dependencies, can be deployed in parallel)
// ============================================================================
const dmzVpcStack = new DmzVpcStack(app, 'DmzVpcStack', {
  env,
  description: 'DMZ VPC with Network Firewall, ALB, CloudFront, and EC2 instances',
});

const vpc01Stack = new Vpc01Stack(app, 'Vpc01Stack', {
  env,
  description: 'VPC01 with private subnets and EC2 instances',
});

const vpc02Stack = new Vpc02Stack(app, 'Vpc02Stack', {
  env,
  description: 'VPC02 with private subnets and EC2 instances',
});

// ============================================================================
// Transit Gateway Stack (depends on all VPC stacks)
// ============================================================================
const tgwStack = new TgwStack(app, 'TgwStack', {
  env,
  description: 'Transit Gateway connecting DMZ, VPC01, and VPC02',
  dmzVpcStack,
  vpc01Stack,
  vpc02Stack,
});
tgwStack.addDependency(dmzVpcStack);
tgwStack.addDependency(vpc01Stack);
tgwStack.addDependency(vpc02Stack);

// ============================================================================
// EKS Stack (placeholder - actual cluster created via eksctl)
// ============================================================================
const eksStack = new EksStack(app, 'EksStack', {
  env,
  description: 'EKS placeholder stack - cluster managed via eksctl',
});
eksStack.addDependency(vpc01Stack);

// ============================================================================
// Data Services Stack (depends on DMZ VPC for subnets)
// ============================================================================
const dataServicesStack = new DataServicesStack(app, 'DataServicesStack', {
  env,
  description: 'Aurora MySQL and Valkey (ElastiCache) in DMZ data subnets',
  dmzVpcStack,
});
dataServicesStack.addDependency(dmzVpcStack);
dataServicesStack.addDependency(tgwStack);

// ============================================================================
// ECS Fargate Stack (depends on DMZ VPC for subnets)
// ============================================================================
const ecsFargateStack = new EcsFargateStack(app, 'EcsFargateStack', {
  env,
  description: 'ECS Fargate ARM64 with bilingual shop microservices',
  dmzVpcStack,
});
ecsFargateStack.addDependency(dmzVpcStack);

// ============================================================================
// ECS EC2 Stack (depends on DMZ VPC for subnets)
// ============================================================================
const ecsEc2Stack = new EcsEc2Stack(app, 'EcsEc2Stack', {
  env,
  description: 'ECS EC2 Graviton (t4g.large) with base shop microservices',
  dmzVpcStack,
});
ecsEc2Stack.addDependency(dmzVpcStack);

app.synth();
