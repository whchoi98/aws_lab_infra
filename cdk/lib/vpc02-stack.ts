import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { LAB_CONFIG, commonTags } from './config';

export class Vpc02Stack extends cdk.Stack {
  public readonly vpc: ec2.CfnVPC;
  public readonly vpcId: string;
  public readonly publicSubnetA: ec2.CfnSubnet;
  public readonly publicSubnetB: ec2.CfnSubnet;
  public readonly privateSubnetA: ec2.CfnSubnet;
  public readonly privateSubnetB: ec2.CfnSubnet;
  public readonly dataSubnetA: ec2.CfnSubnet;
  public readonly dataSubnetB: ec2.CfnSubnet;
  public readonly attachSubnetA: ec2.CfnSubnet;
  public readonly attachSubnetB: ec2.CfnSubnet;
  public readonly privateRouteTableA: ec2.CfnRouteTable;
  public readonly privateRouteTableB: ec2.CfnRouteTable;
  public readonly dataRouteTableA: ec2.CfnRouteTable;
  public readonly dataRouteTableB: ec2.CfnRouteTable;
  public readonly attachRouteTableA: ec2.CfnRouteTable;
  public readonly attachRouteTableB: ec2.CfnRouteTable;
  public readonly publicRouteTableA: ec2.CfnRouteTable;
  public readonly publicRouteTableB: ec2.CfnRouteTable;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const config = LAB_CONFIG.vpc02;
    const tags = commonTags();
    const azA = `${this.region}a`;
    const azB = `${this.region}b`;

    // ========================================================================
    // VPC
    // ========================================================================
    this.vpc = new ec2.CfnVPC(this, 'Vpc02', {
      cidrBlock: config.cidr,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      tags: [{ key: 'Name', value: 'vpc-02' }, ...this.toTags(tags)],
    });
    this.vpcId = this.vpc.ref;

    // ========================================================================
    // Subnets
    // ========================================================================
    this.publicSubnetA = this.createSubnet('Vpc02PublicSubnetA', config.subnets.public.cidrA, azA, 'vpc02-public-a');
    this.publicSubnetB = this.createSubnet('Vpc02PublicSubnetB', config.subnets.public.cidrB, azB, 'vpc02-public-b');

    this.privateSubnetA = this.createSubnet('Vpc02PrivateSubnetA', config.subnets.private.cidrA, azA, 'vpc02-private-a');
    this.privateSubnetB = this.createSubnet('Vpc02PrivateSubnetB', config.subnets.private.cidrB, azB, 'vpc02-private-b');

    this.dataSubnetA = this.createSubnet('Vpc02DataSubnetA', config.subnets.data.cidrA, azA, 'vpc02-data-a');
    this.dataSubnetB = this.createSubnet('Vpc02DataSubnetB', config.subnets.data.cidrB, azB, 'vpc02-data-b');

    this.attachSubnetA = this.createSubnet('Vpc02AttachSubnetA', config.subnets.attach.cidrA, azA, 'vpc02-attach-a');
    this.attachSubnetB = this.createSubnet('Vpc02AttachSubnetB', config.subnets.attach.cidrB, azB, 'vpc02-attach-b');

