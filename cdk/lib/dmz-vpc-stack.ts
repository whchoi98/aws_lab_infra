import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as elbv2_targets from 'aws-cdk-lib/aws-elasticloadbalancingv2-targets';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as networkfirewall from 'aws-cdk-lib/aws-networkfirewall';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cr from 'aws-cdk-lib/custom-resources';
import * as logs from 'aws-cdk-lib/aws-logs';
import { LAB_CONFIG, commonTags } from './config';

export class DmzVpcStack extends cdk.Stack {
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

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const config = LAB_CONFIG.dmzVpc;
    const tags = commonTags();
    const azA = `${this.region}a`;
    const azB = `${this.region}b`;

    // ========================================================================
    // VPC
    // ========================================================================
    this.vpc = new ec2.CfnVPC(this, 'DmzVpc', {
      cidrBlock: config.cidr,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      tags: [{ key: 'Name', value: 'dmz-vpc' }, ...this.toTags(tags)],
    });
    this.vpcId = this.vpc.ref;

    // ========================================================================
    // Internet Gateway
    // ========================================================================
    const igw = new ec2.CfnInternetGateway(this, 'DmzIgw', {
      tags: [{ key: 'Name', value: 'dmz-igw' }, ...this.toTags(tags)],
    });
    new ec2.CfnVPCGatewayAttachment(this, 'DmzIgwAttach', {
      vpcId: this.vpcId,
      internetGatewayId: igw.ref,
    });

    // ========================================================================
    // Subnets
    // ========================================================================
    // Public Subnets
    this.publicSubnetA = this.createSubnet('DmzPublicSubnetA', config.subnets.public.cidrA, azA, 'dmz-public-a');
    this.publicSubnetB = this.createSubnet('DmzPublicSubnetB', config.subnets.public.cidrB, azB, 'dmz-public-b');

    // Private Subnets
    this.privateSubnetA = this.createSubnet('DmzPrivateSubnetA', config.subnets.private.cidrA, azA, 'dmz-private-a');
    this.privateSubnetB = this.createSubnet('DmzPrivateSubnetB', config.subnets.private.cidrB, azB, 'dmz-private-b');

    // Data Subnets
    this.dataSubnetA = this.createSubnet('DmzDataSubnetA', config.subnets.data.cidrA, azA, 'dmz-data-a');
    this.dataSubnetB = this.createSubnet('DmzDataSubnetB', config.subnets.data.cidrB, azB, 'dmz-data-b');

    // Attach Subnets (for TGW)
    this.attachSubnetA = this.createSubnet('DmzAttachSubnetA', config.subnets.attach.cidrA, azA, 'dmz-attach-a');
    this.attachSubnetB = this.createSubnet('DmzAttachSubnetB', config.subnets.attach.cidrB, azB, 'dmz-attach-b');

    // Firewall Subnets
    const fwSubnetA = this.createSubnet('DmzFwSubnetA', config.subnets.fw.cidrA, azA, 'dmz-fw-a');
    const fwSubnetB = this.createSubnet('DmzFwSubnetB', config.subnets.fw.cidrB, azB, 'dmz-fw-b');

    // NAT Gateway Subnets
    const natgwSubnetA = this.createSubnet('DmzNatgwSubnetA', config.subnets.natgw.cidrA, azA, 'dmz-natgw-a');
    const natgwSubnetB = this.createSubnet('DmzNatgwSubnetB', config.subnets.natgw.cidrB, azB, 'dmz-natgw-b');

    // ========================================================================
    // Elastic IPs and NAT Gateways
    // ========================================================================
    const eipA = new ec2.CfnEIP(this, 'DmzEipA', {
      domain: 'vpc',
      tags: [{ key: 'Name', value: 'dmz-natgw-eip-a' }, ...this.toTags(tags)],
    });
    const eipB = new ec2.CfnEIP(this, 'DmzEipB', {
      domain: 'vpc',
      tags: [{ key: 'Name', value: 'dmz-natgw-eip-b' }, ...this.toTags(tags)],
    });

