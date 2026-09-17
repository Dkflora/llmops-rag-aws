# Aurora PostgreSQL Serverless v2: employee records, chat history and logs.
#
#   Serverless v2   capacity grows and shrinks with load (auto scaling)
#   min 0 ACUs      pauses when idle, so an unused demo costs only storage.
#                   The first request after a pause waits roughly 15 seconds.
#   2 instances     a writer and a reader in different Availability Zones (Multi-AZ)

resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name}-aurora"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${local.name}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # "provisioned" + db.serverless instances = Serverless v2

  # AWS retires Aurora engine versions, and a retired version fails at create time with
  # "Cannot find version 16.6 for aurora-postgresql". List what your account can use now:
  #   aws rds describe-db-engine-versions --engine aurora-postgresql   #     --query "DBEngineVersions[].EngineVersion" --output text
  engine_version = var.aurora_engine_version
  database_name  = "hr"

  # The admin password is created and rotated by RDS, and kept in Secrets Manager.
  # It never appears in Terraform code or state.
  master_username             = "hr_admin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  storage_encrypted      = true

  # The RDS Data API: lets you run SQL from the console's Query Editor, with no network path to the database
  enable_http_endpoint = true

  serverlessv2_scaling_configuration {
    min_capacity             = 0
    max_capacity             = var.aurora_max_capacity
    seconds_until_auto_pause = 900 # pause after 15 idle minutes
  }

  # Demo settings, so `terraform destroy` removes everything.
  # In production: deletion_protection = true and keep a final snapshot.
  deletion_protection = false
  skip_final_snapshot = true
}

resource "aws_rds_cluster_instance" "aurora" {
  count              = var.aurora_instance_count
  identifier         = "${local.name}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}
