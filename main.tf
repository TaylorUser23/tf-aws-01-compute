# ---------------------------------------------------------------------------
# Project 01 — Compute
#
# Networking is Project 03, so for now we borrow the account's DEFAULT VPC.
# These data sources look it up instead of creating anything.
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  name = "tf01-${var.environment}-web"
}

# ---------------------------------------------------------------------------
# The module call. Everything interesting lives in ./modules/ec2-instance —
# this file just decides WHAT to build; the module knows HOW.
# ---------------------------------------------------------------------------

module "web" {
  source = "./modules/ec2-instance"

  name               = local.name
  instance_count     = var.instance_count
  instance_type      = var.instance_type
  vpc_id             = data.aws_vpc.default.id
  subnet_ids         = data.aws_subnets.default.ids
  allowed_http_cidrs = [var.my_ip_cidr]
  page_message       = var.page_message
}
