variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "cloudfront_prefix_list_id" {
  description = "Prefix list ID for CloudFront to restrict ALB access"
  type        = string
}

variable "db_password" {
  description = "Password for Aurora MySQL database"
  type        = string
  sensitive   = true
}

# -------------------------------------------------------
# CIDR Configurations
# -------------------------------------------------------

variable "vpc01_cidr" {
  description = "CIDR block for VPC01"
  type        = string
  default     = "10.1.0.0/16"
}

variable "vpc02_cidr" {
  description = "CIDR block for VPC02"
  type        = string
  default     = "10.2.0.0/16"
}

variable "dmz_vpc_cidr" {
  description = "CIDR block for DMZ VPC"
  type        = string
  default     = "10.11.0.0/16"
}

# VPC01 Subnets
variable "vpc01_public_subnets" {
  description = "Public subnet CIDRs for VPC01 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "vpc01_private_subnets" {
  description = "Private subnet CIDRs for VPC01 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.1.32.0/19", "10.1.64.0/19"]
}

variable "vpc01_data_subnets" {
  description = "Data subnet CIDRs for VPC01 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.1.160.0/21", "10.1.168.0/21"]
}

variable "vpc01_attach_subnets" {
  description = "TGW Attach subnet CIDRs for VPC01 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.1.248.0/24", "10.1.249.0/24"]
}

# VPC02 Subnets
variable "vpc02_public_subnets" {
  description = "Public subnet CIDRs for VPC02 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24"]
}

variable "vpc02_private_subnets" {
  description = "Private subnet CIDRs for VPC02 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.2.32.0/19", "10.2.64.0/19"]
}

variable "vpc02_data_subnets" {
  description = "Data subnet CIDRs for VPC02 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.2.160.0/21", "10.2.168.0/21"]
}

variable "vpc02_attach_subnets" {
  description = "TGW Attach subnet CIDRs for VPC02 [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.2.248.0/24", "10.2.249.0/24"]
}

# DMZ VPC Subnets
variable "dmz_public_subnets" {
  description = "Public subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.1.0/24", "10.11.2.0/24"]
}

variable "dmz_private_subnets" {
  description = "Private subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.32.0/19", "10.11.64.0/19"]
}

variable "dmz_data_subnets" {
  description = "Data subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.160.0/21", "10.11.168.0/21"]
}

variable "dmz_attach_subnets" {
  description = "TGW Attach subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.248.0/24", "10.11.249.0/24"]
}

variable "dmz_fw_subnets" {
  description = "Firewall subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.252.0/24", "10.11.253.0/24"]
}

variable "dmz_natgw_subnets" {
  description = "NAT Gateway subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.254.0/24", "10.11.255.0/24"]
}

variable "dmz_alb_subnets" {
  description = "ALB subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.3.0/24", "10.11.4.0/24"]
}

variable "dmz_gwlb_subnets" {
  description = "GWLB/extra subnet CIDRs for DMZ VPC [AZ-A, AZ-B]"
  type        = list(string)
  default     = ["10.11.5.0/24", "10.11.6.0/24"]
}
