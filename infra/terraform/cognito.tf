# Amazon Cognito: sign-in.
#
# The React app sends people to Cognito's sign-in page (OpenID Connect, authorization code + PKCE).
# Cognito sends back tokens. API Gateway checks the ID token on every request.
#
# In a real company, Cognito would pass sign-in on to the company's identity provider
# (Okta, Microsoft Entra ID) with SAML or OIDC, so people use their normal work login (SSO).

resource "aws_cognito_user_pool" "main" {
  name = "${local.name}-users"

  username_attributes      = ["email"] # people sign in with their work email
  auto_verified_attributes = ["email"]

  # Only an administrator creates accounts. Nobody can sign themselves up.
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  deletion_protection = "INACTIVE" # demo: allow `terraform destroy`
}

# The hosted sign-in page address
resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

# The React app. It runs in the browser, so it can't keep a secret: it uses PKCE instead.
resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  # Where Cognito may send people back to after sign-in and sign-out
  # Cognito only redirects back to an address listed here, exactly, with no trailing slash.
  # Both are listed so the app still works on its CloudFront address while DNS propagates.
  callback_urls = distinct(compact(["https://${aws_cloudfront_distribution.app.domain_name}", local.app_url]))
  logout_urls   = distinct(compact(["https://${aws_cloudfront_distribution.app.domain_name}", local.app_url]))

  id_token_validity      = 60 # minutes
  access_token_validity  = 60
  refresh_token_validity = 1 # days
  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}

# Demo accounts. No email is sent: an administrator sets the first password (see the guide).
resource "aws_cognito_user" "demo" {
  for_each     = toset(var.demo_user_emails)
  user_pool_id = aws_cognito_user_pool.main.id
  username     = each.value

  attributes = {
    email          = each.value
    email_verified = true
  }

  message_action = "SUPPRESS"
}
