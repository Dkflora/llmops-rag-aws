# IAM: one role per Lambda function, each allowed only what that function does (least privilege).
#
#   chat       read the app DB secret, call the chat model + Guardrails + Titan, read OpenSearch
#   ingest     read the documents bucket, call Titan, write OpenSearch
#   setup-db   read both DB secrets
#   evaluate   same as chat

locals {
  # An inference profile id is the model id with a region prefix: "global." or
  # "us.". Strip it to get the foundation model ARN the profile resolves to.
  bare_model_id    = replace(replace(var.chat_model_id, "global.", ""), "us.", "")
  bare_fallback_id = replace(replace(var.fallback_chat_model_id, "global.", ""), "us.", "")
  # Both, deduplicated in case the fallback is unset or the same model.
  chat_model_arns = distinct(concat(
    [
      "arn:aws:bedrock:*::foundation-model/${local.bare_model_id}",
      "arn:aws:bedrock:::foundation-model/${local.bare_model_id}",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.chat_model_id}",
    ],
    var.fallback_chat_model_id == "" ? [] : [
      "arn:aws:bedrock:*::foundation-model/${local.bare_fallback_id}",
      "arn:aws:bedrock:::foundation-model/${local.bare_fallback_id}",
      "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.fallback_chat_model_id}",
    ],
  ))
  titan_model_id = "amazon.titan-embed-text-v2:0"
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chat" {
  name               = "${local.name}-chat"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role" "ingest" {
  name               = "${local.name}-ingest"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role" "setup_db" {
  name               = "${local.name}-setup-db"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role" "evaluate" {
  name               = "${local.name}-evaluate"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# What every function needs: run inside the VPC, write logs, send X-Ray traces
locals {
  lambda_roles = {
    chat     = aws_iam_role.chat.name
    ingest   = aws_iam_role.ingest.name
    setup_db = aws_iam_role.setup_db.name
    evaluate = aws_iam_role.evaluate.name
  }
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  for_each   = local.lambda_roles
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray" {
  for_each   = local.lambda_roles
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ---------------------------------------------------------------------------
# Permission building blocks
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "app_secret" {
  statement {
    sid       = "ReadAppDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_app.arn]
  }
}

data "aws_iam_policy_document" "titan" {
  statement {
    sid       = "EmbedWithTitan"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${var.aws_region}::foundation-model/${local.titan_model_id}"]
  }
}

data "aws_iam_policy_document" "answer" {
  statement {
    sid     = "InvokeChatModel"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    # The chat model and the fallback. A plain model id (Nova) and an inference
    # profile id (used by Claude and others) are different ARN shapes, so both are allowed.
    resources = local.chat_model_arns
  }

  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.hr.guardrail_arn]
  }

  statement {
    sid       = "SearchPolicies"
    actions   = ["aoss:APIAccessAll"]
    resources = [aws_opensearchserverless_collection.policies.arn]
  }
}

# ---------------------------------------------------------------------------
# Each role's own policy
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "chat" {
  source_policy_documents = [
    data.aws_iam_policy_document.app_secret.json,
    data.aws_iam_policy_document.titan.json,
    data.aws_iam_policy_document.answer.json,
  ]
}

resource "aws_iam_role_policy" "chat" {
  name   = "chat"
  role   = aws_iam_role.chat.id
  policy = data.aws_iam_policy_document.chat.json
}

resource "aws_iam_role_policy" "evaluate" {
  name   = "evaluate"
  role   = aws_iam_role.evaluate.id
  policy = data.aws_iam_policy_document.chat.json
}

data "aws_iam_policy_document" "ingest" {
  source_policy_documents = [data.aws_iam_policy_document.titan.json]

  statement {
    sid       = "ListDocuments"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.documents.arn]
  }

  statement {
    sid       = "ReadDocuments"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.documents.arn}/*"]
  }

  statement {
    sid       = "WritePolicyIndex"
    actions   = ["aoss:APIAccessAll"]
    resources = [aws_opensearchserverless_collection.policies.arn]
  }
}

resource "aws_iam_role_policy" "ingest" {
  name   = "ingest"
  role   = aws_iam_role.ingest.id
  policy = data.aws_iam_policy_document.ingest.json
}

data "aws_iam_policy_document" "setup_db" {
  statement {
    sid       = "ReadDatabaseSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_app.arn, local.db_admin_secret_arn]
  }
}

resource "aws_iam_role_policy" "setup_db" {
  name   = "setup-db"
  role   = aws_iam_role.setup_db.id
  policy = data.aws_iam_policy_document.setup_db.json
}
