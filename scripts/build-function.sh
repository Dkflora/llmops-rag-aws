#!/usr/bin/env bash
#
# Build the function zip: our own code, and nothing else.
#
# All four Lambda functions run this same zip. They differ only in which handler
# they are configured to call:
#
#   app.chat_handler.handler       answer a question
#   app.ingest_handler.handler     load, chunk, embed, store
#   app.setup_db_handler.handler   create the tables and the security rules
#   app.evaluate_handler.handler   score the assistant
#
#   bash scripts/build-function.sh
#
# Produces build/function.zip (~60 KB). Small, because the libraries live in the layer.

set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON=${PYTHON:-python}
BUILD_DIR=build
mkdir -p "$BUILD_DIR"
rm -f "$BUILD_DIR/function.zip"

# What goes in, and where it lands inside the zip. Lambda imports from the zip root,
# so "app" must be a top-level folder in the archive: app/chat_handler.py, not
# lambda/app/chat_handler.py. Getting this wrong is the "Unable to import module" error.
"$PYTHON" - "$BUILD_DIR/function.zip" <<'PY'
import os, sys, zipfile

SOURCES = [
    ("lambda/app", "app"),                    # the application
    ("lambda/db", "db"),                      # SQL the setup function runs
    ("lambda/data/evaluation_questions.json", "data/evaluation_questions.json"),
]

SKIP_DIRS = {"__pycache__", ".pytest_cache"}
SKIP_SUFFIXES = (".pyc", ".pyo")

target = sys.argv[1]
count = 0

with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for source, prefix in SOURCES:
        if os.path.isfile(source):
            archive.write(source, prefix)
            count += 1
            continue
        for folder, dirs, files in os.walk(source):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in files:
                if name.endswith(SKIP_SUFFIXES):
                    continue
                full = os.path.join(folder, name)
                inside = os.path.join(prefix, os.path.relpath(full, source))
                archive.write(full, inside.replace(os.sep, "/"))
                count += 1

print(f"{count} files")
PY

SIZE_KB=$("$PYTHON" -c "import os;print(round(os.path.getsize('$BUILD_DIR/function.zip')/1024))")

echo
echo "build/function.zip   ${SIZE_KB} KB"
echo
echo "Check the layout before you upload (app/ must be at the top):"
echo "  python -c \"import zipfile;print(zipfile.ZipFile('build/function.zip').namelist()[:5])\""
