variable "vpc01_id" {
  description = "VPC01 ID"
  type        = string
}

variable "vpc01_attach_subnets" {
  description = "VPC01 TGW attachment subnet IDs"
  type        = list(string)
}

variable "vpc02_id" {
  description = "VPC02 ID"
  type        = string
}

variable "vpc02_attach_subnets" {
  description = "VPC02 TGW attachment subnet IDs"
  type        = list(string)
}

variable "dmz_vpc_id" {
  description = "DMZ VPC ID"
  type        = string
}

variable "dmz_attach_subnets" {
  description = "DMZ VPC TGW attachment subnet IDs"
  type        = list(string)
}

# Route table IDs for adding TGW routes
variable "vpc01_public_rt_id" {
  description = "VPC01 public route table ID"
  type        = string
}

variable "vpc01_private_rt_id" {
  description = "VPC01 private route table ID"
  type        = string
}

variable "vpc01_data_rt_id" {
  description = "VPC01 data route table ID"
  type        = string
}

variable "vpc02_public_rt_id" {
  description = "VPC02 public route table ID"
  type        = string
}

variable "vpc02_private_rt_id" {
  description = "VPC02 private route table ID"
  type        = string
}

variable "vpc02_data_rt_id" {
  description = "VPC02 data route table ID"
  type        = string
}

variable "dmz_private_rt_id" {
  description = "DMZ VPC private route table ID"
  type        = string
}

variable "dmz_data_rt_id" {
  description = "DMZ VPC data route table ID"
  type        = string
}

variable "dmz_attach_rt_id" {
  description = "DMZ VPC attach route table ID"
  type        = string
}

variable "dmz_natgw_rt_ids" {
  description = "DMZ VPC NAT GW route table IDs (per AZ)"
  type        = list(string)
}

# CIDRs for route creation
variable "vpc01_cidr" {
  description = "VPC01 CIDR"
  type        = string
}

variable "vpc02_cidr" {
  description = "VPC02 CIDR"
  type        = string
}

variable "dmz_vpc_cidr" {
  description = "DMZ VPC CIDR"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
