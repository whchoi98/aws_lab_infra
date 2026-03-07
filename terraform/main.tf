locals {
  common_tags = {
    Environment = "lab"
    Project     = "aws-lab-infra"
    ManagedBy   = "terraform"
  }
}

# -------------------------------------------------------
# VPC01 - Workload VPC
# -------------------------------------------------------
module "vpc01" {
  source = "./modules/vpc"

  vpc_name        = "VPC01"
  vpc_cidr        = var.vpc01_cidr
  azs             = ["${var.region}a", "${var.region}b"]
  public_subnets  = var.vpc01_public_subnets
  private_subnets = var.vpc01_private_subnets
  data_subnets    = var.vpc01_data_subnets
  attach_subnets  = var.vpc01_attach_subnets
  common_tags     = local.common_tags
}

# -------------------------------------------------------
# VPC02 - Workload VPC
# -------------------------------------------------------
module "vpc02" {
  source = "./modules/vpc"

  vpc_name        = "VPC02"
  vpc_cidr        = var.vpc02_cidr
  azs             = ["${var.region}a", "${var.region}b"]
  public_subnets  = var.vpc02_public_subnets
  private_subnets = var.vpc02_private_subnets
  data_subnets    = var.vpc02_data_subnets
  attach_subnets  = var.vpc02_attach_subnets
  common_tags     = local.common_tags
}

# -------------------------------------------------------
# DMZ VPC
# -------------------------------------------------------
module "dmz_vpc" {
  source = "./modules/dmz-vpc"

  vpc_cidr                  = var.dmz_vpc_cidr
  azs                       = ["${var.region}a", "${var.region}b"]
  public_subnets            = var.dmz_public_subnets
  private_subnets           = var.dmz_private_subnets
  data_subnets              = var.dmz_data_subnets
  attach_subnets            = var.dmz_attach_subnets
  fw_subnets                = var.dmz_fw_subnets
  natgw_subnets             = var.dmz_natgw_subnets
  alb_subnets               = var.dmz_alb_subnets
  gwlb_subnets              = var.dmz_gwlb_subnets
  cloudfront_prefix_list_id = var.cloudfront_prefix_list_id
  common_tags               = local.common_tags
}

# -------------------------------------------------------
# Transit Gateway
# -------------------------------------------------------
module "tgw" {
  source = "./modules/tgw"

  vpc01_id              = module.vpc01.vpc_id
  vpc01_attach_subnets  = module.vpc01.attach_subnet_ids
  vpc02_id              = module.vpc02.vpc_id
  vpc02_attach_subnets  = module.vpc02.attach_subnet_ids
  dmz_vpc_id            = module.dmz_vpc.vpc_id
  dmz_attach_subnets    = module.dmz_vpc.attach_subnet_ids

  # Route table IDs for adding TGW routes
  vpc01_public_rt_id    = module.vpc01.public_route_table_id
  vpc01_private_rt_id   = module.vpc01.private_route_table_id
  vpc01_data_rt_id      = module.vpc01.data_route_table_id
  vpc02_public_rt_id    = module.vpc02.public_route_table_id
  vpc02_private_rt_id   = module.vpc02.private_route_table_id
  vpc02_data_rt_id      = module.vpc02.data_route_table_id
  dmz_private_rt_id     = module.dmz_vpc.private_route_table_id
  dmz_data_rt_id        = module.dmz_vpc.data_route_table_id

  vpc01_cidr            = var.vpc01_cidr
  vpc02_cidr            = var.vpc02_cidr
  dmz_vpc_cidr          = var.dmz_vpc_cidr

  common_tags           = local.common_tags
}

# -------------------------------------------------------
# Data Services (Aurora MySQL + ElastiCache Valkey)
# -------------------------------------------------------
module "data_services" {
  source = "./modules/data-services"

  vpc_id          = module.vpc01.vpc_id
  data_subnet_ids = module.vpc01.data_subnet_ids
  vpc_cidrs       = [var.vpc01_cidr, var.vpc02_cidr, var.dmz_vpc_cidr]
  db_password     = var.db_password
  common_tags     = local.common_tags
}
