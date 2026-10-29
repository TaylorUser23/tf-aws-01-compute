# tf-aws-01-compute

**Terraform on AWS — Project 01 of the series: EC2 instances, configured at boot.**

Launches hardened Amazon Linux 2023 instances that install and serve an nginx page through `user_data`, reachable only from your IP, with shell access through SSM Session Manager instead of SSH.

![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A51.9-7B42BC?logo=terraform) ![AWS Provider](https://img.shields.io/badge/hashicorp%2Faws-~%3E6.0-FF9900?logo=amazonaws) ![CI](https://github.com/TaylorUser23/tf-aws-01-compute/actions/workflows/terraform-ci.yml/badge.svg)

---

## The series

Each project is its own repo with a reusable module **and the IAM policy needed to deploy it**. You never run Terraform as admin: your lab permissions grow one reviewed policy at a time. The last project wires everything together into a production-style environment.

| # | Repo | Builds | IAM lesson | Status |
|---|---|---|---|---|
| **01** | **tf-aws-01-compute** | **EC2, IAM instance profile, security group, user_data** | **Region/tag/prefix scoping, PassRole, escalation** | **← you are here** |
| 02 | tf-aws-02-storage | S3 (+ remote state bucket), EBS volumes, lifecycle rules | Bucket policies vs identity policies | planned |
| 03 | tf-aws-03-networking | VPC, public/private subnets across AZs, IGW, NAT, route tables, endpoints | VPC endpoint policies | planned |
| 04 | tf-aws-04-load-balancing | ALB, target groups, listeners, ACM certificate | Service-linked roles | planned |
| 05 | tf-aws-05-autoscaling | Launch template, Auto Scaling group, scaling policies | Permissions boundaries | planned |
| 06 | tf-aws-06-database | RDS (Multi-AZ), subnet groups, Secrets Manager | KMS key policies, secret policies | planned |
| 07 | tf-aws-07-dns-cdn | Route 53, CloudFront, WAF | Global-service permissions | planned |
| 08 | tf-aws-08-observability | CloudWatch dashboards and alarms, SNS, log groups | Cross-service trust | planned |
| 09 | tf-aws-09-prod-app | **Capstone:** composes modules 01–08 into dev + prod environments with remote state and CI/CD | GitHub OIDC deploy role; humans read-only | planned |

```
                             ┌──────────── 09 prod-app ─────────────┐
 Route53/CloudFront (07) ──► │ ALB (04) ──► ASG of EC2 (05 ← 01) ──► RDS (06) │
                             │        inside VPC (03), state in S3 (02)       │
                             └──────────── watched by CloudWatch (08) ────────┘
```

## What this project builds

```
 Default VPC (temporary — replaced in Project 03)
 └── default subnet(s)
     └── EC2 t3.micro  ×  instance_count
           ├── AMI: latest Amazon Linux 2023 (looked up via SSM parameter)
           ├── user_data → installs nginx, writes a page with instance ID + AZ
           ├── IMDSv2 required, encrypted gp3 root volume
           ├── IAM instance profile → AmazonSSMManagedInstanceCore
           └── Security group: inbound 80 from YOUR /32 only, NO port 22
```

## What you'll learn

- Reading Terraform: blocks, references, dependency graph → [docs/01-reading-terraform.md](docs/01-reading-terraform.md)
- `resource` vs `data`, `variable` with `validation`, `locals`, `output`
- Writing and calling a **module** (`modules/ec2-instance`)
- `count`, `for_each`, splat, and for-expressions
- **Instance configuration** with `user_data` + `templatefile()`
- `lifecycle` and replacement triggers
- Security defaults: no SSH, IMDSv2, encrypted volumes, least-privilege SG
- **Least-privilege IAM for the deployer itself** → [docs/02-iam-least-privilege.md](docs/02-iam-least-privilege.md): region and tag (ABAC) conditions, PassRole, and closing a privilege-escalation path

## Prerequisites

Do [docs/00-setup.md](docs/00-setup.md) first: AWS CLI, Terraform, GitHub CLI, and the Session Manager plugin. It walks you through creating the policy in [`iam/TerraformLab-01-Compute.json`](iam/TerraformLab-01-Compute.json) and the least-privilege `tf-lab` IAM user that Terraform runs as.

## Run it

```bash
export AWS_PROFILE=tf-lab
aws sts get-caller-identity                  # confirm the right account

cp terraform.tfvars.example terraform.tfvars
echo "my_ip_cidr = \"$(curl -s https://checkip.amazonaws.com)/32\""   # paste into terraform.tfvars

terraform init          # downloads the AWS provider, creates .terraform.lock.hcl
terraform fmt -recursive
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

After apply, wait about 2 minutes for cloud-init, then:

```bash
terraform output web_urls               # open in a browser
terraform output ssm_connect_commands   # copy one and run it for a shell
```

Inside the SSM shell:

```bash
sudo cat /var/log/cloud-init-output.log | tail -20   # see your user_data run
systemctl status nginx
curl -s localhost | head
```

## Experiments (do these — this is where it sticks)

| Change | Predict, then run `terraform plan` |
|---|---|
| `instance_count = 2` | What gets added? Do existing instances change? |
| `page_message = "v2"` | Why is this `-/+` and not `~`? |
| `instance_type = "t3.small"` | In-place or replace? (Hint: stop/start) |
| `instance_type = "t3.large"` | Plan passes but apply fails. Which policy condition stops it? |
| Delete the SG in the console, then plan | How does Terraform notice drift? |
| `terraform state list` / `terraform state show 'module.web.aws_instance.this[0]'` | What does state actually hold? |
| `my_ip_cidr = "1.2.3.4"` | What does the validation block do? |

## Clean up

```bash
terraform destroy
```

## Cost

One `t3.micro` with a 10 GiB gp3 volume runs roughly **$8–9/month** if left on in us-east-1 (less, or covered, under Free Tier credits). Destroy when you're done each session.

## Security notes

- No SSH keys and no port 22 — access is through SSM, which is IAM-authenticated and logged in CloudTrail.
- IMDSv2 required (`http_tokens = "required"`), hop limit 1.
- Root volume encrypted with the AWS-managed EBS key.
- HTTP limited to a single `/32` you supply.
- State is local and gitignored in this project; Project 02 moves it to an encrypted S3 backend with locking.

## Repo layout

```
.
├── versions.tf              # Terraform + provider pins, (future) backend
├── providers.tf             # AWS provider, default tags
├── variables.tf             # root inputs
├── main.tf                  # default VPC lookup + module call
├── outputs.tf               # URLs, SSM commands
├── terraform.tfvars.example
├── modules/
│   └── ec2-instance/        # ← reused by Project 05 and the capstone
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── templates/user_data.sh.tftpl
├── iam/
│   └── TerraformLab-01-Compute.json   # exactly what this project's Terraform may do
├── docs/
│   ├── 00-setup.md
│   ├── 01-reading-terraform.md
│   └── 02-iam-least-privilege.md
└── .github/workflows/terraform-ci.yml   # fmt, validate, tflint on every push/PR
```

## Exercise answers (from docs/01)

1. `aws_security_group.this` and `aws_iam_instance_profile.this` — the instance references their `id`/`name`, which builds the dependency graph.
2. It's **replaced**. The message is rendered into `user_data`, `user_data_replace_on_change = true`, and user_data only runs on first boot.
3. Nowhere. You connect with `aws ssm start-session`, allowed by the `AmazonSSMManagedInstanceCore` policy on the instance role.
4. Subnets at index 0, 1, 2 — `element(var.subnet_ids, count.index)` round-robins (and would wrap to 0 if count exceeded the subnet count).

---

Part of the **terraform-aws-path** series by [Taylor Wiley](https://tw-it.net) · [LinkedIn](https://linkedin.com/in/taylor-wiley-321301210)
