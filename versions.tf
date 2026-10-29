terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Project 01 uses LOCAL state (terraform.tfstate in this folder — gitignored).
  # Project 02 (storage) builds an S3 state bucket, and every project after it
  # switches to a remote backend like this:
  #
  # backend "s3" {
  #   bucket       = "tw-tf-state-<account-id>"
  #   key          = "tf-aws-01-compute/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  #   encrypt      = true
  # }
}
