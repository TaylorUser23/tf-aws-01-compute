output "instance_ids" {
  description = "IDs of the launched instances."
  value       = aws_instance.this[*].id
}

output "private_ips" {
  description = "Private IPs of the instances."
  value       = aws_instance.this[*].private_ip
}

output "public_ips" {
  description = "Public IPs (empty strings if associate_public_ip = false)."
  value       = aws_instance.this[*].public_ip
}

output "security_group_id" {
  description = "Security group attached to the instances. Later projects add rules to it (e.g. allow traffic from the ALB)."
  value       = aws_security_group.this.id
}

output "iam_role_name" {
  description = "Instance role name. Later projects attach more policies (e.g. S3 read access)."
  value       = aws_iam_role.this.name
}

output "ami_id" {
  description = "AMI the instances were launched from."
  value       = nonsensitive(data.aws_ssm_parameter.ami.value)
}
