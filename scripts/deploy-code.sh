#!/usr/bin/env bash
#
# Push build/function.zip to all four Lambda functions.
#
# Use this every time you change the Python. It replaces only the code, so environment
# variables, the layer, the VPC settings and the IAM role stay exactly as they are.
#
#   bash scripts/build-function.sh
#   bash scripts/deploy-code.sh                  # northwind-hr-* in us-east-1
#   bash scripts/deploy-code.sh my-hr eu-west-1  # a different prefix and region
#
# The console equivalent is: Lambda > the function > Code > Upload from > .zip file,
# once per function. This script is the same four uploads in one command.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT=${1:-northwind-hr}
REGION=${2:-us-east-1}
ZIP=build/function.zip

if [ ! -f "$ZIP" ]; then
  echo "$ZIP is missing. Run: bash scripts/build-function.sh" >&2
  exit 1
fi

for name in chat ingest setup-db evaluate; do
  printf '%-28s ' "$PROJECT-$name"
  aws lambda update-function-code \
    --function-name "$PROJECT-$name" \
    --zip-file "fileb://$ZIP" \
    --region "$REGION" \
    --query 'LastUpdateStatus' \
    --output text
done

echo
echo "Wait for all four to report Successful, then re-run the evaluation:"
echo "  aws lambda invoke --function-name $PROJECT-evaluate --cli-read-timeout 900 /tmp/eval.json"
