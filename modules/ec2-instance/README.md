# Module: `ec2-instance`

Launches 1–5 hardened Amazon Linux 2023 instances with an SSM-enabled IAM role, a security group with no SSH, and an nginx demo page configured through `user_data`.

## Usage

From this repo:

```hcl
module "web" {
  source = "./modules/ec2-instance"

  name               = "tf01-web"
  vpc_id             = data.aws_vpc.default.id
  subnet_ids         = data.aws_subnets.default.ids
  allowed_http_cidrs = ["203.0.113.10/32"]
}
```

From a later project (pinned to a release tag):

```hcl
module "web" {
  source = "git::https://github.com/TaylorUser23/tf-aws-01-compute.git//modules/ec2-instance?ref=v1.0.0"
  # ...
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Name prefix for every resource |
| `vpc_id` | string | — | VPC for the security group |
| `subnet_ids` | list(string) | — | Subnets, used round-robin |
| `instance_count` | number | `1` | 1–5 instances |
| `instance_type` | string | `t3.micro` | Instance size |
| `associate_public_ip` | bool | `true` | Public IP on/off |
| `allowed_http_cidrs` | list(string) | `[]` | Who can reach port 80 |
| `root_volume_size` | number | `10` | GiB, gp3, encrypted |
| `ami_ssm_parameter` | string | AL2023 x86_64 | SSM path for the AMI |
| `page_message` | string | `Provisioned by Terraform` | Text on the demo page |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

`instance_ids`, `private_ips`, `public_ips`, `security_group_id`, `iam_role_name`, `ami_id`
