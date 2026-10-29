# 01 — How to Read Terraform

Before running anything, learn to read what's in this repo. Every Terraform project is built from the same handful of block types.

## The mental model

```
 .tf files (what you WANT)   +   state file (what Terraform BUILT)   +   AWS (what ACTUALLY exists)
                     \                     |                                /
                      `-------> terraform plan compares all three <--------'
                                           |
                              terraform apply makes AWS match the code
```

- **Declarative:** you describe the end result ("one t3.micro running nginx"), not the steps.
- **State:** `terraform.tfstate` maps each resource in your code to a real AWS ID. Lose it and Terraform forgets it built anything. Never edit it by hand and never commit it.
- **Plan before apply, always.** The plan is the contract.

## File layout (convention, not a rule)

Terraform loads every `*.tf` file in a folder as one configuration. File names are for humans.

| File | What goes in it |
|---|---|
| `versions.tf` | Terraform + provider version requirements, backend |
| `providers.tf` | Provider setup (region, profile, default tags) |
| `variables.tf` | Inputs |
| `main.tf` | Resources, data sources, module calls |
| `outputs.tf` | Values printed after apply / exposed to other configs |
| `terraform.tfvars` | Your actual input values (gitignored) |

## The block types — with examples from this repo

Every block reads as: `<BLOCK TYPE> "<LABEL>" "<LABEL>" { arguments }`

### `terraform` — settings for Terraform itself

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
```

`~> 6.0` means "any 6.x, never 7.0" — protects you from breaking major versions.

### `provider` — which cloud, which region, which credentials

```hcl
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

### `resource` — something Terraform creates and owns

```hcl
resource "aws_security_group" "this" {
#         └── resource type ──┘ └ local name
  name   = "${var.name}-ec2-sg"
  vpc_id = var.vpc_id
}
```

Reference it elsewhere as **`<type>.<name>.<attribute>`** → `aws_security_group.this.id`.

That reference is also how Terraform figures out **ordering**: the instance mentions the security group's `id`, so Terraform builds the security group first. You almost never set order by hand.

### `data` — something that already exists; read-only lookup

```hcl
data "aws_vpc" "default" {
  default = true
}
```

Referenced with a `data.` prefix: `data.aws_vpc.default.id`. Terraform will never create, change, or delete it.

### `variable` — an input

```hcl
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
```

Used as `var.instance_type`. No default = required. Values come from (later wins): `default` → `TF_VAR_instance_type` env var → `terraform.tfvars` → `*.auto.tfvars` → `-var` / `-var-file` on the command line.

`validation` blocks reject bad input at plan time instead of failing halfway through an apply.

### `locals` — named expressions, to avoid repeating yourself

```hcl
locals {
  name = "tf01-${var.environment}-web"
}
```

Used as `local.name` (singular!).

### `output` — values to show or pass along

```hcl
output "instance_ids" {
  value = module.web.instance_ids
}
```

Outputs are how projects will hand values to each other later (VPC IDs from networking → load balancer project, etc.).

### `module` — call a reusable folder of Terraform

```hcl
module "web" {
  source        = "./modules/ec2-instance"
  name          = local.name
  vpc_id        = data.aws_vpc.default.id
}
```

A module's `variable` blocks are its parameters; its `output` blocks are its return values (`module.web.instance_ids`). This is the key to the whole series: each project ships a module, and the capstone just calls them all.

## Expressions you'll see in this repo

| Syntax | Meaning |
|---|---|
| `"${var.name}-sg"` | String interpolation |
| `count = 3` | Make 3 copies; `count.index` is 0, 1, 2 |
| `for_each = toset(var.cidrs)` | One copy per item; `each.value` is the item |
| `aws_instance.this[*].id` | Splat: list of `id` from every copy |
| `[for ip in list : "http://${ip}"]` | For-expression: transform a list |
| `element(list, i)` | Item `i`, wrapping around — used for round-robin subnets |
| `merge(map1, map2)` | Combine maps (tags) |
| `templatefile(path, vars)` | Render a file with variables filled in (our `user_data`) |

## Meta-arguments that change behavior

- **`lifecycle { ignore_changes = [ami] }`** — don't replace instances just because AWS published a newer AMI.
- **`user_data_replace_on_change = true`** — if you edit the boot script, rebuild the instance (it only runs once at first boot).
- **`depends_on`** — force an order Terraform can't infer. Rarely needed.

## Reading a plan

```
  # module.web.aws_instance.this[0] will be created
  + resource "aws_instance" "this" {
      + ami           = (sensitive value)
      + instance_type = "t3.micro"
      + id            = (known after apply)
```

| Symbol | Meaning |
|---|---|
| `+` | create |
| `-` | destroy |
| `~` | update in place |
| `-/+` | destroy then recreate (**read these carefully**) |
| `(known after apply)` | AWS assigns it; can't be known yet |

Last line is the summary: `Plan: 7 to add, 0 to change, 0 to destroy.` With the defaults, expect **7 to add**: IAM role, policy attachment, instance profile, security group, ingress rule, egress rule, and 1 instance (each extra instance adds 1).

## Exercise before you apply

Open `modules/ec2-instance/main.tf` and answer:

1. Which resource must exist before `aws_instance.this` can be created? How does Terraform know?
2. What happens to the instance if you change `page_message` and apply again? Why?
3. Where does port 22 get opened? (Trick question — find out how you'll get a shell instead.)
4. If you set `instance_count = 3` and there are 6 default subnets, which subnets get used?

Answers are at the bottom of the main README.
