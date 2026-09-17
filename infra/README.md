# infra

Everything that creates AWS resources. Two ways to build the same thing.

| | |
|---|---|
| **[clickops.md](clickops.md)** | Build it by hand in the AWS Console. Every service, every setting, and why. About three hours. |
| **[terraform/](terraform)** | Build the identical stack in one command. About twenty minutes, most of it waiting for Aurora and CloudFront. |

Do the console walkthrough once. You cannot debug a Terraform stack you have never seen the
inside of, and half the hard questions about this architecture are about the parts
Terraform hides from you. Then use Terraform for every build after that, because doing it by
hand twice teaches you nothing new and takes three hours.

Neither path contains application code. The code is in [`lambda/`](../lambda) and reaches AWS
as two zip files built by [`scripts/`](../scripts).

## Layout

```
infra/
  clickops.md      the console walkthrough
  terraform/       one file per service
```

`terraform/` is its own folder because Terraform uses its directory as a working directory:
`terraform init` puts several hundred megabytes of provider binaries in `.terraform/`, and
your state file, lock file and `terraform.tfvars` all live beside the `.tf` files. Keeping
that out of the way means `infra/` stays readable.

## The Terraform path

```bash
# 1. Build the two zips. Terraform uploads them; it does not build them.
bash scripts/build-layer.sh
bash scripts/build-function.sh

# 2. Settings
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars      # set cognito_domain_prefix at least

# 3. Build
terraform init
terraform apply

# 4. Create the tables, the security policies and the demo data
aws lambda invoke --function-name northwind-hr-setup-db --cli-read-timeout 300 /tmp/setup.json

# 5. Load the documents. The manifest goes last: uploading it is what triggers ingestion.
DOCS=$(terraform output -raw documents_bucket)
aws s3 cp ../../lambda/data/documents/ "s3://$DOCS/" --recursive --exclude manifest.json
aws s3 cp ../../lambda/data/documents/manifest.json "s3://$DOCS/"

# 6. Publish the React app
terraform output -raw frontend_env > ../../frontend/.env.production
cd ../../frontend && npm install && npm run build && cd ../infra/terraform
aws s3 sync ../../frontend/dist/ "s3://$(terraform output -raw frontend_bucket)/" --delete
aws cloudfront create-invalidation --distribution-id "$(terraform output -raw cloudfront_distribution_id)" --paths "/*"

# 7. Set a password for a demo user, then open the app
aws cognito-idp admin-set-user-password \
  --user-pool-id "$(terraform output -raw cognito_user_pool_id)" \
  --username amara.diallo@northwind.example --password 'Northwind-Demo-2026!' --permanent
terraform output -raw app_url
```

Tear it down with `terraform destroy`. Then check Resource Groups > Tag Editor for
`Project = northwind-hr` across all regions: it should come back empty.

## What is in each file

| File | What it creates |
|---|---|
| `network.tf` | VPC, two private subnets, route table. No internet gateway, no NAT. |
| `security_groups.tf` | Three firewalls: Lambda, Aurora, VPC endpoints |
| `endpoints.tf` | Private routes to Bedrock, Secrets Manager and S3 |
| `aurora.tf` | Aurora PostgreSQL Serverless v2, minimum 0 ACUs |
| `secrets.tf` | The `hr_app` credentials (the master password is managed by RDS) |
| `opensearch.tf` | NextGen Serverless collection group and collection, and its access policies |
| `s3.tf` | The documents bucket (versioned) and the front-end bucket (private) |
| `bedrock.tf` | The guardrail, and a numbered version of it |
| `iam.tf` | One role per function, each with only what that function does |
| `lambda.tf` | The dependency layer and the four functions |
| `ingestion_triggers.tf` | S3 notification on `manifest.json`, plus a daily EventBridge rule |
| `api_gateway.tf` | HTTP API, routes, Cognito JWT authorizer, throttling |
| `cognito.tf` | User pool, app client, demo users |
| `cloudfront.tf` | One HTTPS address for the app and the API |
| `waf.tf` | Managed rule sets and a per-IP rate limit |
| `dns.tf` | Route 53 records and the wildcard ACM certificate (optional) |
| `monitoring.tf` | Alarms for errors, 5xx responses and slow answers |
| `outputs.tf` | The values the deploy steps above use |

## Settings worth knowing

Set these in `terraform.tfvars`:

| Variable | Default | Why you would change it |
|---|---|---|
| `cognito_domain_prefix` | none, required | Must be unique in the region. Add your initials. |
| `domain_name` | `""` | Your domain, if its hosted zone is in this account. Empty means the CloudFront address. |
| `subdomain` | `hrassistant` | The app ends up at `https://<subdomain>.<domain_name>` |
| `aurora_instance_count` | 2 | 1 halves the database cost and gives up Multi-AZ failover |
| `alarm_email` | `""` | Where CloudWatch alarms go. AWS sends a confirmation first. |
| `min_best_similarity` | `0.35` | The relevance cut-off. Measure it for your corpus rather than guessing. |

## Two things to get right

**OpenSearch must be NextGen.** `opensearch.tf` creates a collection group with
`generation = "NEXTGEN"` and a minimum of 0 OCUs, so an idle collection costs a few dollars a
month. A Classic collection bills a 2 OCU minimum around the clock, about $350 a month,
whether or not anybody uses it. This needs AWS provider 6.49 or newer.

**The certificate must be in us-east-1.** CloudFront reads certificates only from us-east-1,
whatever region the rest of the stack runs in. `dns.tf` uses the `aws.us_east_1` provider
alias for exactly this reason.
