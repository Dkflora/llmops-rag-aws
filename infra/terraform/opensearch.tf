# Amazon OpenSearch Serverless: the vector store for policy chunks.
#
# A collection needs three policies before it can exist:
#   encryption    how data is encrypted at rest
#   network       where it can be reached from: only our VPC endpoint
#   data access   which IAM roles can do what with indexes and documents
#
# IAM and the data access policy are two separate gates. A role holding aoss:APIAccessAll
# still gets 403 unless it is also named as a Principal in the data access policy below.
# That is the most common OpenSearch Serverless mistake.
#
# Cost: this collection group is NextGen, which scales to zero when nobody is asking
# questions. A Classic collection bills a 2 OCU minimum around the clock (~$350/month)
# whether or not anyone uses it. Still destroy it after class, but the idle bill is now
# a few dollars rather than a few hundred.

locals {
  collection_name = "${local.name}-policies"
}

# The compute the collection runs on. Generation NEXTGEN is what allows a minimum of 0 OCU.
# Requires AWS provider >= 6.49; on older providers this argument does not exist and you
# get a Classic collection with its much larger idle bill.
resource "aws_opensearchserverless_collection_group" "main" {
  name             = "${local.name}-group"
  description      = "Shared compute for the policy collection"
  generation       = "NEXTGEN"
  standby_replicas = "ENABLED" # NextGen requires it; unlike Classic it does not double the bill

  capacity_limits {
    min_indexing_capacity_in_ocu = 0 # nothing to pay while no one is ingesting
    max_indexing_capacity_in_ocu = 4
    min_search_capacity_in_ocu   = 0 # nothing to pay while no one is searching
    max_search_capacity_in_ocu   = 4
  }
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${local.name}-encryption"
  type = "encryption"
  policy = jsonencode({
    Rules       = [{ ResourceType = "collection", Resource = ["collection/${local.collection_name}"] }]
    AWSOwnedKey = true
  })
}

# A private door into OpenSearch Serverless from our VPC.
#
# This must be an ordinary PrivateLink interface endpoint for the "aoss-data" service, NOT
# the aws_opensearchserverless_vpc_endpoint resource. The two create different private
# hosted zones, and only this one covers NextGen:
#
#   aws_opensearchserverless_vpc_endpoint  ->  *.us-east-1.aoss.amazonaws.com   (Classic)
#   com.amazonaws.us-east-1.aoss-data      ->  *.aoss.us-east-1.on.aws          (NextGen)
#
# A NextGen collection's endpoint is https://<id>.aoss.us-east-1.on.aws. With the wrong
# endpoint that name has no private hosted zone, so it resolves to the public address, the
# network policy below refuses it, and every call hangs until it times out. The symptom is a
# ConnectionTimeout from opensearch-py that looks nothing like a DNS problem.
resource "aws_vpc_endpoint" "aoss_data" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.aoss-data"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${local.name}-aoss-data" }
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${local.name}-network"
  type = "network"
  policy = jsonencode([{
    Rules = [
      { ResourceType = "collection", Resource = ["collection/${local.collection_name}"] },
    ]
    AllowFromPublic = false
    SourceVPCEs     = [aws_vpc_endpoint.aoss_data.id]
  }])
}

resource "aws_opensearchserverless_collection" "policies" {
  name = local.collection_name
  type = "VECTORSEARCH"

  # Compute, scaling and standby all come from the group, so they are not set here.
  collection_group_name = aws_opensearchserverless_collection_group.main.name

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]
}

# Ingestion may create and fill the index. The chat and evaluate functions may only read it.
resource "aws_opensearchserverless_access_policy" "data" {
  name = "${local.name}-data"
  type = "data"
  policy = jsonencode([
    {
      Description = "Ingestion: create the index and write documents"
      Principal   = [aws_iam_role.ingest.arn]
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
          Permission   = ["aoss:DescribeCollectionItems", "aoss:CreateCollectionItems", "aoss:UpdateCollectionItems"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/*"]
          Permission   = ["aoss:CreateIndex", "aoss:DeleteIndex", "aoss:UpdateIndex", "aoss:DescribeIndex", "aoss:ReadDocument", "aoss:WriteDocument"]
        },
      ]
    },
    {
      Description = "Chat and evaluation: read only"
      Principal   = [aws_iam_role.chat.arn, aws_iam_role.evaluate.arn]
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/*"]
          Permission   = ["aoss:DescribeIndex", "aoss:ReadDocument"]
        },
      ]
    },
  ])
}