    // ========================================================================
    // Route Tables (no default route - TGW stack will add routes)
    // ========================================================================
    this.publicRouteTableA = new ec2.CfnRouteTable(this, 'Vpc02PublicRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-public-rt-a' }, ...this.toTags(tags)],
    });
    this.publicRouteTableB = new ec2.CfnRouteTable(this, 'Vpc02PublicRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-public-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02PublicRtAssocA', {
      subnetId: this.publicSubnetA.ref,
      routeTableId: this.publicRouteTableA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02PublicRtAssocB', {
      subnetId: this.publicSubnetB.ref,
      routeTableId: this.publicRouteTableB.ref,
    });

    this.privateRouteTableA = new ec2.CfnRouteTable(this, 'Vpc02PrivateRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-private-rt-a' }, ...this.toTags(tags)],
    });
    this.privateRouteTableB = new ec2.CfnRouteTable(this, 'Vpc02PrivateRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-private-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02PrivateRtAssocA', {
      subnetId: this.privateSubnetA.ref,
      routeTableId: this.privateRouteTableA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02PrivateRtAssocB', {
      subnetId: this.privateSubnetB.ref,
      routeTableId: this.privateRouteTableB.ref,
    });

    this.dataRouteTableA = new ec2.CfnRouteTable(this, 'Vpc02DataRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-data-rt-a' }, ...this.toTags(tags)],
    });
    this.dataRouteTableB = new ec2.CfnRouteTable(this, 'Vpc02DataRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-data-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02DataRtAssocA', {
      subnetId: this.dataSubnetA.ref,
      routeTableId: this.dataRouteTableA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02DataRtAssocB', {
      subnetId: this.dataSubnetB.ref,
      routeTableId: this.dataRouteTableB.ref,
    });

    this.attachRouteTableA = new ec2.CfnRouteTable(this, 'Vpc02AttachRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-attach-rt-a' }, ...this.toTags(tags)],
    });
    this.attachRouteTableB = new ec2.CfnRouteTable(this, 'Vpc02AttachRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'vpc02-attach-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02AttachRtAssocA', {
      subnetId: this.attachSubnetA.ref,
      routeTableId: this.attachRouteTableA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'Vpc02AttachRtAssocB', {
      subnetId: this.attachSubnetB.ref,
      routeTableId: this.attachRouteTableB.ref,
    });

    // ========================================================================
    // SSM VPC Endpoints
    // ========================================================================
    const ssmSg = new ec2.CfnSecurityGroup(this, 'Vpc02SsmEndpointSg', {
      groupDescription: 'Security group for SSM VPC endpoints in VPC02',
      vpcId: this.vpcId,
      securityGroupIngress: [
        { ipProtocol: 'tcp', fromPort: 443, toPort: 443, cidrIp: config.cidr },
      ],
      tags: [{ key: 'Name', value: 'vpc02-ssm-endpoint-sg' }, ...this.toTags(tags)],
    });

    const endpointSubnets = [this.privateSubnetA.ref, this.privateSubnetB.ref];

    new ec2.CfnVPCEndpoint(this, 'Vpc02SsmEndpoint', {
      vpcId: this.vpcId,
      serviceName: `com.amazonaws.${this.region}.ssm`,
      vpcEndpointType: 'Interface',
      privateDnsEnabled: true,
      subnetIds: endpointSubnets,
      securityGroupIds: [ssmSg.ref],
    });
    new ec2.CfnVPCEndpoint(this, 'Vpc02SsmMessagesEndpoint', {
      vpcId: this.vpcId,
      serviceName: `com.amazonaws.${this.region}.ssmmessages`,
      vpcEndpointType: 'Interface',
      privateDnsEnabled: true,
      subnetIds: endpointSubnets,
      securityGroupIds: [ssmSg.ref],
    });
    new ec2.CfnVPCEndpoint(this, 'Vpc02Ec2MessagesEndpoint', {
      vpcId: this.vpcId,
      serviceName: `com.amazonaws.${this.region}.ec2messages`,
      vpcEndpointType: 'Interface',
      privateDnsEnabled: true,
      subnetIds: endpointSubnets,
      securityGroupIds: [ssmSg.ref],
    });

    // ========================================================================
    // EC2 Instances
    // ========================================================================
    const ec2Role = new iam.Role(this, 'Vpc02Ec2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    const instanceProfile = new iam.CfnInstanceProfile(this, 'Vpc02InstanceProfile', {
      roles: [ec2Role.roleName],
    });

    const ec2Sg = new ec2.CfnSecurityGroup(this, 'Vpc02Ec2Sg', {
      groupDescription: 'Security group for EC2 instances in VPC02',
      vpcId: this.vpcId,
      securityGroupIngress: [
        { ipProtocol: 'tcp', fromPort: 80, toPort: 80, cidrIp: '10.0.0.0/8' },
        { ipProtocol: 'tcp', fromPort: 443, toPort: 443, cidrIp: '10.0.0.0/8' },
        { ipProtocol: 'icmp', fromPort: -1, toPort: -1, cidrIp: '10.0.0.0/8' },
      ],
      tags: [{ key: 'Name', value: 'vpc02-ec2-sg' }, ...this.toTags(tags)],
    });

    const amznLinux2023 = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'dnf install -y httpd',
      'systemctl enable httpd',
      'systemctl start httpd',
      'TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")',
      'INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)',
      'AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)',
      'echo "<html><body><h1>VPC02 Instance</h1><p>Instance: $INSTANCE_ID</p><p>AZ: $AZ</p></body></html>" > /var/www/html/index.html',
    );

    new ec2.CfnInstance(this, 'Vpc02InstanceA', {
      instanceType: 't4g.micro',
      imageId: amznLinux2023.getImage(this).imageId,
      subnetId: this.privateSubnetA.ref,
      securityGroupIds: [ec2Sg.ref],
      iamInstanceProfile: instanceProfile.ref,
      userData: cdk.Fn.base64(userData.render()),
      tags: [{ key: 'Name', value: 'vpc02-instance-a' }, ...this.toTags(tags)],
    });

    new ec2.CfnInstance(this, 'Vpc02InstanceB', {
      instanceType: 't4g.micro',
      imageId: amznLinux2023.getImage(this).imageId,
      subnetId: this.privateSubnetB.ref,
      securityGroupIds: [ec2Sg.ref],
      iamInstanceProfile: instanceProfile.ref,
      userData: cdk.Fn.base64(userData.render()),
      tags: [{ key: 'Name', value: 'vpc02-instance-b' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Stack Outputs
    // ========================================================================
    new cdk.CfnOutput(this, 'Vpc02Id', {
      value: this.vpcId,
      exportName: 'Vpc02Id',
    });
    new cdk.CfnOutput(this, 'Vpc02PrivateSubnetAId', {
      value: this.privateSubnetA.ref,
      exportName: 'Vpc02PrivateSubnetAId',
    });
    new cdk.CfnOutput(this, 'Vpc02PrivateSubnetBId', {
      value: this.privateSubnetB.ref,
      exportName: 'Vpc02PrivateSubnetBId',
    });
    new cdk.CfnOutput(this, 'Vpc02DataSubnetAId', {
      value: this.dataSubnetA.ref,
      exportName: 'Vpc02DataSubnetAId',
    });
    new cdk.CfnOutput(this, 'Vpc02DataSubnetBId', {
      value: this.dataSubnetB.ref,
      exportName: 'Vpc02DataSubnetBId',
    });
    new cdk.CfnOutput(this, 'Vpc02AttachSubnetAId', {
      value: this.attachSubnetA.ref,
      exportName: 'Vpc02AttachSubnetAId',
    });
    new cdk.CfnOutput(this, 'Vpc02AttachSubnetBId', {
      value: this.attachSubnetB.ref,
      exportName: 'Vpc02AttachSubnetBId',
    });
  }

  private createSubnet(id: string, cidrBlock: string, az: string, name: string): ec2.CfnSubnet {
    const tags = commonTags();
    return new ec2.CfnSubnet(this, id, {
      vpcId: this.vpcId,
      cidrBlock,
      availabilityZone: az,
      mapPublicIpOnLaunch: false,
      tags: [{ key: 'Name', value: name }, ...this.toTags(tags)],
    });
  }

  private toTags(tags: Record<string, string>): { key: string; value: string }[] {
    return Object.entries(tags).map(([key, value]) => ({ key, value }));
  }
}
