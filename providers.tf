provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile # null = use AWS_PROFILE / default credential chain

  # Every resource the AWS provider creates gets these tags automatically.
  default_tags {
    tags = {
      Project     = "tf-aws-01-compute"
      Series      = "terraform-aws-path"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "github.com/TaylorUser23/tf-aws-01-compute"
    }
  }
}
