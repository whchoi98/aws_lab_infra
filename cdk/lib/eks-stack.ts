import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { commonTags } from './config';

/**
 * EKS Stack - Placeholder
 *
 * The EKS cluster is managed via eksctl rather than CDK for the following reasons:
 *
 * 1. The CDK L2 construct for EKS (aws-eks) is complex and creates many nested
 *    resources including a custom resource Lambda for kubectl operations.
 *
 * 2. eksctl provides a more streamlined experience for EKS cluster lifecycle
 *    management including managed node groups, add-ons, and IAM integration.
 *
 * 3. The lab scripts already use eksctl for cluster creation with specific
 *    configurations for VPC subnets, security groups, and add-ons.
 *
 * To create the EKS cluster, use the existing setup scripts:
 *   - create-eks-cluster.sh: Creates the EKS cluster using eksctl
 *   - deploy-lbc.sh: Deploys the AWS Load Balancer Controller
 *   - setup-cloudwatch.sh: Configures CloudWatch monitoring
 *
 * Example eksctl cluster config:
 *   apiVersion: eksctl.io/v1alpha5
 *   kind: ClusterConfig
 *   metadata:
 *     name: lab-eks-cluster
 *     region: ap-northeast-2
 *   vpc:
 *     subnets:
 *       private:
 *         ap-northeast-2a:
 *           id: <VPC01 Private Subnet A>
 *         ap-northeast-2b:
 *           id: <VPC01 Private Subnet B>
 *   managedNodeGroups:
 *     - name: lab-ng
 *       instanceType: t3.medium
 *       desiredCapacity: 2
 *       minSize: 1
 *       maxSize: 4
 */
export class EksStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const tags = commonTags();

    // Apply tags to the stack
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // ========================================================================
    // Placeholder Output
    // ========================================================================
    new cdk.CfnOutput(this, 'EksInstructions', {
      value: 'EKS cluster should be created using eksctl. See comments in eks-stack.ts for details.',
      description: 'Instructions for EKS cluster creation',
    });

    new cdk.CfnOutput(this, 'EksClusterNameSuggestion', {
      value: 'lab-eks-cluster',
      description: 'Suggested EKS cluster name for eksctl',
      exportName: 'EksClusterNameSuggestion',
    });

    new cdk.CfnOutput(this, 'EksRegion', {
      value: this.region,
      description: 'Region for EKS cluster deployment',
      exportName: 'EksRegion',
    });
  }
}
