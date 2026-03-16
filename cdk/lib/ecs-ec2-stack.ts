import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import { commonTags } from './config';
import { DmzVpcStack } from './dmz-vpc-stack';

export interface EcsEc2StackProps extends cdk.StackProps {
  dmzVpcStack: DmzVpcStack;
}

export class EcsEc2Stack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EcsEc2StackProps) {
    super(scope, id, props);

    const tags = commonTags();
    const dmzVpc = props.dmzVpcStack;

    // ========================================================================
    // ECS Cluster
    // ========================================================================
    const cluster = new ecs.CfnCluster(this, 'Ec2Cluster', {
      clusterName: 'lab-shop-ecs',
      clusterSettings: [
        { name: 'containerInsights', value: 'enabled' },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-ecs' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Cloud Map Namespace
    // ========================================================================
    const namespace = new servicediscovery.CfnPrivateDnsNamespace(this, 'Ec2Namespace', {
      name: 'lab-shop.local',
      vpc: dmzVpc.vpcId,
      description: 'Service discovery namespace for ECS EC2 services',
      tags: [{ key: 'Name', value: 'lab-shop.local' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Security Groups
    // ========================================================================
    const albSg = new ec2.CfnSecurityGroup(this, 'Ec2AlbSg', {
      groupDescription: 'Security group for ECS EC2 ALB',
      vpcId: dmzVpc.vpcId,
      securityGroupIngress: [
        { ipProtocol: 'tcp', fromPort: 80, toPort: 80, cidrIp: '0.0.0.0/0' },
        { ipProtocol: 'tcp', fromPort: 443, toPort: 443, cidrIp: '0.0.0.0/0' },
      ],
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-alb-sg' }, ...this.toTags(tags)],
    });

    const tasksSg = new ec2.CfnSecurityGroup(this, 'Ec2TasksSg', {
      groupDescription: 'Security group for ECS EC2 tasks',
      vpcId: dmzVpc.vpcId,
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-tasks-sg' }, ...this.toTags(tags)],
    });

    // Allow ALB to tasks on all ports
    new ec2.CfnSecurityGroupIngress(this, 'Ec2TasksFromAlb', {
      groupId: tasksSg.ref,
      ipProtocol: 'tcp',
      fromPort: 0,
      toPort: 65535,
      sourceSecurityGroupId: albSg.ref,
    });

    // Self-referencing rule for inter-service communication
    new ec2.CfnSecurityGroupIngress(this, 'Ec2TasksSelfRef', {
      groupId: tasksSg.ref,
      ipProtocol: 'tcp',
      fromPort: 0,
      toPort: 65535,
      sourceSecurityGroupId: tasksSg.ref,
    });

    // ========================================================================
    // IAM Roles
    // ========================================================================
    const taskExecutionRole = new iam.CfnRole(this, 'Ec2TaskExecutionRole', {
      roleName: 'lab-ecs-ec2-task-execution-role',
      assumeRolePolicyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Effect: 'Allow',
          Principal: { Service: 'ecs-tasks.amazonaws.com' },
          Action: 'sts:AssumeRole',
        }],
      },
      managedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy',
      ],
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-task-execution-role' }, ...this.toTags(tags)],
    });

    const taskRole = new iam.CfnRole(this, 'Ec2TaskRole', {
      roleName: 'lab-ecs-ec2-task-role',
      assumeRolePolicyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Effect: 'Allow',
          Principal: { Service: 'ecs-tasks.amazonaws.com' },
          Action: 'sts:AssumeRole',
        }],
      },
      policies: [{
        policyName: 'lab-ecs-ec2-task-policy',
        policyDocument: {
          Version: '2012-10-17',
          Statement: [
            {
              Effect: 'Allow',
              Action: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              Resource: '*',
            },
            {
              Effect: 'Allow',
              Action: [
                'xray:PutTraceSegments',
                'xray:PutTelemetryRecords',
              ],
              Resource: '*',
            },
          ],
        },
      }],
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-task-role' }, ...this.toTags(tags)],
    });

