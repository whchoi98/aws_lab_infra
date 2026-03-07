import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { LAB_CONFIG, commonTags } from './config';
import { DmzVpcStack } from './dmz-vpc-stack';
import { Vpc01Stack } from './vpc01-stack';
import { Vpc02Stack } from './vpc02-stack';

export interface TgwStackProps extends cdk.StackProps {
  dmzVpcStack: DmzVpcStack;
  vpc01Stack: Vpc01Stack;
  vpc02Stack: Vpc02Stack;
}

export class TgwStack extends cdk.Stack {
  public readonly transitGateway: ec2.CfnTransitGateway;

  constructor(scope: Construct, id: string, props: TgwStackProps) {
    super(scope, id, props);

    const tags = commonTags();

    // ========================================================================
    // Transit Gateway
    // ========================================================================
    this.transitGateway = new ec2.CfnTransitGateway(this, 'Tgw', {
      description: 'Transit Gateway for lab infrastructure',
      defaultRouteTableAssociation: 'enable',
      defaultRouteTablePropagation: 'enable',
      dnsSupport: 'enable',
      vpnEcmpSupport: 'enable',
      tags: [{ key: 'Name', value: 'lab-tgw' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // TGW VPC Attachments
    // ========================================================================
    const dmzAttachment = new ec2.CfnTransitGatewayAttachment(this, 'TgwDmzAttachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: props.dmzVpcStack.vpcId,
      subnetIds: [
        props.dmzVpcStack.attachSubnetA.ref,
        props.dmzVpcStack.attachSubnetB.ref,
      ],
      tags: [{ key: 'Name', value: 'tgw-dmz-attachment' }, ...this.toTags(tags)],
    });

    const vpc01Attachment = new ec2.CfnTransitGatewayAttachment(this, 'TgwVpc01Attachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: props.vpc01Stack.vpcId,
      subnetIds: [
        props.vpc01Stack.attachSubnetA.ref,
        props.vpc01Stack.attachSubnetB.ref,
      ],
      tags: [{ key: 'Name', value: 'tgw-vpc01-attachment' }, ...this.toTags(tags)],
    });

    const vpc02Attachment = new ec2.CfnTransitGatewayAttachment(this, 'TgwVpc02Attachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: props.vpc02Stack.vpcId,
      subnetIds: [
        props.vpc02Stack.attachSubnetA.ref,
        props.vpc02Stack.attachSubnetB.ref,
      ],
      tags: [{ key: 'Name', value: 'tgw-vpc02-attachment' }, ...this.toTags(tags)],
    });

    // ========================================================================
    // DMZ VPC Routes to VPC01 and VPC02 via TGW
    // ========================================================================
    // DMZ Private route tables -> VPC01 CIDR via TGW
    new ec2.CfnRoute(this, 'DmzPrivateToVpc01A', {
      routeTableId: props.dmzVpcStack.privateRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzPrivateToVpc01B', {
      routeTableId: props.dmzVpcStack.privateRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    // DMZ Private route tables -> VPC02 CIDR via TGW
    new ec2.CfnRoute(this, 'DmzPrivateToVpc02A', {
      routeTableId: props.dmzVpcStack.privateRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzPrivateToVpc02B', {
      routeTableId: props.dmzVpcStack.privateRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    // DMZ Data route tables -> VPC01/VPC02 CIDR via TGW
    new ec2.CfnRoute(this, 'DmzDataToVpc01A', {
      routeTableId: props.dmzVpcStack.dataRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzDataToVpc01B', {
      routeTableId: props.dmzVpcStack.dataRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzDataToVpc02A', {
      routeTableId: props.dmzVpcStack.dataRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzDataToVpc02B', {
      routeTableId: props.dmzVpcStack.dataRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    // DMZ Attach route tables -> VPC01/VPC02 CIDR via TGW
    new ec2.CfnRoute(this, 'DmzAttachToVpc01A', {
      routeTableId: props.dmzVpcStack.attachRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzAttachToVpc01B', {
      routeTableId: props.dmzVpcStack.attachRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzAttachToVpc02A', {
      routeTableId: props.dmzVpcStack.attachRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    new ec2.CfnRoute(this, 'DmzAttachToVpc02B', {
      routeTableId: props.dmzVpcStack.attachRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(dmzAttachment);

    // ========================================================================
    // VPC01 Routes: 0.0.0.0/0 + VPC02 CIDR via TGW
    // ========================================================================
    // VPC01 Private -> default route via TGW
    new ec2.CfnRoute(this, 'Vpc01PrivateDefaultA', {
      routeTableId: props.vpc01Stack.privateRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    new ec2.CfnRoute(this, 'Vpc01PrivateDefaultB', {
      routeTableId: props.vpc01Stack.privateRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    // VPC01 Private -> VPC02 CIDR via TGW
    new ec2.CfnRoute(this, 'Vpc01PrivateToVpc02A', {
      routeTableId: props.vpc01Stack.privateRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    new ec2.CfnRoute(this, 'Vpc01PrivateToVpc02B', {
      routeTableId: props.vpc01Stack.privateRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc02.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    // VPC01 Data -> default route via TGW
    new ec2.CfnRoute(this, 'Vpc01DataDefaultA', {
      routeTableId: props.vpc01Stack.dataRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    new ec2.CfnRoute(this, 'Vpc01DataDefaultB', {
      routeTableId: props.vpc01Stack.dataRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    // VPC01 Public -> default route via TGW
    new ec2.CfnRoute(this, 'Vpc01PublicDefaultA', {
      routeTableId: props.vpc01Stack.publicRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    new ec2.CfnRoute(this, 'Vpc01PublicDefaultB', {
      routeTableId: props.vpc01Stack.publicRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc01Attachment);

    // ========================================================================
    // VPC02 Routes: 0.0.0.0/0 + VPC01 CIDR via TGW
    // ========================================================================
    // VPC02 Private -> default route via TGW
    new ec2.CfnRoute(this, 'Vpc02PrivateDefaultA', {
      routeTableId: props.vpc02Stack.privateRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    new ec2.CfnRoute(this, 'Vpc02PrivateDefaultB', {
      routeTableId: props.vpc02Stack.privateRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    // VPC02 Private -> VPC01 CIDR via TGW
    new ec2.CfnRoute(this, 'Vpc02PrivateToVpc01A', {
      routeTableId: props.vpc02Stack.privateRouteTableA.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    new ec2.CfnRoute(this, 'Vpc02PrivateToVpc01B', {
      routeTableId: props.vpc02Stack.privateRouteTableB.ref,
      destinationCidrBlock: LAB_CONFIG.vpc01.cidr,
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    // VPC02 Data -> default route via TGW
    new ec2.CfnRoute(this, 'Vpc02DataDefaultA', {
      routeTableId: props.vpc02Stack.dataRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    new ec2.CfnRoute(this, 'Vpc02DataDefaultB', {
      routeTableId: props.vpc02Stack.dataRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    // VPC02 Public -> default route via TGW
    new ec2.CfnRoute(this, 'Vpc02PublicDefaultA', {
      routeTableId: props.vpc02Stack.publicRouteTableA.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    new ec2.CfnRoute(this, 'Vpc02PublicDefaultB', {
      routeTableId: props.vpc02Stack.publicRouteTableB.ref,
      destinationCidrBlock: '0.0.0.0/0',
      transitGatewayId: this.transitGateway.ref,
    }).addDependency(vpc02Attachment);

    // ========================================================================
    // Stack Outputs
    // ========================================================================
    new cdk.CfnOutput(this, 'TransitGatewayId', {
      value: this.transitGateway.ref,
      exportName: 'TransitGatewayId',
    });
    new cdk.CfnOutput(this, 'TgwDmzAttachmentId', {
      value: dmzAttachment.ref,
      exportName: 'TgwDmzAttachmentId',
    });
    new cdk.CfnOutput(this, 'TgwVpc01AttachmentId', {
      value: vpc01Attachment.ref,
      exportName: 'TgwVpc01AttachmentId',
    });
    new cdk.CfnOutput(this, 'TgwVpc02AttachmentId', {
      value: vpc02Attachment.ref,
      exportName: 'TgwVpc02AttachmentId',
    });
  }

  private toTags(tags: Record<string, string>): { key: string; value: string }[] {
    return Object.entries(tags).map(([key, value]) => ({ key, value }));
  }
}
