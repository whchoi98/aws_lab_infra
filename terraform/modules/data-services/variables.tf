variable "vpc_id" {
  description = "VPC ID where data services will be deployed"
  type        = string
}

variable "data_subnet_ids" {
  description = "Subnet IDs for data services"
  type        = list(string)
}

variable "vpc_cidrs" {
  description = "List of VPC CIDRs allowed to access data services"
  type        = list(string)
}

variable "db_password" {
  description = "Master password for Aurora MySQL"
  type        = string
  sensitive   = true
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
