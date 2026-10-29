output "instance_ids" {
  description = "EC2 instance IDs."
  value       = module.web.instance_ids
}

output "web_urls" {
  description = "Open these in a browser (only works from my_ip_cidr). Give cloud-init ~2 minutes after apply."
  value       = [for ip in module.web.public_ips : "http://${ip}"]
}

output "ssm_connect_commands" {
  description = "Shell into each instance with no SSH key and no port 22."
  value = [
    for id in module.web.instance_ids :
    "aws ssm start-session --target ${id} --region ${var.aws_region}"
  ]
}

output "ami_id" {
  description = "Amazon Linux 2023 AMI that was resolved at plan time."
  value       = module.web.ami_id
}
