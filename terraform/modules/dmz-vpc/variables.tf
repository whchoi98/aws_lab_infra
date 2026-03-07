variable "vpc_cidr" {
  description = "CIDR block for the DMZ VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "data_subnets" {
  description = "Data subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "attach_subnets" {
  description = "TGW Attach subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "fw_subnets" {
  description = "Firewall subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "natgw_subnets" {
  description = "NAT Gateway subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "alb_subnets" {
  description = "ALB subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "gwlb_subnets" {
  description = "GWLB/extra subnet CIDRs [AZ-A, AZ-B]"
  type        = list(string)
}

variable "cloudfront_prefix_list_id" {
  description = "Prefix list ID for CloudFront to restrict ALB access"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