    const natGwA = new ec2.CfnNatGateway(this, 'DmzNatGwA', {
      subnetId: natgwSubnetA.ref,
      allocationId: eipA.attrAllocationId,
      tags: [{ key: 'Name', value: 'dmz-natgw-a' }, ...this.toTags(tags)],
    });
    const natGwB = new ec2.CfnNatGateway(this, 'DmzNatGwB', {
      subnetId: natgwSubnetB.ref,
      allocationId: eipB.attrAllocationId,
      tags: [{ key: 'Name', value: 'dmz-natgw-b' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // AWS Network Firewall
    // ========================================================================
    // Stateless rule group - forward all traffic to stateful engine
    const statelessRuleGroup = new networkfirewall.CfnRuleGroup(this, 'DmzNfwStatelessRg', {
      ruleGroupName: 'dmz-nfw-stateless-rg',
      type: 'STATELESS',
      capacity: 100,
      ruleGroup: {
        rulesSource: {
          statelessRulesAndCustomActions: {
            statelessRules: [
              {
                priority: 1,
                ruleDefinition: {
                  matchAttributes: {
                    protocols: [6],   // TCP
                    sources: [{ addressDefinition: '0.0.0.0/0' }],
                    destinations: [{ addressDefinition: '0.0.0.0/0' }],
                  },
                  actions: ['aws:forward_to_sfe'],
                },
              },
              {
                priority: 2,
                ruleDefinition: {
                  matchAttributes: {
                    protocols: [17],  // UDP
                    sources: [{ addressDefinition: '0.0.0.0/0' }],
                    destinations: [{ addressDefinition: '0.0.0.0/0' }],
                  },
                  actions: ['aws:forward_to_sfe'],
                },
              },
              {
                priority: 10,
                ruleDefinition: {
                  matchAttributes: {
                    protocols: [1],   // ICMP
                    sources: [{ addressDefinition: '0.0.0.0/0' }],
                    destinations: [{ addressDefinition: '0.0.0.0/0' }],
                  },
                  actions: ['aws:forward_to_sfe'],
                },
              },
            ],
          },
        },
      },
      tags: [{ key: 'Name', value: 'dmz-nfw-stateless-rg' }, ...this.toTags(tags)],
    });

    // Stateful rule group - pass TCP/UDP/ICMP for HOME_NET
    const statefulRuleGroup = new networkfirewall.CfnRuleGroup(this, 'DmzNfwStatefulRg', {
      ruleGroupName: 'dmz-nfw-stateful-rg',
      type: 'STATEFUL',
      capacity: 100,
      ruleGroup: {
        ruleVariables: {
          ipSets: {
            HOME_NET: {
              definition: [config.cidr, LAB_CONFIG.vpc01.cidr, LAB_CONFIG.vpc02.cidr],
            },
          },
        },
        rulesSource: {
          statefulRules: [
            {
              action: 'PASS',
              header: {
                protocol: 'TCP',
                source: '$HOME_NET',
                sourcePort: 'ANY',
                destination: '$HOME_NET',
                destinationPort: 'ANY',
                direction: 'ANY',
              },
              ruleOptions: [{ keyword: 'sid', settings: ['1'] }],
            },
            {
              action: 'PASS',
              header: {
                protocol: 'UDP',
                source: '$HOME_NET',
                sourcePort: 'ANY',
                destination: '$HOME_NET',
                destinationPort: 'ANY',
                direction: 'ANY',
              },
              ruleOptions: [{ keyword: 'sid', settings: ['2'] }],
            },
            {
              action: 'PASS',
              header: {
                protocol: 'ICMP',
                source: '$HOME_NET',
                sourcePort: 'ANY',
                destination: '$HOME_NET',
                destinationPort: 'ANY',
                direction: 'ANY',
              },
              ruleOptions: [{ keyword: 'sid', settings: ['3'] }],
            },
            {
              action: 'PASS',
              header: {
                protocol: 'TCP',
                source: '$HOME_NET',
                sourcePort: 'ANY',
                destination: 'ANY',
                destinationPort: 'ANY',
                direction: 'ANY',
              },
              ruleOptions: [{ keyword: 'sid', settings: ['4'] }],
            },
            {
              action: 'PASS',
              header: {
                protocol: 'UDP',
                source: '$HOME_NET',
                sourcePort: 'ANY',
                destination: 'ANY',
                destinationPort: 'ANY',
                direction: 'ANY',
              },
              ruleOptions: [{ keyword: 'sid', settings: ['5'] }],
            },
            {
              action: 'PASS',
              header: {
                protocol: 'ICMP',
                source: '$HOME_NET',
                sourcePort: 'ANY',
                destination: 'ANY',
                destinationPort: 'ANY',
                direction: 'ANY',
              },
              ruleOptions: [{ keyword: 'sid', settings: ['6'] }],
            },
          ],
        },
      },
      tags: [{ key: 'Name', value: 'dmz-nfw-stateful-rg' }, ...this.toTags(tags)],
    });

    // Firewall Policy
    const firewallPolicy = new networkfirewall.CfnFirewallPolicy(this, 'DmzNfwPolicy', {
      firewallPolicyName: 'dmz-nfw-policy',
      firewallPolicy: {
        statelessDefaultActions: ['aws:forward_to_sfe'],
        statelessFragmentDefaultActions: ['aws:forward_to_sfe'],
        statelessRuleGroupReferences: [
          {
            resourceArn: statelessRuleGroup.attrRuleGroupArn,
            priority: 1,
          },
        ],
        statefulRuleGroupReferences: [
          {
            resourceArn: statefulRuleGroup.attrRuleGroupArn,
          },
        ],
      },
      tags: [{ key: 'Name', value: 'dmz-nfw-policy' }, ...this.toTags(tags)],
    });

    // Network Firewall
    const firewall = new networkfirewall.CfnFirewall(this, 'DmzNfw', {
      firewallName: 'dmz-nfw',
      firewallPolicyArn: firewallPolicy.attrFirewallPolicyArn,
      vpcId: this.vpcId,
      subnetMappings: [
        { subnetId: fwSubnetA.ref },
        { subnetId: fwSubnetB.ref },
      ],
      tags: [{ key: 'Name', value: 'dmz-nfw' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Custom Resource Lambda to extract NFW Endpoint IDs
    // ========================================================================
    const nfwEndpointRole = new iam.Role(this, 'NfwEndpointLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        NfwDescribe: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ['network-firewall:DescribeFirewall'],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    const nfwEndpointFn = new lambda.Function(this, 'NfwEndpointFn', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.handler',
      role: nfwEndpointRole,
      timeout: cdk.Duration.seconds(60),
      code: lambda.Code.fromInline(`
import boto3
import cfnresponse
import json

def handler(event, context):
    try:
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return

        firewall_name = event['ResourceProperties']['FirewallName']
        az_a = event['ResourceProperties']['AzA']
        az_b = event['ResourceProperties']['AzB']

        client = boto3.client('network-firewall')
        response = client.describe_firewall(FirewallName=firewall_name)

        sync_states = response['FirewallStatus']['SyncStates']
        endpoint_a = sync_states[az_a]['Attachment']['EndpointId']
        endpoint_b = sync_states[az_b]['Attachment']['EndpointId']

        cfnresponse.send(event, context, cfnresponse.SUCCESS, {
            'EndpointIdA': endpoint_a,
            'EndpointIdB': endpoint_b,
        })
    except Exception as e:
        print(f'Error: {e}')
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': str(e)})
`),
    });

    const nfwEndpoints = new cdk.CustomResource(this, 'NfwEndpoints', {
      serviceToken: nfwEndpointFn.functionArn,
      properties: {
        FirewallName: 'dmz-nfw',
        AzA: azA,
        AzB: azB,
      },
    });
    nfwEndpoints.node.addDependency(firewall);

    const nfwEndpointIdA = nfwEndpoints.getAttString('EndpointIdA');
    const nfwEndpointIdB = nfwEndpoints.getAttString('EndpointIdB');

    // ========================================================================
    // Route Tables
    // ========================================================================

    // --- IGW Ingress Route Table (Edge Association) ---
    const igwRouteTable = new ec2.CfnRouteTable(this, 'DmzIgwRt', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-igw-rt' }, ...this.toTags(tags)],
    });
    new ec2.CfnGatewayRouteTableAssociation(this, 'DmzIgwRtAssoc', {
      gatewayId: igw.ref,
      routeTableId: igwRouteTable.ref,
    });
    // IGW ingress routes to NFW endpoints for public subnets
    new ec2.CfnRoute(this, 'IgwToNfwA', {
      routeTableId: igwRouteTable.ref,
      destinationCidrBlock: config.subnets.public.cidrA,
      vpcEndpointId: nfwEndpointIdA,
    });
    new ec2.CfnRoute(this, 'IgwToNfwB', {
      routeTableId: igwRouteTable.ref,
      destinationCidrBlock: config.subnets.public.cidrB,
      vpcEndpointId: nfwEndpointIdB,
    });

    // --- Public Route Tables ---
    const publicRtA = new ec2.CfnRouteTable(this, 'DmzPublicRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-public-rt-a' }, ...this.toTags(tags)],
    });
    const publicRtB = new ec2.CfnRouteTable(this, 'DmzPublicRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-public-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzPublicRtAssocA', {
      subnetId: this.publicSubnetA.ref,
      routeTableId: publicRtA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzPublicRtAssocB', {
      subnetId: this.publicSubnetB.ref,
      routeTableId: publicRtB.ref,
    });
    // Public subnets route to NFW
    new ec2.CfnRoute(this, 'PublicToNfwA', {
      routeTableId: publicRtA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      vpcEndpointId: nfwEndpointIdA,
    });
    new ec2.CfnRoute(this, 'PublicToNfwB', {
      routeTableId: publicRtB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      vpcEndpointId: nfwEndpointIdB,
    });

    // --- Firewall Route Tables ---
    const fwRtA = new ec2.CfnRouteTable(this, 'DmzFwRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-fw-rt-a' }, ...this.toTags(tags)],
    });
    const fwRtB = new ec2.CfnRouteTable(this, 'DmzFwRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-fw-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzFwRtAssocA', {
      subnetId: fwSubnetA.ref,
      routeTableId: fwRtA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzFwRtAssocB', {
      subnetId: fwSubnetB.ref,
      routeTableId: fwRtB.ref,
    });
    // FW subnets route to IGW
    new ec2.CfnRoute(this, 'FwToIgwA', {
      routeTableId: fwRtA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      gatewayId: igw.ref,
    });
    new ec2.CfnRoute(this, 'FwToIgwB', {
      routeTableId: fwRtB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      gatewayId: igw.ref,
    });

