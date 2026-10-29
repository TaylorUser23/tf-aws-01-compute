# 00 — Setup: AWS CLI, Terraform, and GitHub

Do this once. Every project in the series reuses the same tools and AWS profile.

## 1. Install the tools

| Tool | macOS (Homebrew) | Windows (winget) | Linux |
|---|---|---|---|
| AWS CLI v2 | `brew install awscli` | `winget install Amazon.AWSCLI` | [AWS installer](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` | `winget install Hashicorp.Terraform` | [HashiCorp apt/yum repo](https://developer.hashicorp.com/terraform/install) |
| GitHub CLI | `brew install gh` | `winget install GitHub.cli` | [cli.github.com](https://cli.github.com) |
| Session Manager plugin | `brew install --cask session-manager-plugin` | [MSI installer](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | same link |
| TFLint (optional) | `brew install tflint` | `winget install TerraformLinters.tflint` | `curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh \| bash` |

Check:

```bash
aws --version          # aws-cli/2.x
terraform -version     # Terraform v1.9 or newer
gh --version
session-manager-plugin --version
```

## 2. Create two IAM users and configure the AWS CLI

Everything happens in **one AWS account** with plain IAM users — no Organizations, no Identity Center.

| User | Access | Permissions | Use it for |
|---|---|---|---|
| `lab-admin` | Console only (password + MFA) | `AdministratorAccess` | Creating and attaching each project's IAM policy |
| `tf-lab` | CLI only (access key) | Only the project policies from `iam/` | Running Terraform and SSM sessions — your daily driver |

Why two? The identity that runs Terraform can't grant itself more power. To widen `tf-lab`, you have to log in as `lab-admin` and attach a policy on purpose. Details: [02-iam-least-privilege.md](02-iam-least-privilege.md).

### 2a. Lock down root and create `lab-admin` (as root, one time)

1. Sign in as the **root user** → top-right account menu → **Security credentials** → **Assign MFA device**.
2. **IAM → Users → Create user**
   - User name: `lab-admin`
   - Tick **Provide user access to the AWS Management Console** → **I want to create an IAM user** → set a custom password → untick "must create a new password" if you like → **Next**
   - **Attach policies directly** → tick `AdministratorAccess` → **Next** → **Create user**
3. Copy the **console sign-in URL** shown on the success page (`https://<account-id>.signin.aws.amazon.com/console`).
4. Sign out of root. Sign in at that URL as `lab-admin`, then go to **IAM → Users → lab-admin → Security credentials → Assign MFA device**.

From now on, root stays locked away. `lab-admin` never gets an access key — it's console-only.

### 2b. Create this project's policy (as `lab-admin`)

1. **IAM → Policies → Create policy** → **JSON** tab.
2. Delete the placeholder text and paste the entire contents of [`iam/TerraformLab-01-Compute.json`](../iam/TerraformLab-01-Compute.json).
3. Look at the checks under the editor (IAM Access Analyzer runs automatically). Errors must be fixed; a few suggestions about `"Resource": "*"` are expected.
4. **Next** → Policy name: `TerraformLab-01-Compute` → **Create policy**.

### 2c. Create `tf-lab` (as `lab-admin`)

1. **IAM → Users → Create user**
   - User name: `tf-lab`
   - Leave **console access unticked** — this user is for the CLI only → **Next**
   - **Attach policies directly** → change the filter to **Customer managed** → tick `TerraformLab-01-Compute` → **Next** → **Create user**
2. Open **tf-lab → Security credentials → Create access key**
   - Use case: **Command Line Interface (CLI)** → tick the acknowledgment → **Next** → **Create access key**
   - Copy the **Access key ID** and **Secret access key** now. The secret is shown only once.

### 2d. Configure the CLI

```bash
aws configure --profile tf-lab
```

| Prompt | Answer |
|---|---|
| AWS Access Key ID | from step 2c |
| AWS Secret Access Key | from step 2c |
| Default region name | `us-east-1` |
| Default output format | `json` |

The keys are stored in `~/.aws/credentials` on your machine, outside every repo.

### 2e. Prove it's least privilege

```bash
export AWS_PROFILE=tf-lab            # PowerShell: $env:AWS_PROFILE="tf-lab"

aws sts get-caller-identity          # Arn ends in :user/tf-lab
aws ec2 describe-vpcs                # works — Describe is allowed
aws s3 ls                            # AccessDenied — S3 arrives in Project 02
```

That pattern means it's set up correctly.

### Access key hygiene

An access key doesn't expire on its own, so treat it like a password:

- Never paste it into a `.tf` file, a `.tfvars` file, a script, or a chat. Terraform reads it from your profile automatically.
- Rotate it every ~90 days: create a second key, `aws configure --profile tf-lab` with the new one, then deactivate and delete the old one.
- Delete it when you finish the series.
- If it ever leaks, deactivate it in the console immediately. Because `tf-lab` is least privilege, a leak can only reach what the policies allow, which is the point of the whole exercise.

> Already enabled IAM Identity Center or Organizations while following an earlier version of this guide? It's harmless and free; you can simply ignore it.

## 3. GitHub: authenticate and create the repo

```bash
gh auth login                        # GitHub.com → HTTPS → login with browser
```

From inside this project folder:

```bash
cd tf-aws-01-compute
git init -b main
git add .
git commit -m "Project 01: EC2 compute module with user_data configuration"

gh repo create TaylorUser23/tf-aws-01-compute \
  --public \
  --source=. \
  --remote=origin \
  --description "Terraform AWS series 01 — EC2 instances configured with user_data, IMDSv2, SSM access" \
  --push

gh repo edit TaylorUser23/tf-aws-01-compute \
  --add-topic terraform --add-topic aws --add-topic ec2 --add-topic infrastructure-as-code --add-topic learning
```

Check: the **Actions** tab should show `terraform-ci` running fmt / validate / tflint.

### Protect `main` (recommended)

```bash
gh api -X PUT repos/TaylorUser23/tf-aws-01-compute/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": { "strict": true, "contexts": ["validate"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

From here on, work on a branch, open a PR, and let CI pass before merging — the same flow you'd use on a real team.

### Tag a release once it works

The capstone environment pulls modules by tag, so tag each project when it's done:

```bash
git tag -a v1.0.0 -m "Project 01 complete"
git push origin v1.0.0
```

## 4. A cost guardrail (do this now)

Do this while signed in as **root** in step 2a, because by default IAM users can't see billing pages.

1. **Billing and Cost Management → Budgets → Create budget**
2. **Use a template** → **Monthly cost budget**
3. Budgeted amount: `$20` (or whatever you're comfortable with)
4. Email recipients: your email → **Create budget**

You'll get an email at 85% and 100% of the amount, plus a forecast alert. Later projects (NAT gateways, load balancers, RDS) cost real money per hour, so **`terraform destroy` at the end of every session**.
