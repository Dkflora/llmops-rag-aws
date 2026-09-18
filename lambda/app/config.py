"""All settings, read from environment variables once.

This code runs in one place: AWS. Claude and Titan on Amazon Bedrock, OpenSearch
Serverless, Aurora PostgreSQL, credentials from Secrets Manager. Terraform sets
these values on each Lambda function, and the defaults below exist so that an
unset variable fails with a clear message rather than a KeyError.

The exception is DATABASE_URL. Set it on your own machine to point the tests at
Aurora, which is how the row-level security tests are run. Nothing on Lambda
sets it, because Lambda reads the passwords from Secrets Manager instead.
"""

import os
from pathlib import Path

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# ---------------------------------------------------------------------------
# Database: Aurora PostgreSQL
# ---------------------------------------------------------------------------
# Empty on Lambda. Set on your machine to run the tests against Aurora:
# one connection string for the app user, one for the admin user.
DATABASE_URL = os.environ.get("DATABASE_URL", "")
DATABASE_ADMIN_URL = os.environ.get("DATABASE_ADMIN_URL", "")

# The database address, and the Secrets Manager secrets holding the passwords.
DB_HOST = os.environ.get("DB_HOST", "")
DB_NAME = os.environ.get("DB_NAME", "hr")
# hr_app: row-level security applies to this user
DB_APP_SECRET_ARN = os.environ.get("DB_APP_SECRET_ARN", "")
DB_ADMIN_SECRET_ARN = os.environ.get("DB_ADMIN_SECRET_ARN", "")  # master user: only for setup

# ---------------------------------------------------------------------------
# Search: OpenSearch Serverless
# ---------------------------------------------------------------------------
SEARCH_URL = os.environ.get("SEARCH_URL", "")
POLICY_INDEX = "hr-policies"

# ---------------------------------------------------------------------------
# Documents: an S3 bucket, with the repo copy as the source to upload
# ---------------------------------------------------------------------------
DOCUMENTS_BUCKET = os.environ.get("DOCUMENTS_BUCKET", "")
DATA_DIR = Path(__file__).parent.parent / "data"
DOCUMENTS_DIR = DATA_DIR / "documents"

CHUNK_SIZE = 700
CHUNK_OVERLAP = 80

# ---------------------------------------------------------------------------
# Embeddings and relevance thresholds
# ---------------------------------------------------------------------------
# 8, not 4: a policy that differs by country (parental leave: US, UK, DE) needs room
# for each country's passage. The gap filter below still drops the weak ones.
RESULTS_PER_SEARCH = 8

# A year in a question earlier than this means "the old version", e.g. "the 2024
# expense policy". Superseded documents are searched only for those questions.
CURRENT_POLICY_YEAR = 2026

EMBEDDING_MODEL = "amazon.titan-embed-text-v2:0"
EMBEDDING_SIZE = 1024

# Measured on this corpus with the evaluate function, not guessed:
#   small talk        0.106 to 0.148
#   real questions    0.361 to 0.656
# 0.35 sat 0.011 below the lowest real question, which approximate vector
# search crosses between runs. 0.25 sits in the gap between the two groups.
MIN_BEST_SIMILARITY = float(os.environ.get("MIN_BEST_SIMILARITY", "0.25"))
MAX_GAP_FROM_BEST = float(os.environ.get("MAX_GAP_FROM_BEST", "0.10"))

# ---------------------------------------------------------------------------
# Answering: Claude, and Amazon Bedrock Guardrails
# ---------------------------------------------------------------------------
# Any Bedrock model that supports tool use, reached through the Converse API.
# Nova needs no access request, which is why it is the default. Point this at
# a Claude inference profile once the use case form has been approved:
#   global.anthropic.claude-haiku-4-5-20251001-v1:0
CHAT_MODEL = os.environ.get("CHAT_MODEL", "amazon.nova-pro-v1:0")

# Used only when CHAT_MODEL will not answer: throttled, warming up, withdrawn,
# or never enabled in this account. Pick one from a different family, because
# two models from the same family tend to be unavailable together. Set it to
# an empty string to turn the fallback off and let the error surface.
FALLBACK_CHAT_MODEL = os.environ.get("FALLBACK_CHAT_MODEL", "amazon.nova-lite-v1:0")

# Empty until you create the guardrail in step 3, so the checks are skipped
# until then and the assistant still answers.
GUARDRAIL_ID = os.environ.get("GUARDRAIL_ID", "")
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "")
