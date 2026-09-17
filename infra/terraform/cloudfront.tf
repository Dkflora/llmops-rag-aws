# Amazon CloudFront: one HTTPS address for the whole app.
#
#   /          the React files from the private S3 bucket
#   /api/*     passed to API Gateway, never cached
#
# Same address for both means no CORS setup, and WAF (waf.tf) protects both.
# Set domain_name in terraform.tfvars and the distribution answers on your own name as
# well, using the wildcard certificate from dns.tf.

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# The API must get the Authorization header, and nothing may be cached
resource "aws_cloudfront_cache_policy" "api" {
  name        = "${local.name}-api-no-cache"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
      }
    }
    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  comment             = "${local.name} HR assistant"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # North America and Europe edge locations: cheapest
  web_acl_id          = aws_wafv2_web_acl.app.arn

  # The names this distribution will answer to. Every name here must be covered by the
  # certificate below, or CloudFront refuses to deploy.
  aliases = local.use_custom_domain ? [local.app_domain] : []

  origin {
    origin_id                = "frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "api"
    domain_name = replace(aws_apigatewayv2_api.chat.api_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # The React app
  default_cache_behavior {
    target_origin_id       = "frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  # The API
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # The React app does its own routing, so a deep link like /conversations/7 is not a file in
  # the bucket. S3 answers 403 (it will not even admit whether the key exists), and without
  # these two rules the visitor gets an S3 XML error instead of the app.
  # Returning index.html with status 200 hands the URL to React, which renders the right page.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Without a domain of your own: CloudFront's shared certificate on https://xxxx.cloudfront.net.
    # With one: the wildcard certificate, after ACM has confirmed you own the domain.
    cloudfront_default_certificate = local.use_custom_domain ? null : true
    acm_certificate_arn            = local.certificate_arn
    ssl_support_method             = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}
