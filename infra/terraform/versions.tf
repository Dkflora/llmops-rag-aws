# Which Terraform and which providers this project needs, and where AWS resources go.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.49 is the first release with generation = "NEXTGEN" on an OpenSearch
      # Serverless collection group, which is what lets the collection scale to zero.
      version = ">= 6.49, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # For a team, keep state in S3 instead of on one laptop. Uncomment and fill in:
  # backend "s3" {
  #   bucket       = "your-terraform-state-bucket"
  #   key          = "northwind-hr/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  # Every resource gets these tags, so the whole demo is easy to find in the console and in the bill
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# CloudFront is global, and its WAF must be created in us-east-1, whatever region the rest uses
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
