# VPC endpoints: private doors from our network to AWS services.
# Without them, Lambda functions in private subnets could not reach Bedrock or Secrets Manager
# (we have no NAT gateway, which would cost more and open a path to the internet).
# The OpenSearch Serverless endpoint is in opensearch.tf.

# Interface endpoints: a network card in each private subnet
resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "bedrock-runtime", # the chat model, Titan embeddings, Guardrails
    "secretsmanager",  # database passwords
  ])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true # the normal service address now resolves to the endpoint

  tags = { Name = "${local.name}-${each.key}" }
}

# Gateway endpoint for S3: a route in the route table, and free
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${local.name}-s3" }
}
