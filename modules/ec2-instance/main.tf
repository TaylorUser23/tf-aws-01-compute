# ---------------------------------------------------------------------------
# DATA SOURCES — read things that already exist; Terraform does not manage them
# ---------------------------------------------------------------------------

# Ask SSM Parameter Store for the newest Amazon Linux 2023 AMI.
# Better than hardcoding an AMI ID: IDs differ per region and go stale.
data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# LOCALS — computed values reused below
# ---------------------------------------------------------------------------

locals {
  common_tags = merge(var.tags, { Module = "ec2-instance" })
}

# ---------------------------------------------------------------------------
# IAM — lets instances register with SSM so we can shell in WITHOUT SSH keys
# or an open port 22 (aws ssm start-session --target <instance-id>)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "this" {
  name               = "${var.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.this.name
  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# SECURITY GROUP — no SSH at all; HTTP only from the CIDRs you allow
# ---------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.name}-ec2-sg"
  description = "Managed by Terraform: ${var.name} instances"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name}-ec2-sg" })
}

# One rule per CIDR. for_each needs a set or map, so we convert the list.
resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.allowed_http_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "HTTP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

# Outbound is needed for dnf package installs and the SSM agent.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# EC2 INSTANCES
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  count = var.instance_count

  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = element(var.subnet_ids, count.index) # round-robin across subnets
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = var.associate_public_ip

  # CONFIGURATION: this script runs once at first boot (cloud-init).
  # templatefile() injects Terraform values into the script.
  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    instance_name = "${var.name}-${count.index + 1}"
    page_message  = var.page_message
  })
  user_data_replace_on_change = true # edit the script -> instance is replaced

  # Hardening: require IMDSv2 (blocks SSRF-style credential theft via IMDSv1)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.common_tags, { Name = "${var.name}-${count.index + 1}" })

  # A new AMI is published regularly. Without this, every plan after a
  # release would want to replace your instances.
  lifecycle {
    ignore_changes = [ami]
  }
}
