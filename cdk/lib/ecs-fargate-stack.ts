import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import { commonTags } from './config';
import { DmzVpcStack } from './dmz-vpc-stack';

export interface EcsFargateStackProps extends cdk.StackProps {
  dmzVpcStack: DmzVpcStack;
  bilingualEcrUri?: string;
}

export class EcsFargateStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EcsFargateStackProps) {
    super(scope, id, props);

    const tags = commonTags();
    const dmzVpc = props.dmzVpcStack;

    // ========================================================================
    // ECS Cluster
    // ========================================================================
    const cluster = new ecs.CfnCluster(this, 'FargateCluster', {
      clusterName: 'lab-shop-ecs-fargate',
      clusterSettings: [
        { name: 'containerInsights', value: 'enabled' },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-ecs-fargate' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Cloud Map Namespace
    // ========================================================================
    const namespace = new servicediscovery.CfnPrivateDnsNamespace(this, 'FargateNamespace', {
      name: 'lab-shop-fg.local',
      vpc: dmzVpc.vpcId,
      description: 'Service discovery namespace for ECS Fargate services',
      tags: [{ key: 'Name', value: 'lab-shop-fg.local' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Security Groups
    // ========================================================================
    const albSg = new ec2.CfnSecurityGroup(this, 'FargateAlbSg', {
      groupDescription: 'Security group for ECS Fargate ALB',
      vpcId: dmzVpc.vpcId,
      securityGroupIngress: [
        { ipProtocol: 'tcp', fromPort: 80, toPort: 80, cidrIp: '0.0.0.0/0' },
        { ipProtocol: 'tcp', fromPort: 443, toPort: 443, cidrIp: '0.0.0.0/0' },
      ],
      tags: [{ key: 'Name', value: 'lab-ecs-fg-alb-sg' }, ...this.toTags(tags)],
    });

    const tasksSg = new ec2.CfnSecurityGroup(this, 'FargateTasksSg', {
      groupDescription: 'Security group for ECS Fargate tasks',
      vpcId: dmzVpc.vpcId,
      tags: [{ key: 'Name', value: 'lab-ecs-fg-tasks-sg' }, ...this.toTags(tags)],
    });

    // Allow ALB to tasks on all ports
    new ec2.CfnSecurityGroupIngress(this, 'FargateTasksFromAlb', {
      groupId: tasksSg.ref,
      ipProtocol: 'tcp',
      fromPort: 0,
      toPort: 65535,
      sourceSecurityGroupId: albSg.ref,
    });

    // Self-referencing rule for inter-service communication
    new ec2.CfnSecurityGroupIngress(this, 'FargateTasksSelfRef', {
      groupId: tasksSg.ref,
      ipProtocol: 'tcp',
      fromPort: 0,
      toPort: 65535,
      sourceSecurityGroupId: tasksSg.ref,
    });

    // ========================================================================
    // IAM Roles
    // ========================================================================
    const taskExecutionRole = new iam.CfnRole(this, 'FargateTaskExecutionRole', {
      roleName: 'lab-ecs-fg-task-execution-role',
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
      tags: [{ key: 'Name', value: 'lab-ecs-fg-task-execution-role' }, ...this.toTags(tags)],
    });

    const taskRole = new iam.CfnRole(this, 'FargateTaskRole', {
      roleName: 'lab-ecs-fg-task-role',
      assumeRolePolicyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Effect: 'Allow',
          Principal: { Service: 'ecs-tasks.amazonaws.com' },
          Action: 'sts:AssumeRole',
        }],
      },
      policies: [{
        policyName: 'lab-ecs-fg-task-policy',
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
      tags: [{ key: 'Name', value: 'lab-ecs-fg-task-role' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // CloudWatch Log Groups
    // ========================================================================
    const logGroupNames = ['ui', 'catalog', 'carts', 'checkout', 'orders'];
    const logGroups: Record<string, logs.CfnLogGroup> = {};
    for (const name of logGroupNames) {
      logGroups[name] = new logs.CfnLogGroup(this, `FgLogGroup${name}`, {
        logGroupName: `/ecs/lab-shop-fg/${name}`,
        retentionInDays: 7,
        tags: [{ key: 'Name', value: `/ecs/lab-shop-fg/${name}` }, ...this.toTags(tags)],
      });
    }

    // ========================================================================
    // ALB
    // ========================================================================
    const alb = new elbv2.CfnLoadBalancer(this, 'FargateAlb', {
      name: 'lab-ecs-fg-alb',
      scheme: 'internet-facing',
      type: 'application',
      subnets: [dmzVpc.publicSubnetA.ref, dmzVpc.publicSubnetB.ref],
      securityGroups: [albSg.ref],
      tags: [{ key: 'Name', value: 'lab-ecs-fg-alb' }, ...this.toTags(tags)],
    });

    const uiTargetGroup = new elbv2.CfnTargetGroup(this, 'FargateUiTg', {
      name: 'lab-ecs-fg-ui-tg',
      port: 8080,
      protocol: 'HTTP',
      vpcId: dmzVpc.vpcId,
      targetType: 'ip',
      healthCheckPath: '/health',
      healthCheckProtocol: 'HTTP',
      healthCheckIntervalSeconds: 30,
      healthyThresholdCount: 2,
      unhealthyThresholdCount: 3,
      tags: [{ key: 'Name', value: 'lab-ecs-fg-ui-tg' }, ...this.toTags(tags)],
    });

    new elbv2.CfnListener(this, 'FargateAlbListener', {
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
      discoveryServices[name] = new servicediscovery.CfnService(this, `FgDiscovery${name}`, {
        name,
        namespaceId: namespace.attrId,
        dnsConfig: {
          dnsRecords: [{ type: 'A', ttl: 10 }],
          namespaceId: namespace.attrId,
        },
        healthCheckCustomConfig: {
          failureThreshold: 1,
        },
      });
    }

    // ========================================================================
    // Service: Catalog + MySQL sidecar
    // ========================================================================
    const catalogTd = new ecs.CfnTaskDefinition(this, 'FgCatalogTd', {
      family: 'lab-shop-fg-catalog',
      networkMode: 'awsvpc',
      requiresCompatibilities: ['FARGATE'],
      cpu: '512',
      memory: '1024',
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      runtimePlatform: {
        cpuArchitecture: 'ARM64',
        operatingSystemFamily: 'LINUX',
      },
      containerDefinitions: [
        {
          name: 'catalog',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-catalog:1.2.1',
          essential: true,
          portMappings: [{ containerPort: 8080, protocol: 'tcp' }],
          environment: [
            { name: 'DB_ENDPOINT', value: 'localhost' },
            { name: 'DB_USER', value: 'catalog' },
            { name: 'DB_PASSWORD', value: 'dYmNfWV4uEvTzoFu' },
            { name: 'DB_NAME', value: 'catalog' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/catalog`,
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
          portMappings: [{ containerPort: 3306, protocol: 'tcp' }],
          environment: [
            { name: 'MYSQL_ROOT_PASSWORD', value: 'dYmNfWV4uEvTzoFu' },
            { name: 'MYSQL_USER', value: 'catalog' },
            { name: 'MYSQL_PASSWORD', value: 'dYmNfWV4uEvTzoFu' },
            { name: 'MYSQL_DATABASE', value: 'catalog' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/catalog`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'catalog-db',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-fg-catalog-td' }, ...this.toTags(tags)],
    });

    new ecs.CfnService(this, 'FgCatalogSvc', {
      cluster: cluster.ref,
      serviceName: 'catalog',
      desiredCount: 1,
      launchType: 'FARGATE',
      taskDefinition: catalogTd.ref,
      networkConfiguration: {
        awsvpcConfiguration: {
          subnets: [dmzVpc.privateSubnetA.ref, dmzVpc.privateSubnetB.ref],
          securityGroups: [tasksSg.ref],
          assignPublicIp: 'DISABLED',
        },
      },
      serviceRegistries: [{
        registryArn: discoveryServices['catalog'].attrArn,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-fg-catalog-svc' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Service: Carts + DynamoDB Local sidecar
    // ========================================================================
    const cartsTd = new ecs.CfnTaskDefinition(this, 'FgCartsTd', {
      family: 'lab-shop-fg-carts',
      networkMode: 'awsvpc',
      requiresCompatibilities: ['FARGATE'],
      cpu: '512',
      memory: '1024',
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      runtimePlatform: {
        cpuArchitecture: 'ARM64',
        operatingSystemFamily: 'LINUX',
      },
      containerDefinitions: [
        {
          name: 'carts',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-cart:1.2.1',
          essential: true,
          portMappings: [{ containerPort: 8080, protocol: 'tcp' }],
          environment: [
            { name: 'CARTS_DYNAMODB_ENDPOINT', value: 'http://localhost:8000' },
            { name: 'CARTS_DYNAMODB_TABLENAME', value: 'Items' },
            { name: 'AWS_ACCESS_KEY_ID', value: 'key' },
            { name: 'AWS_SECRET_ACCESS_KEY', value: 'secret' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/carts`,
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
          portMappings: [{ containerPort: 8000, protocol: 'tcp' }],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/carts`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'carts-db',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-fg-carts-td' }, ...this.toTags(tags)],
    });

    new ecs.CfnService(this, 'FgCartsSvc', {
      cluster: cluster.ref,
      serviceName: 'carts',
      desiredCount: 1,
      launchType: 'FARGATE',
      taskDefinition: cartsTd.ref,
      networkConfiguration: {
        awsvpcConfiguration: {
          subnets: [dmzVpc.privateSubnetA.ref, dmzVpc.privateSubnetB.ref],
          securityGroups: [tasksSg.ref],
          assignPublicIp: 'DISABLED',
        },
      },
      serviceRegistries: [{
        registryArn: discoveryServices['carts'].attrArn,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-fg-carts-svc' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Service: Checkout + Redis sidecar
    // ========================================================================
    const checkoutTd = new ecs.CfnTaskDefinition(this, 'FgCheckoutTd', {
      family: 'lab-shop-fg-checkout',
      networkMode: 'awsvpc',
      requiresCompatibilities: ['FARGATE'],
      cpu: '512',
      memory: '1024',
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      runtimePlatform: {
        cpuArchitecture: 'ARM64',
        operatingSystemFamily: 'LINUX',
      },
      containerDefinitions: [
        {
          name: 'checkout',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-checkout:1.2.1',
          essential: true,
          portMappings: [{ containerPort: 8080, protocol: 'tcp' }],
          environment: [
            { name: 'REDIS_URL', value: 'redis://localhost:6379' },
            { name: 'ENDPOINTS_ORDERS', value: 'http://orders.lab-shop-fg.local:8080' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/checkout`,
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
          portMappings: [{ containerPort: 6379, protocol: 'tcp' }],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/checkout`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'checkout-redis',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-fg-checkout-td' }, ...this.toTags(tags)],
    });

    new ecs.CfnService(this, 'FgCheckoutSvc', {
      cluster: cluster.ref,
      serviceName: 'checkout',
      desiredCount: 1,
      launchType: 'FARGATE',
      taskDefinition: checkoutTd.ref,
      networkConfiguration: {
        awsvpcConfiguration: {
          subnets: [dmzVpc.privateSubnetA.ref, dmzVpc.privateSubnetB.ref],
          securityGroups: [tasksSg.ref],
          assignPublicIp: 'DISABLED',
        },
      },
      serviceRegistries: [{
        registryArn: discoveryServices['checkout'].attrArn,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-fg-checkout-svc' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Service: Orders + PostgreSQL sidecar
    // ========================================================================
    const ordersTd = new ecs.CfnTaskDefinition(this, 'FgOrdersTd', {
      family: 'lab-shop-fg-orders',
      networkMode: 'awsvpc',
      requiresCompatibilities: ['FARGATE'],
      cpu: '512',
      memory: '1024',
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      runtimePlatform: {
        cpuArchitecture: 'ARM64',
        operatingSystemFamily: 'LINUX',
      },
      containerDefinitions: [
        {
          name: 'orders',
          image: 'public.ecr.aws/aws-containers/retail-store-sample-orders:1.2.1',
          essential: true,
          portMappings: [{ containerPort: 8080, protocol: 'tcp' }],
          environment: [
            { name: 'SPRING_DATASOURCE_URL', value: 'jdbc:postgresql://localhost:5432/orders' },
            { name: 'SPRING_DATASOURCE_USERNAME', value: 'orders' },
            { name: 'SPRING_DATASOURCE_PASSWORD', value: '3z6sGLhGunfn0xZc' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/orders`,
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
          portMappings: [{ containerPort: 5432, protocol: 'tcp' }],
          environment: [
            { name: 'POSTGRES_USER', value: 'orders' },
            { name: 'POSTGRES_PASSWORD', value: '3z6sGLhGunfn0xZc' },
            { name: 'POSTGRES_DB', value: 'orders' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/orders`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'orders-db',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-fg-orders-td' }, ...this.toTags(tags)],
    });

    new ecs.CfnService(this, 'FgOrdersSvc', {
      cluster: cluster.ref,
      serviceName: 'orders',
      desiredCount: 1,
      launchType: 'FARGATE',
      taskDefinition: ordersTd.ref,
      networkConfiguration: {
        awsvpcConfiguration: {
          subnets: [dmzVpc.privateSubnetA.ref, dmzVpc.privateSubnetB.ref],
          securityGroups: [tasksSg.ref],
          assignPublicIp: 'DISABLED',
        },
      },
      serviceRegistries: [{
        registryArn: discoveryServices['orders'].attrArn,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-fg-orders-svc' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Service: UI (bilingual)
    // ========================================================================
    const uiImage = props.bilingualEcrUri ?? 'public.ecr.aws/aws-containers/retail-store-sample-ui:1.2.1';

    const uiTd = new ecs.CfnTaskDefinition(this, 'FgUiTd', {
      family: 'lab-shop-fg-ui',
      networkMode: 'awsvpc',
      requiresCompatibilities: ['FARGATE'],
      cpu: '512',
      memory: '1024',
      executionRoleArn: taskExecutionRole.attrArn,
      taskRoleArn: taskRole.attrArn,
      runtimePlatform: {
        cpuArchitecture: 'ARM64',
        operatingSystemFamily: 'LINUX',
      },
      containerDefinitions: [
        {
          name: 'ui',
          image: uiImage,
          essential: true,
          portMappings: [{ containerPort: 8080, protocol: 'tcp' }],
          environment: [
            { name: 'ENDPOINTS_CATALOG', value: 'http://catalog.lab-shop-fg.local:8080' },
            { name: 'ENDPOINTS_CARTS', value: 'http://carts.lab-shop-fg.local:8080' },
            { name: 'ENDPOINTS_CHECKOUT', value: 'http://checkout.lab-shop-fg.local:8080' },
            { name: 'ENDPOINTS_ORDERS', value: 'http://orders.lab-shop-fg.local:8080' },
          ],
          logConfiguration: {
            logDriver: 'awslogs',
            options: {
              'awslogs-group': `/ecs/lab-shop-fg/ui`,
              'awslogs-region': this.region,
              'awslogs-stream-prefix': 'ui',
            },
          },
        },
      ],
      tags: [{ key: 'Name', value: 'lab-shop-fg-ui-td' }, ...this.toTags(tags)],
    });

    new ecs.CfnService(this, 'FgUiSvc', {
      cluster: cluster.ref,
      serviceName: 'ui',
      desiredCount: 2,
      launchType: 'FARGATE',
      taskDefinition: uiTd.ref,
      networkConfiguration: {
        awsvpcConfiguration: {
          subnets: [dmzVpc.privateSubnetA.ref, dmzVpc.privateSubnetB.ref],
          securityGroups: [tasksSg.ref],
          assignPublicIp: 'DISABLED',
        },
      },
      loadBalancers: [{
        containerName: 'ui',
        containerPort: 8080,
        targetGroupArn: uiTargetGroup.ref,
      }],
      tags: [{ key: 'Name', value: 'lab-shop-fg-ui-svc' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Stack Outputs
    // ========================================================================
    new cdk.CfnOutput(this, 'FargateClusterName', {
      value: cluster.ref,
      exportName: 'EcsFargateClusterName',
    });

    new cdk.CfnOutput(this, 'FargateAlbDnsName', {
      value: cdk.Fn.getAtt(alb.logicalId, 'DNSName').toString(),
      exportName: 'EcsFargateAlbDnsName',
    });

    new cdk.CfnOutput(this, 'FargateNamespaceId', {
      value: namespace.attrId,
      exportName: 'EcsFargateNamespaceId',
    });
  }

  private toTags(tags: Record<string, string>): { key: string; value: string }[] {
    return Object.entries(tags).map(([key, value]) => ({ key, value }));
  }
}
