PROJECT 01 - QUESTIONS & ANSWERS
Terraform on AWS series | tf-aws-01-compute
Notes from working through setup, the first plan, and the first apply.
======================================================================


1. WHAT IS THE SESSION MANAGER DEPENDENCY?
----------------------------------------------------------------------
SSM Session Manager replaces SSH. Instead of opening port 22 and
managing key pairs, `aws ssm start-session --target <instance-id>`
opens a shell through AWS Systems Manager. Five things must line up:

  - Your machine:   the session-manager-plugin is installed
                    (macOS: brew install --cask session-manager-plugin)
  - The instance:   the SSM Agent is running (preinstalled on Amazon
                    Linux 2023)
  - The instance:   its IAM role has AmazonSSMManagedInstanceCore
  - The network:    the instance can reach SSM over outbound HTTPS 443
                    (public IP + open egress now; VPC endpoints or NAT
                    once it moves to a private subnet in Project 03)
  - You:            your IAM user is allowed ssm:StartSession

Why bother: no port 22, no keys to lose, and every session is
authenticated through IAM and logged.


2. WHY NOT JUST GIVE THE TERRAFORM USER ADMINISTRATORACCESS?
----------------------------------------------------------------------
It works, but it breaks least privilege. A typo or a bad module could
do anything to the account, and you never learn which permissions a
project actually needs.

Instead, each project in the series ships its own IAM policy in iam/.
The Terraform user starts with only Project 01's permissions and gains
one reviewed policy per project. Learning IAM grows alongside learning
Terraform.


3. WHY TWO IAM USERS?
----------------------------------------------------------------------
  lab-admin   Console only, AdministratorAccess.
              Job: create each project's policy and attach it to tf-lab.

  tf-lab      CLI access key only, project policies only.
              Job: run terraform plan/apply/destroy and SSM sessions.

This is separation of duties: the identity that builds infrastructure
cannot widen its own permissions. To get more access you must switch
to lab-admin and attach a policy on purpose.


4. WHY NOT IAM IDENTITY CENTER / AWS ORGANIZATIONS?
----------------------------------------------------------------------
This is a beginner series in one AWS account. Identity Center requires
AWS Organizations, which adds moving parts the series doesn't need.
Plain IAM users are simpler and teach the same least-privilege lesson.

5. WHAT DOES THE TERRAFORMLAB-01-COMPUTE POLICY ALLOW?
----------------------------------------------------------------------
Only what this project's Terraform needs, mostly limited to us-east-1:

  - Read-only EC2 lookups (ec2:Describe*) and the Amazon Linux AMI
    parameter
  - Launch instances only if tagged ManagedBy=terraform and sized
    t3.micro or t3.small (cost guardrail)
  - Create security groups only if tagged ManagedBy=terraform
  - Change or delete only resources already tagged
    ManagedBy=terraform (ABAC - tags decide access, not names)
  - Manage only IAM roles/instance profiles whose names start with "tf"
  - Attach only AmazonSSMManagedInstanceCore to those roles
    (blocks privilege escalation: otherwise tf-lab could create a role,
    attach AdministratorAccess, and hand it to a server)
  - Pass "tf" roles to EC2 only
  - Start SSM sessions only on tagged instances

The ManagedBy=terraform tag is added automatically by default_tags in
providers.tf. Code and policy are wired together.


6. WHAT IS TERRAFORM, IN ONE PICTURE?
----------------------------------------------------------------------
  .tf files (what you WANT)
  + terraform.tfstate (what Terraform BUILT)
  + real AWS (what actually EXISTS)
      -> terraform plan   compares all three, changes nothing
      -> terraform apply  makes AWS match the code, updates state

Providers are plugins that translate Terraform blocks into API calls
(the AWS provider turns aws_instance into ec2:RunInstances).
State is the ledger mapping code names to real AWS IDs. Never edit it,
never commit it.


7. WHAT GOES IN A .TF FILE?
----------------------------------------------------------------------
Only blocks:  <type> "<label>" "<label>" { key = value }

  terraform   settings: Terraform/provider versions, backend
  provider    connection: region, credentials, default tags
  variable    inputs                       -> var.name
  locals      named expressions            -> local.name
  data        read something that exists   -> data.type.name.attr
  resource    create and own something     -> type.name.attr
  module      call a folder of Terraform   -> module.name.output
  output      return values

