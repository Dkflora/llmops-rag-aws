# Four Lambda functions, one zip of our code, one layer of libraries.
#
#   chat       behind API Gateway: the orchestrator that answers questions
#   ingest     S3 upload or daily schedule: load, chunk, embed, store
#   setup-db   run once by hand: tables, row-level security, demo data
#   evaluate   run by hand after each change: score the assistant
#
# All four run the same build/function.zip and differ only in the handler they call.
# Build the two zips before `terraform apply`:
#
#   bash scripts/build-layer.sh       build/layer.zip     libraries, ~33 MB, rarely changes
#   bash scripts/build-function.sh    build/function.zip  our code, ~26 KB, changes constantly

locals {
  build_dir      = "${path.module}/../../build"
  layer_zip      = "${local.build_dir}/layer.zip"
  function_zip   = "${local.build_dir}/function.zip"
  python_runtime = "python3.12"

  # Settings every function gets
  common_env = {
    DB_HOST             = aws_rds_cluster.aurora.endpoint
    DB_NAME             = aws_rds_cluster.aurora.database_name
    DB_APP_SECRET_ARN   = aws_secretsmanager_secret.db_app.arn
    SEARCH_URL          = aws_opensearchserverless_collection.policies.collection_endpoint
    MIN_BEST_SIMILARITY = var.min_best_similarity
    MAX_GAP_FROM_BEST   = var.max_gap_from_best
    CHAT_MODEL          = var.chat_model_id
    FALLBACK_CHAT_MODEL = var.fallback_chat_model_id
    GUARDRAIL_ID        = aws_bedrock_guardrail.hr.guardrail_id
    GUARDRAIL_VERSION   = aws_bedrock_guardrail_version.hr.version
  }

  functions = {
    chat = {
      handler = "app.chat_handler.handler"
      role    = aws_iam_role.chat.arn
      timeout = 29 # API Gateway gives up at 30 seconds
      env     = local.common_env
    }
    ingest = {
      handler = "app.ingest_handler.handler"
      role    = aws_iam_role.ingest.arn
      timeout = 900
      env = {
        SEARCH_URL       = aws_opensearchserverless_collection.policies.collection_endpoint
        DOCUMENTS_BUCKET = aws_s3_bucket.documents.bucket
      }
    }
    setup-db = {
      handler = "app.setup_db_handler.handler"
      role    = aws_iam_role.setup_db.arn
      timeout = 120
      env = {
        DB_HOST             = aws_rds_cluster.aurora.endpoint
        DB_NAME             = aws_rds_cluster.aurora.database_name
        DB_APP_SECRET_ARN   = aws_secretsmanager_secret.db_app.arn
        DB_ADMIN_SECRET_ARN = local.db_admin_secret_arn
      }
    }
    evaluate = {
      handler = "app.evaluate_handler.handler"
      role    = aws_iam_role.evaluate.arn
      timeout = 900
      env     = local.common_env
    }
  }
}

# The libraries: psycopg, opensearch-py, boto3, pypdf and the rest.
# Lambda unzips this into /opt and puts /opt/python on the import path.
resource "aws_lambda_layer_version" "dependencies" {
  layer_name          = "${local.name}-dependencies"
  filename            = local.layer_zip
  source_code_hash    = filebase64sha256(local.layer_zip)
  compatible_runtimes = [local.python_runtime]
  description         = "Built by scripts/build-layer.sh from lambda/requirements.txt"

  lifecycle {
    precondition {
      condition     = fileexists(local.layer_zip)
      error_message = "build/layer.zip is missing. Run: bash scripts/build-layer.sh"
    }
  }
}

# Create each log group ourselves, so logs are kept for 14 days instead of forever
resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.functions
  name              = "/aws/lambda/${local.name}-${each.key}"
  retention_in_days = 14
}

resource "aws_lambda_function" "app" {
  for_each = local.functions

  function_name = "${local.name}-${each.key}"
  role          = each.value.role
  runtime       = local.python_runtime
  architectures = ["x86_64"] # the layer holds Linux x86_64 wheels, so the function must match
  handler       = each.value.handler
  memory_size   = 1024
  timeout       = each.value.timeout

  filename = local.function_zip
  # Terraform compares this hash with the deployed one. Rebuild the zip, run apply,
  # and only the functions whose code actually changed are updated.
  source_code_hash = filebase64sha256(local.function_zip)

  layers = [aws_lambda_layer_version.dependencies.arn]

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = each.value.env
  }

  tracing_config {
    mode = "Active" # X-Ray traces for every invocation
  }

  lifecycle {
    precondition {
      condition     = fileexists(local.function_zip)
      error_message = "build/function.zip is missing. Run: bash scripts/build-function.sh"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.vpc_access,
  ]
}
