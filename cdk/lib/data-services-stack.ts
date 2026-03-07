import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as elasticache from 'aws-cdk-lib/aws-elasticache';
import { LAB_CONFIG, commonTags } from './config';
import { DmzVpcStack } from './dmz-vpc-stack';

export interface DataServicesStackProps extends cdk.StackProps {
  dmzVpcStack: DmzVpcStack;
}

export class DataServicesStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: DataServicesStackProps) {
    super(scope, id, props);

    const tags = commonTags();
    const dmzVpc = props.dmzVpcStack;

    // Apply tags to the stack
    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // ========================================================================
    // Aurora MySQL Security Group
    // ========================================================================
    const auroraSg = new ec2.CfnSecurityGroup(this, 'AuroraSg', {
      groupDescription: 'Security group for Aurora MySQL cluster',
      vpcId: dmzVpc.vpcId,
      securityGroupIngress: [
        // Allow MySQL access from DMZ VPC
        {
          ipProtocol: 'tcp',
          fromPort: 3306,
          toPort: 3306,
          cidrIp: LAB_CONFIG.dmzVpc.cidr,
        },
        // Allow MySQL access from VPC01
        {
          ipProtocol: 'tcp',
          fromPort: 3306,
          toPort: 3306,
          cidrIp: LAB_CONFIG.vpc01.cidr,
        },
        // Allow MySQL access from VPC02
        {
          ipProtocol: 'tcp',
          fromPort: 3306,
          toPort: 3306,
          cidrIp: LAB_CONFIG.vpc02.cidr,
        },
      ],
      tags: [{ key: 'Name', value: 'aurora-mysql-sg' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Aurora MySQL Subnet Group
    // ========================================================================
    const auroraSubnetGroup = new rds.CfnDBSubnetGroup(this, 'AuroraSubnetGroup', {
      dbSubnetGroupDescription: 'Subnet group for Aurora MySQL cluster in DMZ data subnets',
      dbSubnetGroupName: 'lab-aurora-subnet-group',
      subnetIds: [
        dmzVpc.dataSubnetA.ref,
        dmzVpc.dataSubnetB.ref,
      ],
      tags: [{ key: 'Name', value: 'lab-aurora-subnet-group' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Aurora MySQL Cluster
    // ========================================================================
    const auroraCluster = new rds.CfnDBCluster(this, 'AuroraCluster', {
      engine: 'aurora-mysql',
      engineVersion: '8.0.mysql_aurora.3.07.1',
      dbClusterIdentifier: 'lab-aurora-cluster',
      masterUsername: 'admin',
      manageMasterUserPassword: true,
      dbSubnetGroupName: auroraSubnetGroup.ref,
      vpcSecurityGroupIds: [auroraSg.ref],
      storageEncrypted: true,
      deletionProtection: false,
      backupRetentionPeriod: 7,
      port: 3306,
      tags: [{ key: 'Name', value: 'lab-aurora-cluster' }, ...this.toTags(tags)],
    });

    // Aurora MySQL Instances
    const auroraInstanceA = new rds.CfnDBInstance(this, 'AuroraInstanceA', {
      dbInstanceClass: 'db.r6g.large',
      engine: 'aurora-mysql',
      dbClusterIdentifier: auroraCluster.ref,
      dbInstanceIdentifier: 'lab-aurora-instance-a',
      availabilityZone: `${this.region}a`,
      publiclyAccessible: false,
      tags: [{ key: 'Name', value: 'lab-aurora-instance-a' }, ...this.toTags(tags)],
    });

    const auroraInstanceB = new rds.CfnDBInstance(this, 'AuroraInstanceB', {
      dbInstanceClass: 'db.r6g.large',
      engine: 'aurora-mysql',
      dbClusterIdentifier: auroraCluster.ref,
      dbInstanceIdentifier: 'lab-aurora-instance-b',
      availabilityZone: `${this.region}b`,
      publiclyAccessible: false,
      tags: [{ key: 'Name', value: 'lab-aurora-instance-b' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Valkey (ElastiCache) Security Group
    // ========================================================================
    const valkeySg = new ec2.CfnSecurityGroup(this, 'ValkeySg', {
      groupDescription: 'Security group for Valkey (ElastiCache) replication group',
      vpcId: dmzVpc.vpcId,
      securityGroupIngress: [
        // Allow Valkey access from DMZ VPC
        {
          ipProtocol: 'tcp',
          fromPort: 6379,
          toPort: 6379,
          cidrIp: LAB_CONFIG.dmzVpc.cidr,
        },
        // Allow Valkey access from VPC01
        {
          ipProtocol: 'tcp',
          fromPort: 6379,
          toPort: 6379,
          cidrIp: LAB_CONFIG.vpc01.cidr,
        },
        // Allow Valkey access from VPC02
        {
          ipProtocol: 'tcp',
          fromPort: 6379,
          toPort: 6379,
          cidrIp: LAB_CONFIG.vpc02.cidr,
        },
      ],
      tags: [{ key: 'Name', value: 'valkey-sg' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Valkey (ElastiCache) Subnet Group
    // ========================================================================
    const valkeySubnetGroup = new elasticache.CfnSubnetGroup(this, 'ValkeySubnetGroup', {
      description: 'Subnet group for Valkey replication group in DMZ data subnets',
      cacheSubnetGroupName: 'lab-valkey-subnet-group',
      subnetIds: [
        dmzVpc.dataSubnetA.ref,
        dmzVpc.dataSubnetB.ref,
      ],
      tags: [{ key: 'Name', value: 'lab-valkey-subnet-group' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Valkey (ElastiCache) Replication Group
    // ========================================================================
    const valkeyReplicationGroup = new elasticache.CfnReplicationGroup(this, 'ValkeyReplicationGroup', {
      replicationGroupDescription: 'Valkey replication group for lab infrastructure',
      replicationGroupId: 'lab-valkey-rg',
      engine: 'valkey',
      cacheNodeType: 'cache.r6g.large',
      numCacheClusters: 2,
      automaticFailoverEnabled: true,
      multiAzEnabled: true,
      cacheSubnetGroupName: valkeySubnetGroup.ref,
      securityGroupIds: [valkeySg.ref],
      atRestEncryptionEnabled: true,
      transitEncryptionEnabled: true,
      port: 6379,
      tags: [{ key: 'Name', value: 'lab-valkey-rg' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Stack Outputs
    // ========================================================================
    new cdk.CfnOutput(this, 'AuroraClusterEndpoint', {
      value: auroraCluster.attrEndpointAddress,
      description: 'Aurora MySQL cluster writer endpoint',
      exportName: 'AuroraClusterEndpoint',
    });

    new cdk.CfnOutput(this, 'AuroraClusterReaderEndpoint', {
      value: auroraCluster.attrReadEndpointAddress,
      description: 'Aurora MySQL cluster reader endpoint',
      exportName: 'AuroraClusterReaderEndpoint',
    });

    new cdk.CfnOutput(this, 'AuroraClusterPort', {
      value: '3306',
      description: 'Aurora MySQL cluster port',
      exportName: 'AuroraClusterPort',
    });

    new cdk.CfnOutput(this, 'ValkeyPrimaryEndpoint', {
      value: valkeyReplicationGroup.attrPrimaryEndPointAddress,
      description: 'Valkey primary endpoint address',
      exportName: 'ValkeyPrimaryEndpoint',
    });

    new cdk.CfnOutput(this, 'ValkeyPrimaryEndpointPort', {
      value: valkeyReplicationGroup.attrPrimaryEndPointPort,
      description: 'Valkey primary endpoint port',
      exportName: 'ValkeyPrimaryEndpointPort',
    });

    new cdk.CfnOutput(this, 'ValkeyReaderEndpoint', {
      value: valkeyReplicationGroup.attrReaderEndPointAddress,
      description: 'Valkey reader endpoint address',
      exportName: 'ValkeyReaderEndpoint',
    });
  }

  private toTags(tags: Record<string, string>): { key: string; value: string }[] {
    return Object.entries(tags).map(([key, value]) => ({ key, value }));
  }
}
