# Security groups: firewalls around each part. Each one only allows what that part needs.

# The Lambda functions: they start every connection, and accept none
resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda"
  description = "Lambda functions: outbound to Aurora and VPC endpoints only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to VPC endpoints and S3"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0" # S3 gateway endpoint addresses are outside the VPC range
}

resource "aws_vpc_security_group_egress_rule" "lambda_postgres" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "PostgreSQL to Aurora"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.aurora.id
}

# Aurora: only the Lambda functions may connect
resource "aws_security_group" "aurora" {
  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL: inbound from Lambda only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_lambda" {
  security_group_id            = aws_security_group.aurora.id
  description                  = "PostgreSQL from Lambda"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.lambda.id
}

# VPC endpoints: accept HTTPS from the Lambda functions
resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints"
  description = "VPC endpoints: HTTPS from Lambda only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_lambda" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from Lambda"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.lambda.id
}
