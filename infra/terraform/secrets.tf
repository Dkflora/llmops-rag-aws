# AWS Secrets Manager: database credentials.
#
#   admin secret   created by RDS itself (aurora.tf). Only the setup function reads it.
#   app secret     created here, for hr_app, the user the chat function connects as.
#                  Row-level security applies to hr_app, not to the admin.

resource "random_password" "db_app" {
  length  = 32
  special = false # letters and digits only: nothing to escape in a connection string
}

resource "aws_secretsmanager_secret" "db_app" {
  name                    = "${local.name}/db-app-user"
  description             = "Aurora credentials for hr_app, the application user"
  recovery_window_in_days = 0 # demo: delete at once on destroy, so the name can be reused
}

# Note: this value is also stored in the Terraform state file, so keep state private (see versions.tf).
resource "aws_secretsmanager_secret_version" "db_app" {
  secret_id = aws_secretsmanager_secret.db_app.id
  secret_string = jsonencode({
    username = "hr_app"
    password = random_password.db_app.result
  })
}

locals {
  db_admin_secret_arn = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}
