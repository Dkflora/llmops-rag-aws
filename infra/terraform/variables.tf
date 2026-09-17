# The settings you can change. Put your values in terraform.tfvars (see terraform.tfvars.example).

variable "project_name" {
  description = "Prefix for every resource name. Lowercase letters, numbers and hyphens."
  type        = string
  default     = "northwind-hr"
}

variable "aws_region" {
  description = "Region for everything except the CloudFront WAF. Bedrock must offer Claude Haiku 4.5 and Titan Embeddings V2 here."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "A domain you own, with a Route 53 hosted zone in this account, e.g. example.com. Leave empty to use the CloudFront address instead."
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "The name in front of domain_name. The app ends up at https://<subdomain>.<domain_name>."
  type        = string
  default     = "hrassistant"
}

variable "cognito_domain_prefix" {
  description = <<-EOT
    The sign-in page address: https://<prefix>.auth.<region>.amazoncognito.com

    This name is claimed across the whole region, so everyone deploying into
    us-east-1 needs their own. Add your name or initials. There is no default
    on purpose: two people applying with the same value is a confusing failure
    part way through a build.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,62}$", var.cognito_domain_prefix))
    error_message = "Lowercase letters, numbers and hyphens, 3 to 63 characters, not starting with a hyphen."
  }
}

variable "demo_user_emails" {
  description = "Cognito users to create. Each must match an employee email in the database."
  type        = list(string)
  default = [
    "amara.diallo@northwind.example",
    "liam.fischer@northwind.example",
    "priya.raman@northwind.example",
    "dana.whitfield@northwind.example",
  ]
}

variable "aurora_instance_count" {
  description = "1 writer, plus readers in other Availability Zones. 2 = Multi-AZ: if one zone fails, the reader takes over."
  type        = number
  default     = 2
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL version. AWS retires old ones: check with `aws rds describe-db-engine-versions --engine aurora-postgresql`."
  type        = string
  default     = "17.10"
}

variable "aurora_max_capacity" {
  description = "Most Aurora capacity units (ACUs) the database may scale up to."
  type        = number
  default     = 2
}

variable "min_best_similarity" {
  description = <<-EOT
    Relevance cut-off for Titan embeddings. Measure it with the evaluate
    function's similarity report; do not guess it.

    Measured on this corpus: small talk scores 0.106 to 0.148, real questions
    0.361 to 0.656. 0.35 sat 0.011 below the lowest real question, and approximate
    vector search moves a score by more than that between runs, so the same
    question passed on one run and failed on the next. 0.25 sits in the gap
    between the two groups with room either side.
  EOT
  type        = string
  default     = "0.25"
}

variable "max_gap_from_best" {
  description = "How far below the best match another chunk may score and still be used."
  type        = string
  default     = "0.10"
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarms. Leave empty for no emails."
  type        = string
  default     = ""
}

variable "chat_model_id" {
  description = <<-EOT
    Any Bedrock model that supports tool use, reached through the Converse API.
    Amazon Nova needs no access request. Claude needs a use case form approved
    once per account, and is then reached through a cross-region inference
    profile: global.anthropic.claude-haiku-4-5-20251001-v1:0
  EOT
  type        = string
  default     = "amazon.nova-pro-v1:0"
}

variable "certificate_arn" {
  description = <<-EOT
    Optional. An ACM certificate you already have, in us-east-1, covering the
    subdomain. Leave empty and Terraform requests and validates one for you.
    Set it when the domain already has a certificate, so a second one is not
    issued for names that are already covered.
  EOT
  type        = string
  default     = ""
}

variable "fallback_chat_model_id" {
  description = <<-EOT
    Used only when chat_model_id will not answer. Both models are granted to the
    chat role, so the fallback works without a redeploy. Empty turns it off.
  EOT
  type        = string
  default     = "amazon.nova-lite-v1:0"
}
