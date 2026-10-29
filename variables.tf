variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile (from aws configure sso). Leave null to use AWS_PROFILE."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment label used in names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "instance_count" {
  description = "Number of web instances."
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "my_ip_cidr" {
  description = "Your public IP as a /32 (curl -s https://checkip.amazonaws.com). Only this address can view the web page."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0)) && endswith(var.my_ip_cidr, "/32")
    error_message = "my_ip_cidr must be a single IPv4 address in /32 form, e.g. 203.0.113.10/32."
  }
}

variable "page_message" {
  description = "Message shown on the nginx demo page."
  type        = string
  default     = "Hello from Project 01 — provisioned and configured by Terraform"
}
