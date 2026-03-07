variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
