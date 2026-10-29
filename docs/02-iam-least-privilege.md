# 02 — IAM: Least Privilege That Grows With the Series

You don't start with admin. Each project in the series ships **one IAM policy** with exactly what that project's Terraform needs. You add it to your lab permissions when you start the project, and you learn *why* every statement is there.

## The model: two IAM users, two jobs

| IAM user | Access | Permissions | Used for | How often |
|---|---|---|---|---|
| `lab-admin` | Console only | `AdministratorAccess` | Creating each project's policy and attaching it to `tf-lab` | Once per project, ~5 minutes |
| `tf-lab` | CLI access key only | One policy per project | `terraform plan/apply/destroy`, SSM sessions | Daily |

This is **separation of duties**: the identity that builds infrastructure can't widen its own permissions. To get more access, you switch to `lab-admin`, paste a reviewed JSON file from Git, and attach it on purpose. Real platform teams use the same control.

```
 lab-admin ──creates──► IAM policy TerraformLab-01-Compute
 lab-admin ──attaches─► IAM user tf-lab
                              │
                              └──runs──► terraform apply
```

As the series progresses, `tf-lab` collects one policy per project:

```
tf-lab (IAM user)
 ├── TerraformLab-01-Compute      ← this repo
 ├── TerraformLab-02-Storage      ← added in Project 02
 ├── TerraformLab-03-Networking
 └── ...
```

An IAM user can have 10 managed policies attached by default, and the series has 9 projects, so it fits.

## Reading this project's policy

File: [`iam/TerraformLab-01-Compute.json`](../iam/TerraformLab-01-Compute.json). Every statement has a `Sid` that says what it's for. Here's what each one does and which IAM concept it teaches.

| Sid | What it allows | Concept |
|---|---|---|
| `ReadOnlyEC2InLabRegion` | All `ec2:Describe*`, us-east-1 only | Read-only actions are low risk; `aws:RequestedRegion` restricts by region |
| `ReadAmazonLinuxAmiParameter` | Read the public AL2023 AMI parameter | Resource ARNs can target one exact path |
| `LaunchInstancesOnlyIfTaggedAndSmall` | Launch an instance only if tagged `ManagedBy=terraform` and sized `t3.micro`/`t3.small` | `aws:RequestTag` (tag-on-create) and service condition keys (`ec2:InstanceType`) as a cost guardrail |
| `LaunchInstancesSupportingResources` | The AMI, subnet, ENI, SG, and volume that `RunInstances` touches | One API call is authorized against **several resources** — each must be allowed |
| `CreateSecurityGroupsOnlyIfTagged` / `…InAnyLabVpc` | Create SGs, only when tagged | Same split: the new SG has a condition, the VPC it goes into doesn't |
| `TagResourcesAtCreationTime` | `CreateTags` only as part of a create call | `ec2:CreateAction` — you can tag what you're creating, not anything you like |
| `ChangeOnlyTerraformManagedResources` | Modify/stop/terminate/retag only resources already tagged `ManagedBy=terraform` | **ABAC** (attribute-based access control): tags decide access, not resource names |
| `SecurityGroupRuleObjects` | Add/remove individual SG rules | Newer AWS objects (`security-group-rule`) have their own ARNs |
| `ManageOnlyTfPrefixedRolesAndProfiles` | IAM role/instance-profile CRUD, only names starting with `tf` | Name-prefix scoping (IAM roles are global, so no region condition) |
| `AttachOnlyApprovedPoliciesToTfRoles` | Attach **only** `AmazonSSMManagedInstanceCore` | `iam:PolicyARN` closes the classic escalation path (see below) |
| `PassTfRolesToEC2Only` | Hand `tf*` roles to EC2, nothing else | `iam:PassRole` + `iam:PassedToService` |
| `SessionManagerIntoTerraformInstancesOnly` / `…ShellDocument` | `ssm:StartSession`, only to tagged instances, only the shell document | Sessions are authorized against the instance **and** the SSM document |
| `SessionManagerHousekeeping` | List/end/resume sessions | Some APIs don't support resource-level permissions → `"Resource": "*"` |
| `DecodeAccessDeniedMessages` | Decode encoded `AccessDenied` errors | Your debugging tool (below) |

### Why the `iam:PolicyARN` condition matters

Without it, `tf-lab` could do this:

1. Create a role named `tf-backdoor`, allowed by the name prefix.
2. Attach `AdministratorAccess` to it.
3. Launch an instance with that role, then use the instance's credentials.