    // EC2 Instance Role for ECS
    const ec2Role = new iam.CfnRole(this, 'EcsEc2InstanceRole', {
      roleName: 'lab-ecs-ec2-instance-role',
      assumeRolePolicyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Effect: 'Allow',
          Principal: { Service: 'ec2.amazonaws.com' },
          Action: 'sts:AssumeRole',
        }],
      },
      managedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role',
        'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore',
      ],
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-instance-role' }, ...this.toTags(tags)],
    });

    const instanceProfile = new iam.CfnInstanceProfile(this, 'EcsEc2InstanceProfile', {
      instanceProfileName: 'lab-ecs-ec2-instance-profile',
      roles: [ec2Role.ref],
    });

    // ========================================================================
    // CloudWatch Log Groups
    // ========================================================================
    const logGroupNames = ['ui', 'catalog', 'carts', 'checkout', 'orders'];
    const logGroups: Record<string, logs.CfnLogGroup> = {};
    for (const name of logGroupNames) {
      logGroups[name] = new logs.CfnLogGroup(this, `Ec2LogGroup${name}`, {
        logGroupName: `/ecs/lab-shop-ec2/${name}`,
        retentionInDays: 7,
        tags: [{ key: 'Name', value: `/ecs/lab-shop-ec2/${name}` }, ...this.toTags(tags)],
      });
    }

    // ========================================================================
    // Auto Scaling Group + Capacity Provider
    // ========================================================================
    const ecsAmiId = cdk.Fn.ref('EcsAmiId');

    const ecsAmiParam = new cdk.CfnParameter(this, 'EcsAmiId', {
      type: 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>',
      default: '/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id',
      description: 'ECS-optimized AMI ID for ARM64',
    });

    const launchTemplate = new ec2.CfnLaunchTemplate(this, 'EcsLaunchTemplate', {
      launchTemplateName: 'lab-ecs-ec2-lt',
      launchTemplateData: {
        instanceType: 't4g.large',
        imageId: ecsAmiId,
        iamInstanceProfile: { arn: instanceProfile.attrArn },
        securityGroupIds: [tasksSg.ref],
        userData: cdk.Fn.base64(
          cdk.Fn.sub([
            '#!/bin/bash',
            'echo ECS_CLUSTER=${ClusterName} >> /etc/ecs/ecs.config',
          ].join('\n'), {
            ClusterName: cluster.ref,
          }),
        ),
        tagSpecifications: [{
          resourceType: 'instance',
          tags: [{ key: 'Name', value: 'lab-ecs-ec2-instance' }, ...this.toTags(tags)],
        }],
      },
      tagSpecifications: [{
        resourceType: 'launch-template',
        tags: [{ key: 'Name', value: 'lab-ecs-ec2-lt' }, ...this.toTags(tags)],
      }],
    });

    const asg = new autoscaling.CfnAutoScalingGroup(this, 'EcsAsg', {
      autoScalingGroupName: 'lab-ecs-ec2-asg',
      minSize: '1',
      maxSize: '6',
      desiredCapacity: '3',
      launchTemplate: {
        launchTemplateId: launchTemplate.ref,
        version: launchTemplate.attrLatestVersionNumber,
      },
      vpcZoneIdentifier: [dmzVpc.privateSubnetA.ref, dmzVpc.privateSubnetB.ref],
      tags: [
        { key: 'Name', value: 'lab-ecs-ec2-instance', propagateAtLaunch: true },
        ...this.toAsgTags(tags),
      ],
    });

    const capacityProvider = new ecs.CfnCapacityProvider(this, 'EcsCapacityProvider', {
      name: 'lab-ecs-ec2-cp',
      autoScalingGroupProvider: {
        autoScalingGroupArn: asg.ref,
        managedScaling: {
          status: 'ENABLED',
          targetCapacity: 100,
          minimumScalingStepSize: 1,
          maximumScalingStepSize: 2,
        },
        managedTerminationProtection: 'DISABLED',
      },
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-cp' }, ...this.toTags(tags)],
    });

    const clusterCpAssoc = new ecs.CfnClusterCapacityProviderAssociations(this, 'EcsClusterCpAssoc', {
      cluster: cluster.ref,
      capacityProviders: [capacityProvider.ref],
      defaultCapacityProviderStrategy: [{
        capacityProvider: capacityProvider.ref,
        weight: 1,
        base: 0,
      }],
    });

    // ========================================================================
    // ALB
    // ========================================================================
    const alb = new elbv2.CfnLoadBalancer(this, 'Ec2Alb', {
      name: 'lab-ecs-ec2-alb',
      scheme: 'internet-facing',
      type: 'application',
      subnets: [dmzVpc.publicSubnetA.ref, dmzVpc.publicSubnetB.ref],
      securityGroups: [albSg.ref],
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-alb' }, ...this.toTags(tags)],
    });

    const uiTargetGroup = new elbv2.CfnTargetGroup(this, 'Ec2UiTg', {
      name: 'lab-ecs-ec2-ui-tg',
      port: 8080,
      protocol: 'HTTP',
      vpcId: dmzVpc.vpcId,
      targetType: 'instance',
      healthCheckPath: '/actuator/health',
      healthCheckProtocol: 'HTTP',
      healthCheckIntervalSeconds: 30,
      healthyThresholdCount: 2,
      unhealthyThresholdCount: 3,
      tags: [{ key: 'Name', value: 'lab-ecs-ec2-ui-tg' }, ...this.toTags(tags)],
    });

    new elbv2.CfnListener(this, 'Ec2AlbListener', {
      loadBalancerArn: alb.ref,
      port: 80,
      protocol: 'HTTP',
      defaultActions: [{
        type: 'forward',
        targetGroupArn: uiTargetGroup.ref,
      }],
    });

    // ========================================================================
    // Cloud Map Service Discovery Services
    // ========================================================================
    const serviceNames = ['catalog', 'carts', 'checkout', 'orders'];
    const discoveryServices: Record<string, servicediscovery.CfnService> = {};
    for (const name of serviceNames) {
      discoveryServices[name] = new servicediscovery.CfnService(this, `Ec2Discovery${name}`, {
        name,
        namespaceId: namespace.attrId,
        dnsConfig: {
          dnsRecords: [{ type: 'SRV', ttl: 10 }],
          namespaceId: namespace.attrId,
        },
        healthCheckCustomConfig: {
          failureThreshold: 1,
        },
      });
    }

    // ========================================================================
    // Service: Catalog + MySQL sidecar (bridge networking with links)
    // ========================================================================
    const catalogTd = new ecs.CfnTaskDefinition(this, 'Ec2CatalogTd', {
      family: 'lab-shop-ec2-catalog',
      networkMode: 'bridge',
      requiresCompatibilities: ['EC2'],
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      containerDefinitions: [
        {
          name: 'catalog',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-catalog:1.2.1',
          essential: true,
          memory: 512,
          portMappings: [{ containerPort: 8080, hostPort: 0, protocol: 'tcp' }],
          links: ['catalog-db'],
          environment: [
            { name: 'DB_ENDPOINT', value: 'catalog-db' },
            { name: 'DB_USER', value: 'catalog' },
            { name: 'DB_PASSWORD', value: 'dYmNfWV4uEvTzoFu' },
            { name: 'DB_NAME', value: 'catalog' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/catalog`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'catalog',
            },
          },
          dependsOn: [{ containerName: 'catalog-db', condition: 'START' }],
        },
        {
          name: 'catalog-db',
          image: 'public.ecr.aws/docker/library/mysql:8.0',
          essential: true,
          memory: 512,
          portMappings: [{ containerPort: 3306, hostPort: 0, protocol: 'tcp' }],
          environment: [
            { name: 'MYSQL_ROOT_PASSWORD', value: 'dYmNfWV4uEvTzoFu' },
            { name: 'MYSQL_USER', value: 'catalog' },
            { name: 'MYSQL_PASSWORD', value: 'dYmNfWV4uEvTzoFu' },
            { name: 'MYSQL_DATABASE', value: 'catalog' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/catalog`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'catalog-db',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-catalog-td' }, ...this.toTags(tags)],
    });

    const catalogSvc = new ecs.CfnService(this, 'Ec2CatalogSvc', {
      cluster: cluster.ref,
      serviceName: 'catalog',
      desiredCount: 1,
      taskDefinition: catalogTd.ref,
      capacityProviderStrategy: [{
        capacityProvider: capacityProvider.ref,
        weight: 1,
      }],
      serviceRegistries: [{
        registryArn: discoveryServices['catalog'].attrArn,
        containerName: 'catalog',
        containerPort: 8080,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-catalog-svc' }, ...this.toTags(tags)],
    });
    catalogSvc.addDependency(clusterCpAssoc);

    // ========================================================================
    // Service: Carts + DynamoDB Local sidecar (bridge networking with links)
    // ========================================================================
    const cartsTd = new ecs.CfnTaskDefinition(this, 'Ec2CartsTd', {
      family: 'lab-shop-ec2-carts',
      networkMode: 'bridge',
      requiresCompatibilities: ['EC2'],
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      containerDefinitions: [
        {
          name: 'carts',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-cart:1.2.1',
          essential: true,
          memory: 512,
          portMappings: [{ containerPort: 8080, hostPort: 0, protocol: 'tcp' }],
          links: ['carts-db'],
          environment: [
            { name: 'CARTS_DYNAMODB_ENDPOINT', value: 'http://carts-db:8000' },
            { name: 'CARTS_DYNAMODB_TABLENAME', value: 'Items' },
            { name: 'AWS_ACCESS_KEY_ID', value: 'key' },
            { name: 'AWS_SECRET_ACCESS_KEY', value: 'secret' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/carts`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'carts',
            },
          },
          dependsOn: [{ containerName: 'carts-db', condition: 'START' }],
        },
        {
          name: 'carts-db',
          image: 'amazon/dynamodb-local:2.0.0',
          essential: true,
          memory: 256,
          portMappings: [{ containerPort: 8000, hostPort: 0, protocol: 'tcp' }],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/carts`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'carts-db',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-carts-td' }, ...this.toTags(tags)],
    });

    const cartsSvc = new ecs.CfnService(this, 'Ec2CartsSvc', {
      cluster: cluster.ref,
      serviceName: 'carts',
      desiredCount: 1,
      taskDefinition: cartsTd.ref,
      capacityProviderStrategy: [{
        capacityProvider: capacityProvider.ref,
        weight: 1,
      }],
      serviceRegistries: [{
        registryArn: discoveryServices['carts'].attrArn,
        containerName: 'carts',
        containerPort: 8080,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-carts-svc' }, ...this.toTags(tags)],
    });
    cartsSvc.addDependency(clusterCpAssoc);

    // ========================================================================
    // Service: Checkout + Redis sidecar (bridge networking with links)
    // ========================================================================
    const checkoutTd = new ecs.CfnTaskDefinition(this, 'Ec2CheckoutTd', {
      family: 'lab-shop-ec2-checkout',
      networkMode: 'bridge',
      requiresCompatibilities: ['EC2'],
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      containerDefinitions: [
        {
          name: 'checkout',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-checkout:1.2.1',
          essential: true,
          memory: 512,
          portMappings: [{ containerPort: 8080, hostPort: 0, protocol: 'tcp' }],
          links: ['checkout-redis'],
          environment: [
            { name: 'REDIS_URL', value: 'redis://checkout-redis:6379' },
            { name: 'ENDPOINTS_ORDERS', value: 'http://orders.lab-shop.local:8080' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/checkout`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'checkout',
            },
          },
          dependsOn: [{ containerName: 'checkout-redis', condition: 'START' }],
        },
        {
          name: 'checkout-redis',
          image: 'public.ecr.aws/docker/library/redis:7-alpine',
          essential: true,
          memory: 256,
          portMappings: [{ containerPort: 6379, hostPort: 0, protocol: 'tcp' }],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/checkout`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'checkout-redis',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-checkout-td' }, ...this.toTags(tags)],
    });

    const checkoutSvc = new ecs.CfnService(this, 'Ec2CheckoutSvc', {
      cluster: cluster.ref,
      serviceName: 'checkout',
      desiredCount: 1,
      taskDefinition: checkoutTd.ref,
      capacityProviderStrategy: [{
        capacityProvider: capacityProvider.ref,
        weight: 1,
      }],
      serviceRegistries: [{
        registryArn: discoveryServices['checkout'].attrArn,
        containerName: 'checkout',
        containerPort: 8080,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-checkout-svc' }, ...this.toTags(tags)],
    });
    checkoutSvc.addDependency(clusterCpAssoc);

    // ========================================================================
    // Service: Orders + PostgreSQL sidecar (bridge networking with links)
    // ========================================================================
    const ordersTd = new ecs.CfnTaskDefinition(this, 'Ec2OrdersTd', {
      family: 'lab-shop-ec2-orders',
      networkMode: 'bridge',
      requiresCompatibilities: ['EC2'],
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      containerDefinitions: [
        {
          name: 'orders',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-orders:1.2.1',
          essential: true,
          memory: 512,
          portMappings: [{ containerPort: 8080, hostPort: 0, protocol: 'tcp' }],
          links: ['orders-db'],
          environment: [
            { name: 'SPRING_DATASOURCE_URL', value: 'jdbc:postgresql://orders-db:5432/orders' },
            { name: 'SPRING_DATASOURCE_USERNAME', value: 'orders' },
            { name: 'SPRING_DATASOURCE_PASSWORD', value: '3z6sGLhGunfn0xZc' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/orders`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'orders',
            },
          },
          dependsOn: [{ containerName: 'orders-db', condition: 'START' }],
        },
        {
          name: 'orders-db',
          image: 'public.ecr.aws/docker/library/postgres:16-alpine',
          essential: true,
          memory: 256,
          portMappings: [{ containerPort: 5432, hostPort: 0, protocol: 'tcp' }],
          environment: [
            { name: 'POSTGRES_USER', value: 'orders' },
            { name: 'POSTGRES_PASSWORD', value: '3z6sGLhGunfn0xZc' },
            { name: 'POSTGRES_DB', value: 'orders' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/orders`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'orders-db',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-orders-td' }, ...this.toTags(tags)],
    });

    const ordersSvc = new ecs.CfnService(this, 'Ec2OrdersSvc', {
      cluster: cluster.ref,
      serviceName: 'orders',
      desiredCount: 1,
      taskDefinition: ordersTd.ref,
      capacityProviderStrategy: [{
        capacityProvider: capacityProvider.ref,
        weight: 1,
      }],
      serviceRegistries: [{
        registryArn: discoveryServices['orders'].attrArn,
        containerName: 'orders',
        containerPort: 8080,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-orders-svc' }, ...this.toTags(tags)],
    });
    ordersSvc.addDependency(clusterCpAssoc);

    // ========================================================================
    // Service: UI (base app)
    // ========================================================================
    const uiTd = new ecs.CfnTaskDefinition(this, 'Ec2UiTd', {
      family: 'lab-shop-ec2-ui',
      networkMode: 'bridge',
      requiresCompatibilities: ['EC2'],
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      containerDefinitions: [
        {
          name: 'ui',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-ui:1.2.1',
          essential: true,
          memory: 512,
          portMappings: [{ containerPort: 8080, hostPort: 0, protocol: 'tcp' }],
          environment: [
            { name: 'RETAIL_UI_ENDPOINTS_CATALOG', value: 'http://catalog.lab-shop.local:8080' },
            { name: 'RETAIL_UI_ENDPOINTS_CARTS', value: 'http://carts.lab-shop.local:8080' },
            { name: 'RETAIL_UI_ENDPOINTS_CHECKOUT', value: 'http://checkout.lab-shop.local:8080' },
            { name: 'RETAIL_UI_ENDPOINTS_ORDERS', value: 'http://orders.lab-shop.local:8080' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-ec2/ui`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'ui',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-ui-td' }, ...this.toTags(tags)],
    });

    const uiSvc = new ecs.CfnService(this, 'Ec2UiSvc', {
      cluster: cluster.ref,
      serviceName: 'ui',
      desiredCount: 2,
      taskDefinition: uiTd.ref,
      capacityProviderStrategy: [{
        capacityProvider: capacityProvider.ref,
        weight: 1,
      }],
      loadBalancers: [{
        containerName: 'ui',
        containerPort: 8080,
        targetGroupArn: uiTargetGroup.ref,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-ec2-ui-svc' }, ...this.toTags(tags)],
    });
    uiSvc.addDependency(clusterCpAssoc);

    // ========================================================================
    // Stack Outputs
    // ========================================================================
    new cdk.CfnOutput(this, 'Ec2ClusterName', {
      value: cluster.ref,
      exportName: 'EcsEc2ClusterName',
    });

    new cdk.CfnOutput(this, 'Ec2AlbDnsName', {
      value: cdk.Fn.getAtt(alb.logicalId, 'DNSName').toString(),
      exportName: 'EcsEc2AlbDnsName',
    });

    new cdk.CfnOutput(this, 'Ec2NamespaceId', {
      value: namespace.attrId,
      exportName: 'EcsEc2NamespaceId',
    });
  }

  private toTags(tags: Record<string, string>): { key: string; value: string }[] {
    return Object.entries(tags).map(([key, value]) => ({ key, value }));
  }

  private toAsgTags(tags: Record<string, string>): { key: string; value: string; propagateAtLaunch: boolean }[] {
    return Object.entries(tags).map(([key, value]) => ({ key, value, propagateAtLaunch: true }));
  }
}
