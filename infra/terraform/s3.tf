# Two S3 buckets, both private.
#
#   documents   the HR policy files and manifest.json. Versioning keeps every old copy,
#               so you can see and restore what a policy said on any date.
#   frontend    the built React app. Only CloudFront can read it (cloudfront.tf).

resource "aws_s3_bucket" "documents" {
  bucket_prefix = "${local.name}-documents-"
  force_destroy = true # demo: let `terraform destroy` delete a bucket that still has files
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "frontend" {
  bucket_prefix = "${local.name}-frontend-"
  force_destroy = true
}

# Encryption at rest, and no public access, for both buckets
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = {
    documents = aws_s3_bucket.documents.id
    frontend  = aws_s3_bucket.frontend.id
  }
  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = {
    documents = aws_s3_bucket.documents.id
    frontend  = aws_s3_bucket.frontend.id
  }
  bucket = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Only our CloudFront distribution may read the front-end files
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.app.arn }
      }
    }]
  })
}
