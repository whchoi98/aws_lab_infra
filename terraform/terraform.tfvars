region = "ap-northeast-2"

# CloudFront managed prefix list ID for ap-northeast-2
# Find yours: aws ec2 describe-managed-prefix-lists --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing"
cloudfront_prefix_list_id = "pl-22a6434b"

# Sensitive - provide via environment variable or prompt
# export TF_VAR_db_password="YourSecurePassword123!"
# db_password = ""

# VPC CIDRs
vpc01_cidr   = "10.1.0.0/16"
vpc02_cidr   = "10.2.0.0/16"
dmz_vpc_cidr = "10.11.0.0/16"
