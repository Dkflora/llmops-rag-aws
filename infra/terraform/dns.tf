# Route 53 and ACM: give the app a real address, https://hrassistant.yourdomain.com,
# instead of https://d1234abcd.cloudfront.net.
#
# Three pieces have to line up:
#
#   1. A wildcard certificate for *.yourdomain.com, issued by ACM in us-east-1.
#      CloudFront is a global service and only reads certificates from us-east-1,
#      whatever region the rest of the stack runs in. A certificate in another region
#      is invisible to CloudFront, which is the usual cause of "no certificate found".
#
#   2. Proof that you own the domain. ACM publishes a CNAME it expects to find in your
#      hosted zone; Terraform writes that record, then waits for ACM to see it.
#
#   3. An alias record pointing hrassistant.yourdomain.com at the distribution. An alias
#      is a Route 53 extra, not a CNAME: it resolves to CloudFront's changing IP addresses
#      and costs nothing to query.
#
# All of this is optional. Leave domain_name empty in terraform.tfvars and the app is
# served from its CloudFront address, with nothing here created.

locals {
  # "" means: no custom domain, use the CloudFront address
  use_custom_domain = var.domain_name != ""
  app_domain        = local.use_custom_domain ? "${var.subdomain}.${var.domain_name}" : ""
  app_url           = local.use_custom_domain ? "https://${local.app_domain}" : "https://${aws_cloudfront_distribution.app.domain_name}"

  # Three cases, and only the middle one creates anything here:
  #   no domain                     -> CloudFront's own address and certificate
  #   domain, no certificate        -> request one and validate it through the zone
  #   domain, certificate_arn set   -> use the one you already have
  create_certificate = local.use_custom_domain && var.certificate_arn == ""
  certificate_arn = (
    local.use_custom_domain
    ? (var.certificate_arn != "" ? var.certificate_arn : aws_acm_certificate_validation.app[0].certificate_arn)
    : null
  )
}

# Your existing hosted zone. Terraform looks it up rather than creating it: the zone is
# where your domain's name servers point, and recreating it would break every other record.
data "aws_route53_zone" "main" {
  count        = local.use_custom_domain ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

# One wildcard certificate covers hrassistant.yourdomain.com and every other subdomain
# you add later, so a second project needs no second certificate.
# Note: *.yourdomain.com does NOT cover the bare yourdomain.com, which is why the apex is
# listed separately as an alternative name.
resource "aws_acm_certificate" "app" {
  count    = local.create_certificate ? 1 : 0
  provider = aws.us_east_1

  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# The CNAME records ACM asks for. One per distinct name on the certificate; the wildcard
# and the apex validate with the same record, so for_each de-duplicates them.
resource "aws_route53_record" "certificate_validation" {
  for_each = local.create_certificate ? {
    for option in aws_acm_certificate.app[0].domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  zone_id         = data.aws_route53_zone.main[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Waits until ACM has checked the records above and moved the certificate to ISSUED.
# Usually under two minutes. CloudFront cannot use a PENDING_VALIDATION certificate.
resource "aws_acm_certificate_validation" "app" {
  count    = local.create_certificate ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

# hrassistant.yourdomain.com -> the CloudFront distribution.
# Z2FDTNDATAQYW2 is CloudFront's fixed hosted zone ID, the same in every account.
resource "aws_route53_record" "app" {
  count   = local.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.app_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = false
  }
}

# The same name over IPv6. CloudFront answers on both, and some mobile networks are
# IPv6-only, so without this record those users cannot reach the app at all.
resource "aws_route53_record" "app_ipv6" {
  count   = local.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.app_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = false
  }
}