    // --- NATGW Route Tables ---
    const natgwRtA = new ec2.CfnRouteTable(this, 'DmzNatgwRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-natgw-rt-a' }, ...this.toTags(tags)],
    });
    const natgwRtB = new ec2.CfnRouteTable(this, 'DmzNatgwRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-natgw-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzNatgwRtAssocA', {
      subnetId: natgwSubnetA.ref,
      routeTableId: natgwRtA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzNatgwRtAssocB', {
      subnetId: natgwSubnetB.ref,
      routeTableId: natgwRtB.ref,
    });
    // NATGW subnets route to IGW
    new ec2.CfnRoute(this, 'NatgwToIgwA', {
      routeTableId: natgwRtA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      gatewayId: igw.ref,
    });
    new ec2.CfnRoute(this, 'NatgwToIgwB', {
      routeTableId: natgwRtB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      gatewayId: igw.ref,
    });

    // --- Private Route Tables ---
    this.privateRouteTableA = new ec2.CfnRouteTable(this, 'DmzPrivateRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-private-rt-a' }, ...this.toTags(tags)],
    });
    this.privateRouteTableB = new ec2.CfnRouteTable(this, 'DmzPrivateRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-private-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzPrivateRtAssocA', {
      subnetId: this.privateSubnetA.ref,
      routeTableId: this.privateRouteTableA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzPrivateRtAssocB', {
      subnetId: this.privateSubnetB.ref,
      routeTableId: this.privateRouteTableB.ref,
    });
    // Private subnets route to NAT GW
    new ec2.CfnRoute(this, 'PrivateToNatA', {
      routeTableId: this.privateRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      natGatewayId: natGwA.ref,
    });
    new ec2.CfnRoute(this, 'PrivateToNatB', {
      routeTableId: this.privateRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      natGatewayId: natGwB.ref,
    });

    // --- Data Route Tables ---
    this.dataRouteTableA = new ec2.CfnRouteTable(this, 'DmzDataRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-data-rt-a' }, ...this.toTags(tags)],
    });
    this.dataRouteTableB = new ec2.CfnRouteTable(this, 'DmzDataRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-data-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzDataRtAssocA', {
      subnetId: this.dataSubnetA.ref,
      routeTableId: this.dataRouteTableA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzDataRtAssocB', {
      subnetId: this.dataSubnetB.ref,
      routeTableId: this.dataRouteTableB.ref,
    });
    // Data subnets route to NAT GW
    new ec2.CfnRoute(this, 'DataToNatA', {
      routeTableId: this.dataRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      natGatewayId: natGwA.ref,
    });
    new ec2.CfnRoute(this, 'DataToNatB', {
      routeTableId: this.dataRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      natGatewayId: natGwB.ref,
    });

    // --- Attach Route Tables ---
    this.attachRouteTableA = new ec2.CfnRouteTable(this, 'DmzAttachRtA', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-attach-rt-a' }, ...this.toTags(tags)],
    });
    this.attachRouteTableB = new ec2.CfnRouteTable(this, 'DmzAttachRtB', {
      vpcId: this.vpcId,
      tags: [{ key: 'Name', value: 'dmz-attach-rt-b' }, ...this.toTags(tags)],
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzAttachRtAssocA', {
      subnetId: this.attachSubnetA.ref,
      routeTableId: this.attachRouteTableA.ref,
    });
    new ec2.CfnSubnetRouteTableAssociation(this, 'DmzAttachRtAssocB', {
      subnetId: this.attachSubnetB.ref,
      routeTableId: this.attachRouteTableB.ref,
    });

    // ========================================================================
    // SSM VPC Endpoints
    // ========================================================================
    const ssmSg = new ec2.CfnSecurityGroup(this, 'DmzSsmEndpointSg', {
      groupDescription: 'Security group for SSM VPC endpoints in DMZ VPC',
      vpcId: this.vpcId,
      securityGroupIngress: [
        { ipProtocol: 'tcp', fromPort: 443, toPort: 443, cidrIp: config.cidr },
      ],
      tags: [{ key: 'Name', value: 'dmz-ssm-endpoint-sg' }, ...this.toTags(tags)],
    });

    const endpointSubnets = [this.privateSubnetA.ref, this.privateSubnetB.ref];

    new ec2.CfnVPCEndpoint(this, 'DmzSsmEndpoint', {
      vpcId: this.vpcId,
      serviceName: `com.amazonaws.${this.region}.ssm`,
      vpcEndpointType: 'Interface',
      privateDnsEnabled: true,
      subnetIds: endpointSubnets,
      securityGroupIds: [ssmSg.ref],
    });
    new ec2.CfnVPCEndpoint(this, 'DmzSsmMessagesEndpoint', {
      vpcId: this.vpcId,
      serviceName: `com.amazonaws.${this.region}.ssmmessages`,
      vpcEndpointType: 'Interface',
      privateDnsEnabled: true,
      subnetIds: endpointSubnets,
      securityGroupIds: [ssmSg.ref],
    });
    new ec2.CfnVPCEndpoint(this, 'DmzEc2MessagesEndpoint', {
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
    const ec2Role = new iam.Role(this, 'DmzEc2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    const instanceProfile = new iam.CfnInstanceProfile(this, 'DmzInstanceProfile', {
      roles: [ec2Role.roleName],
    });

    const ec2Sg = new ec2.CfnSecurityGroup(this, 'DmzEc2Sg', {
      groupDescription: 'Security group for EC2 instances in DMZ VPC',
      vpcId: this.vpcId,
      securityGroupIngress: [
        { ipProtocol: 'tcp', fromPort: 80, toPort: 80, cidrIp: config.cidr },
        { ipProtocol: 'tcp', fromPort: 443, toPort: 443, cidrIp: config.cidr },
        { ipProtocol: 'icmp', fromPort: -1, toPort: -1, cidrIp: '10.0.0.0/8' },
      ],
      tags: [{ key: 'Name', value: 'dmz-ec2-sg' }, ...this.toTags(tags)],
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
      'echo "<html><body><h1>DMZ Instance</h1><p>Instance: $INSTANCE_ID</p><p>AZ: $AZ</p></body></html>" > /var/www/html/index.html',
    );

    const instanceA = new ec2.CfnInstance(this, 'DmzInstanceA', {
      instanceType: 't4g.large',
      imageId: amznLinux2023.getImage(this).imageId,
      subnetId: this.privateSubnetA.ref,
      securityGroupIds: [ec2Sg.ref],
      iamInstanceProfile: instanceProfile.ref,
      userData: cdk.Fn.base64(userData.render()),
      tags: [{ key: 'Name', value: 'dmz-instance-a' }, ...this.toTags(tags)],
    });

    const instanceB = new ec2.CfnInstance(this, 'DmzInstanceB', {
      instanceType: 't4g.large',
      imageId: amznLinux2023.getImage(this).imageId,
      subnetId: this.privateSubnetB.ref,
      securityGroupIds: [ec2Sg.ref],
      iamInstanceProfile: instanceProfile.ref,
      userData: cdk.Fn.base64(userData.render()),
      tags: [{ key: 'Name', value: 'dmz-instance-b' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // Application Load Balancer
    // ========================================================================
    const albSg = new ec2.CfnSecurityGroup(this, 'DmzAlbSg', {
      groupDescription: 'Security group for ALB in DMZ VPC',
      vpcId: this.vpcId,
      securityGroupIngress: [
        { ipProtocol: 'tcp', fromPort: 80, toPort: 80, cidrIp: '0.0.0.0/0' },
        { ipProtocol: 'tcp', fromPort: 443, toPort: 443, cidrIp: '0.0.0.0/0' },
      ],
      tags: [{ key: 'Name', value: 'dmz-alb-sg' }, ...this.toTags(tags)],
    });

    const alb = new elbv2.CfnLoadBalancer(this, 'DmzAlb', {
      name: 'dmz-alb',
      scheme: 'internet-facing',
      type: 'application',
      subnets: [this.publicSubnetA.ref, this.publicSubnetB.ref],
      securityGroups: [albSg.ref],
      tags: [{ key: 'Name', value: 'dmz-alb' }, ...this.toTags(tags)],
    });

    const targetGroup = new elbv2.CfnTargetGroup(this, 'DmzAlbTg', {
      name: 'dmz-alb-tg',
      port: 80,
      protocol: 'HTTP',
      vpcId: this.vpcId,
      targetType: 'instance',
      healthCheckPath: '/',
      healthCheckProtocol: 'HTTP',
      targets: [
        { id: instanceA.ref, port: 80 },
        { id: instanceB.ref, port: 80 },
      ],
      tags: [{ key: 'Name', value: 'dmz-alb-tg' }, ...this.toTags(tags)],
    });

    const customSecretValue = 'LabSecretHeader2024';

    new elbv2.CfnListener(this, 'DmzAlbListener', {
      loadBalancerArn: alb.ref,
      port: 80,
      protocol: 'HTTP',
      defaultActions: [
        {
          type: 'fixed-response',
          fixedResponseConfig: {
            statusCode: '403',
            contentType: 'text/plain',
            messageBody: 'Access Denied',
          },
        },
      ],
    });

    new elbv2.CfnListenerRule(this, 'DmzAlbListenerRule', {
      listenerArn: cdk.Fn.ref('DmzAlbListener'),
      priority: 1,
      conditions: [
        {
          field: 'http-header',
          httpHeaderConfig: {
            httpHeaderName: 'X-Custom-Secret',
            values: [customSecretValue],
          },
        },
      ],
      actions: [
        {
          type: 'forward',
          targetGroupArn: targetGroup.ref,
        },
      ],
    });

    // ========================================================================
    // CloudFront Distribution
    // ========================================================================
    const distribution = new cloudfront.Distribution(this, 'DmzCloudFront', {
      defaultBehavior: {
        origin: new origins.HttpOrigin(cdk.Fn.getAtt(alb.logicalId, 'DNSName').toString(), {
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
          customHeaders: {
            'X-Custom-Secret': customSecretValue,
          },
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
      },
      comment: 'DMZ VPC CloudFront Distribution',
    });

    // ========================================================================
    // Stack Outputs
    // ========================================================================
    new cdk.CfnOutput(this, 'DmzVpcId', {
      value: this.vpcId,
      exportName: 'DmzVpcId',
    });
    new cdk.CfnOutput(this, 'DmzPublicSubnetAId', {
      value: this.publicSubnetA.ref,
      exportName: 'DmzPublicSubnetAId',
    });
    new cdk.CfnOutput(this, 'DmzPublicSubnetBId', {
      value: this.publicSubnetB.ref,
      exportName: 'DmzPublicSubnetBId',
    });
    new cdk.CfnOutput(this, 'DmzPrivateSubnetAId', {
      value: this.privateSubnetA.ref,
      exportName: 'DmzPrivateSubnetAId',
    });
    new cdk.CfnOutput(this, 'DmzPrivateSubnetBId', {
      value: this.privateSubnetB.ref,
      exportName: 'DmzPrivateSubnetBId',
    });
    new cdk.CfnOutput(this, 'DmzDataSubnetAId', {
      value: this.dataSubnetA.ref,
      exportName: 'DmzDataSubnetAId',
    });
    new cdk.CfnOutput(this, 'DmzDataSubnetBId', {
      value: this.dataSubnetB.ref,
      exportName: 'DmzDataSubnetBId',
    });
    new cdk.CfnOutput(this, 'DmzAttachSubnetAId', {
      value: this.attachSubnetA.ref,
      exportName: 'DmzAttachSubnetAId',
    });
    new cdk.CfnOutput(this, 'DmzAttachSubnetBId', {
      value: this.attachSubnetB.ref,
      exportName: 'DmzAttachSubnetBId',
    });
    new cdk.CfnOutput(this, 'AlbDnsName', {
      value: cdk.Fn.getAtt(alb.logicalId, 'DNSName').toString(),
      exportName: 'DmzAlbDnsName',
    });
    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: distribution.distributionDomainName,
      exportName: 'DmzCloudFrontDomainName',
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
