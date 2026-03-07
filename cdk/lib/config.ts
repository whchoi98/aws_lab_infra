/**
 * Configuration for the AWS Lab Infrastructure.
 * Contains all CIDR blocks, subnet definitions, and shared constants.
 */

export interface SubnetConfig {
  cidrA: string;
  cidrB: string;
}

export interface VpcConfig {
  cidr: string;
  subnets: Record<string, SubnetConfig>;
}

export interface LabConfig {
  region: string;
  environment: string;
  project: string;
  managedBy: string;
  dmzVpc: VpcConfig;
  vpc01: VpcConfig;
  vpc02: VpcConfig;
}

export const LAB_CONFIG: LabConfig = {
  region: 'ap-northeast-2',
  environment: 'lab',
  project: 'aws-lab-infra',
  managedBy: 'cdk',

  dmzVpc: {
    cidr: '10.11.0.0/16',
    subnets: {
      public: {
        cidrA: '10.11.11.0/24',
        cidrB: '10.11.12.0/24',
      },
      private: {
        cidrA: '10.11.32.0/19',
        cidrB: '10.11.64.0/19',
      },
      data: {
        cidrA: '10.11.160.0/21',
        cidrB: '10.11.168.0/21',
      },
      attach: {
        cidrA: '10.11.241.0/24',
        cidrB: '10.11.242.0/24',
      },
      fw: {
        cidrA: '10.11.243.0/24',
        cidrB: '10.11.244.0/24',
      },
      natgw: {
        cidrA: '10.11.245.0/24',
        cidrB: '10.11.246.0/24',
      },
    },
  },

  vpc01: {
    cidr: '10.1.0.0/16',
    subnets: {
      public: {
        cidrA: '10.1.11.0/24',
        cidrB: '10.1.12.0/24',
      },
      private: {
        cidrA: '10.1.32.0/19',
        cidrB: '10.1.64.0/19',
      },
      data: {
        cidrA: '10.1.160.0/21',
        cidrB: '10.1.168.0/21',
      },
      attach: {
        cidrA: '10.1.241.0/24',
        cidrB: '10.1.242.0/24',
      },
    },
  },

  vpc02: {
    cidr: '10.2.0.0/16',
    subnets: {
      public: {
        cidrA: '10.2.11.0/24',
        cidrB: '10.2.12.0/24',
      },
      private: {
        cidrA: '10.2.32.0/19',
        cidrB: '10.2.64.0/19',
      },
      data: {
        cidrA: '10.2.160.0/21',
        cidrB: '10.2.168.0/21',
      },
      attach: {
        cidrA: '10.2.241.0/24',
        cidrB: '10.2.242.0/24',
      },
    },
  },
};

/**
 * Common tags applied to all resources.
 */
export function commonTags(): Record<string, string> {
  return {
    Environment: LAB_CONFIG.environment,
    Project: LAB_CONFIG.project,
    ManagedBy: LAB_CONFIG.managedBy,
  };
}