You'd have turned a limited identity into an admin. That's **privilege escalation through PassRole**, one of the most common real-world IAM findings. Pinning which policies can be attached closes it. Later in the series, once the list of approved policies grows, we'll replace this with a **permissions boundary**, the scalable version of the same idea.

### Why tags instead of names for EC2

Instance IDs are random, so you can't write `instance/tf01-*` in an ARN. Instead, the policy says "you may only touch things tagged `ManagedBy=terraform`," and the provider's `default_tags` puts that tag on everything Terraform creates. Anything created outside Terraform (a console click, another team's server) is untouchable from `tf-lab`.

## Setup: create the policy and attach it (one time)

The step-by-step console instructions are in [00-setup.md, sections 2b–2c](00-setup.md#2b-create-this-projects-policy-as-lab-admin). In short, signed in as `lab-admin`:

1. **IAM → Policies → Create policy → JSON** → paste `iam/TerraformLab-01-Compute.json` → name it `TerraformLab-01-Compute`.
2. **IAM → Users → Create user** `tf-lab` (no console access) → **Attach policies directly** → `TerraformLab-01-Compute`.
3. Create an access key for `tf-lab` and run `aws configure --profile tf-lab`.

### Check the policy before you trust it

The policy editor runs **IAM Access Analyzer** checks as you type and lists them under the editor:

| Finding type | What to do |
|---|---|
| Error | Must fix — the policy won't save |
| Security warning | Read it; usually means something is broader than intended |
| Suggestion | Optional tidy-ups. Expect a couple about `"Resource": "*"`; for the read-only and housekeeping actions they're acceptable |

## Adding a project later (the routine)

Signed in as `lab-admin`:

1. **IAM → Policies → Create policy → JSON** → paste the new project's file, e.g. `iam/TerraformLab-02-Storage.json` → name it to match.
2. **IAM → Users → tf-lab → Add permissions → Attach policies directly** → filter **Customer managed** → tick the new policy → **Add permissions**.

That's it. IAM changes reach `tf-lab` within seconds; there's nothing to log out of or reconfigure.

### Changing an existing project's policy

**IAM → Policies →** select the policy **→ Edit → JSON** → paste the updated file → **Save changes**. IAM saves this as a new *version* and keeps up to five. If the change breaks something, open the **Policy versions** tab and set the previous version as default. That's your rollback.

## When you hit `AccessDenied` (you will — that's the lesson)

1. **Read the error.** It names the action and usually the resource:
   `... is not authorized to perform: ec2:ModifyInstanceAttribute on resource: arn:aws:ec2:...`
2. **Decode it** if it includes an `Encoded authorization failure message`:
   ```bash
   aws sts decode-authorization-message --profile tf-lab \
     --encoded-message '<paste>' --query DecodedMessage --output text | jq
   ```
   This tells you which condition failed (wrong tag, wrong region, wrong instance type).
3. **Fix the policy, not the symptom.** Add the narrowest statement that works, commit it, then paste it into the policy as a new version. It applies within seconds.
4. **Write it down** in the project README's troubleshooting section. A log of permission gaps you found and closed is strong portfolio material.

Try breaking it on purpose:

- Set `instance_type = "t3.large"` and plan, then apply. Plan succeeds; apply is denied. Why?
- Create an instance by hand in the console, then try to terminate it with the CLI using `tf-lab`.
- Temporarily remove `ec2:CreateAction` from `TagResourcesAtCreationTime` and apply.

## Where IAM goes in the rest of the series

| Project | New IAM lesson |
|---|---|
| 01 Compute | Region, tag (ABAC), and name-prefix scoping; PassRole; escalation via attached policies |
| 02 Storage | Resource-based policies (S3 bucket policies) vs identity policies; state-bucket access for Terraform |
| 03 Networking | Scoping a service with very many actions; VPC endpoint policies |
| 04 Load Balancing | Service-linked roles; ACM permissions |
| 05 Autoscaling | **Permissions boundaries** replace the attach-policy allowlist; launch templates + PassRole |
| 06 Database | Secrets Manager resource policies; KMS key policies and grants |
| 07 DNS/CDN | Global services (Route 53, CloudFront, WAF) and us-east-1 quirks |
| 08 Observability | Cross-service trust (SNS, CloudWatch alarms) |
| 09 Prod App | **GitHub Actions OIDC** deploy role; humans drop to read-only + plan; Access Analyzer–generated policies from CloudTrail |
