#!/usr/bin/env bash
#
# Build the Lambda layer: every library the app imports that Lambda does not already have.
#
# Why a layer and not one big zip? The libraries are ~114 MB unpacked and almost never
# change. The application code is ~100 KB and changes every time you edit a file. Keeping
# them apart means a code change uploads 100 KB, not 114 MB.
#
# Why --platform manylinux2014_x86_64? Lambda runs Linux. psycopg and lxml ship compiled
# code, and the Windows or macOS build of them will not run there. These flags tell pip to
# download the Linux wheels whatever machine you are on, so you do not need Docker.
#
#   bash scripts/build-layer.sh
#
# Produces build/layer.zip (~33 MB).

set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON=${PYTHON:-python}   # override if "python" is not your Python 3: PYTHON=python3 bash scripts/build-layer.sh
PYTHON_VERSION=3.12   # must match the runtime in infra/terraform/lambda.tf and the console steps
BUILD_DIR=build
STAGE_DIR="$BUILD_DIR/layer"

# Lambda unzips a layer into /opt. It only adds /opt/python to the import path,
# so every library has to sit inside a folder literally called "python".
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/python"

echo "Downloading Linux wheels for Python $PYTHON_VERSION ..."
"$PYTHON" -m pip install \
  --quiet \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version "$PYTHON_VERSION" \
  --only-binary=:all: \
  --target "$STAGE_DIR/python" \
  -r lambda/requirements.txt

# The Python runtime already includes boto3 and botocore (~27 MB). Shipping our own copy
# would waste most of the layer's size limit and can pin an older version than the runtime.
echo "Removing boto3/botocore (the Lambda runtime provides them) ..."
rm -rf "$STAGE_DIR"/python/boto3 "$STAGE_DIR"/python/botocore "$STAGE_DIR"/python/s3transfer
rm -rf "$STAGE_DIR"/python/boto3-*.dist-info "$STAGE_DIR"/python/botocore-*.dist-info

# Compiled caches and bundled test suites are dead weight inside a Lambda.
find "$STAGE_DIR/python" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGE_DIR/python" -type d -name "tests" -prune -exec rm -rf {} + 2>/dev/null || true

echo "Zipping ..."
rm -f "$BUILD_DIR/layer.zip"
"$PYTHON" - "$STAGE_DIR" "$BUILD_DIR/layer.zip" <<'PY'
import os, sys, zipfile

stage, target = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for folder, _, files in os.walk(stage):
        for name in files:
            full = os.path.join(folder, name)
            # Zip entries always use forward slashes, whatever the machine building them
            archive.write(full, os.path.relpath(full, stage).replace(os.sep, "/"))
PY

SIZE_MB=$("$PYTHON" -c "import os;print(round(os.path.getsize('$BUILD_DIR/layer.zip')/1048576,1))")
UNZIPPED_MB=$("$PYTHON" -c "
import os
total = sum(os.path.getsize(os.path.join(d, f))
            for d, _, fs in os.walk('$STAGE_DIR') for f in fs)
print(round(total / 1048576, 1))
")

echo
echo "build/layer.zip   ${SIZE_MB} MB zipped, ${UNZIPPED_MB} MB unzipped"
echo
echo "Lambda's limits: 50 MB for a direct console upload, 250 MB unzipped for the"
echo "function and all its layers together. If the zip ever grows past 50 MB, upload"
echo "it to S3 first and point the layer at the object instead."