Only `resource` changes the real world. References between blocks are
how Terraform decides what to build first.

Does NOT go in .tf files: your personal values (terraform.tfvars),
secrets (CLI profile / Secrets Manager), what was built (state).


8. WHAT IS EACH FOLDER IN THIS REPO?
----------------------------------------------------------------------
  .github/workflows/   CI on every push/PR: fmt, validate, tflint.
                       Checks code only - never deploys, has no AWS
                       credentials.
  modules/ec2-instance reusable module with the real resources
                       (IAM role, security group, instances) and the
                       user_data startup script template. Later
                       projects reuse it.
  iam/                 the IAM policy this project needs.
                       Terraform doesn't read it; it's version-
                       controlled documentation of permissions.
  docs/                setup and learning guides.
  root .tf files       "what to build": call the module with this
                       project's values.

Created when you run commands:
  .terraform/           downloaded provider       (gitignored)
  .terraform.lock.hcl   exact provider versions   (COMMIT this)
  terraform.tfstate     the ledger                (NEVER commit)


9. HOW DO I READ THE PLAN?
----------------------------------------------------------------------
First plan result: Plan: 7 to add, 0 to change, 0 to destroy.

  + create   - destroy   ~ update in place   -/+ replace (read carefully)

  (known after apply)  AWS assigns this value (IDs, IPs)
  this[0]              a copy made by count (numbered)
  http["1.2.3.4/32"]   a copy made by for_each (keyed by value)
  tags vs tags_all     tags_all = module tags + provider default_tags
  (sensitive value)    hidden on purpose (the AMI comes from SSM)

The rendered user_data in the plan shows templatefile() working:
Terraform filled in the instance name, bash variables were left alone.

Apply a saved plan with `terraform apply tfplan` - it does exactly
what you reviewed, with no extra prompt.


10. WHAT DO I DO WITH THE SSM OUTPUT COMMAND?
----------------------------------------------------------------------
Run it in your terminal to get a shell on the instance:

  aws ssm start-session --target <instance-id> --region us-east-1

Useful checks once connected:
  sudo tail -20 /var/log/cloud-init-output.log   user_data output
  systemctl status nginx                         web server running
  curl -s localhost                              the served page
  exit                                           leave

TargetNotConnected = wait 2-3 minutes for the agent to check in.


11. THE WHOLE FLOW, CORRECTED
----------------------------------------------------------------------
Common mix-ups:
  - tf-lab runs Terraform, NOT lab-admin. lab-admin only did setup.
  - Nobody assumes a role. tf-lab is a plain IAM user with an access
    key in the local CLI profile. (Role assumption comes in the
    capstone with GitHub Actions OIDC.)
  - Pushing to GitHub does NOT deploy. GitHub stores code and runs CI
    checks. The build ran from the laptop via terraform apply.
  - The policy we wrote is attached to the tf-lab USER (limits what I
    can build). The server has a SEPARATE role (tf01-dev-web-ec2-role)
    so it can talk to SSM.

Summary:
I wrote code describing a server. On my laptop, Terraform logged in as
tf-lab - a user only allowed to build what this project needs. It
compared the code to AWS (plan), then made AWS match (apply). AWS
created a server in the default VPC, ran my startup script to install
nginx, and gave the server its own role so I could connect through SSM
instead of SSH. Terraform recorded what it built in terraform.tfstate
so it can update or destroy it later. Separately, GitHub stores the
code and checks it on every push.


Self-check:
  Q: Would apply work with the lab-admin profile?
  A: Yes - admin can do anything, which is exactly why it's a bad idea.

  Q: What happens if terraform.tfstate is deleted and you plan?
  A: Terraform forgets what it built and plans to create all 7
     resources again, causing duplicates or name conflicts.

  Q: Who needed permission for the SSM session?
  A: Both. tf-lab needed ssm:StartSession to open it; the server's
     role needed AmazonSSMManagedInstanceCore to accept it.


Remember: terraform destroy at the end of every session.
