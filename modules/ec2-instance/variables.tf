# ---------------------------------------------------------------------------
# Inputs to the ec2-instance module.
#
# This module is written so later projects can reuse it unchanged:
#   - Project 01 passes the default VPC's subnet.
#   - Project 03 (networking) will pass a private subnet from our own VPC.
#   - The capstone prod environment pins it with a git ref, e.g. ?ref=v1.0.0
# ---------------------------------------------------------------------------

variable "name" {
  description = "Name prefix applied to every resource this module creates."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name))
    error_message = "name must be 3-32 characters: lowercase letters, numbers, and hyphens."
  }
}

variable "instance_count" {
  description = "How many identical instances to launch."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 5
    error_message = "instance_count must be between 1 and 5 for this lab."
  }
}

variable "instance_type" {
  description = "EC2 instance size."
  type        = string
  default     = "t3.micro"
}

variable "vpc_id" {
  description = "VPC the security group is created in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets to spread instances across (round-robin)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "Provide at least one subnet ID."
  }
}

variable "associate_public_ip" {
  description = "Give instances a public IP. True for this lab; false once they sit behind a load balancer."
  type        = bool
  default     = true
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to reach port 80. Empty list = no inbound HTTP."
  type        = list(string)
  default     = []
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 10
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that resolves to the latest AMI ID. Defaults to Amazon Linux 2023."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "page_message" {
  description = "Text written into the demo web page by user_data."
  type        = string
  default     = "Provisioned by Terraform"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}
