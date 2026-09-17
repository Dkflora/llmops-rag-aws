# Values printed after `terraform apply`. The guide's deploy steps use them.
# Read one with:  terraform output -raw app_url

output "app_url" {
  description = "Open this in a browser. Your own domain if you set one, otherwise the CloudFront address."
  value       = local.app_url
}

output "cloudfront_domain" {
  description = "The distribution's own address. Still works when a custom domain is configured."
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "certificate_arn" {
  description = "The wildcard certificate CloudFront is using, if any"
  value       = local.use_custom_domain ? local.certificate_arn : "none (using the CloudFront certificate)"
}

output "documents_bucket" {
  description = "Upload the policy files and manifest.json here"
  value       = aws_s3_bucket.documents.bucket
}

output "frontend_bucket" {
  description = "Upload the built React app (frontend/dist) here"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  description = "Needed to clear the CloudFront cache after uploading a new front end"
  value       = aws_cloudfront_distribution.app.id
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "function_names" {
  value = { for key, function in aws_lambda_function.app : key => function.function_name }
}

output "api_endpoint" {
  description = "API Gateway's own address (the app uses it through CloudFront)"
  value       = aws_apigatewayv2_api.chat.api_endpoint
}

# Paste this into frontend/.env.production before `npm run build`. These values are public.
output "frontend_env" {
  value = <<-EOT
    VITE_AUTH_MODE=cognito
    VITE_COGNITO_AUTHORITY=https://${aws_cognito_user_pool.main.endpoint}
    VITE_COGNITO_CLIENT_ID=${aws_cognito_user_pool_client.web.id}
    VITE_COGNITO_DOMAIN=https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com
  EOT
}
