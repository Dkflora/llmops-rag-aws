"""The ingestion Lambda: load -> chunk -> embed -> store, for every policy file.

When it runs (set up in terraform/ingestion_triggers.tf):
  - whenever manifest.json is uploaded to the documents bucket
    (upload the documents first, then the manifest, so it runs once)
  - once a day, on a schedule

From your machine:  python -m app.ingest_handler   (reads the data/documents folder)

The order here matters. Everything that can be checked for free is checked
before anything is embedded or written:

  1. the manifest agrees with the folder, and every label is one we recognise
  2. every document produces at least one chunk
  3. only then is the old index dropped and rebuilt

A failure in step 1 or 2 leaves the running index exactly as it was, so a bad
upload cannot take policy search down while somebody works out what went wrong.
"""

import json
from pathlib import Path

from app import chunking, config, documents, embeddings, search_index

# The four labels the retrieval filter understands. A typo here is worse than a
# crash: "hr-only" instead of "hr_only" would quietly make a restricted document
# readable by everyone.
ACCESS_LEVELS = {"general", "manager_only", "hr_only", "exec_only"}
STATUSES = {"current", "superseded"}

# The fields ingestion actually reads. The manifest carries more than this, and
# the extra fields are left alone.
REQUIRED_FIELDS = {"filename", "title", "access_level", "status"}


class IngestionError(RuntimeError):
    """Ingestion refused to run. The message lists every problem found, not just the first."""


def download_documents(target_dir):
    """Copy every file from the S3 documents bucket into a folder (Lambda can write to /tmp)."""
    import boto3

    s3 = boto3.client("s3", region_name=config.AWS_REGION)
    target_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=config.DOCUMENTS_BUCKET):
        for item in page.get("Contents", []):
            filename = Path(item["Key"]).name
            s3.download_file(config.DOCUMENTS_BUCKET, item["Key"], str(target_dir / filename))
            count += 1
    print(f"downloaded {count} files from s3://{config.DOCUMENTS_BUCKET}")


def load_manifest(documents_dir):
    """Read manifest.json and check it against the folder, before anything is spent.

    A document in the folder but not in the manifest is never indexed, and
    nothing downstream ever complains: questions about it simply come back
    "not found". A document in the manifest but not in the folder fails later,
    part way through a rebuild. Both are cheaper to catch here.
    """
    manifest_path = documents_dir / "manifest.json"
    if not manifest_path.exists():
        raise IngestionError(f"{manifest_path} does not exist, so there is nothing to ingest")

    entries = json.loads(manifest_path.read_text(encoding="utf-8"))
    problems = []
    listed = set()

    for entry in entries:
        filename = entry.get("filename", "<missing filename>")
        listed.add(filename)

        missing = REQUIRED_FIELDS - set(entry)
        if missing:
            problems.append(f"{filename}: manifest entry is missing {sorted(missing)}")

        access_level = entry.get("access_level")
        if access_level not in ACCESS_LEVELS:
            problems.append(
                f"{filename}: access_level is {access_level!r}, expected one of "
                f"{sorted(ACCESS_LEVELS)}"
            )

        status = entry.get("status")
        if status not in STATUSES:
            problems.append(f"{filename}: status is {status!r}, expected one of {sorted(STATUSES)}")

        if not (documents_dir / filename).exists():
            problems.append(f"{filename}: listed in the manifest but not in the folder")

    on_disk = {p.name for p in documents_dir.iterdir() if p.name != "manifest.json"}
    for orphan in sorted(on_disk - listed):
        problems.append(
            f"{orphan}: in the folder but not in the manifest, so it will never be searchable"
        )

    if problems:
        raise IngestionError(
            "manifest.json does not match the documents:\n  " + "\n  ".join(problems)
        )
    return entries


def build_chunks(documents_dir, entries):
    """Read and chunk every document, and refuse to lose one.

    A document that yields zero chunks is in the manifest, in the bucket, and
    invisible to search. Nothing downstream will ever complain about it. Fail
    here instead, before a single embedding is paid for, where the cause is
    still obvious.
    """
    per_document = []
    empty = []

    for entry in entries:
        path = documents_dir / entry["filename"]
        try:
            sections = documents.read_document(path)
        except Exception as error:
            raise IngestionError(
                f"{entry['filename']}: could not be read: {type(error).__name__}: {error}"
            ) from error

        chunks = chunking.chunk_sections(sections)
        per_document.append((entry, chunks))

        if not chunks:
            empty.append(entry["filename"])

        print(
            f"  {entry['filename']:42} {entry['access_level']:13} "
            f"{len(sections):3} sections {len(chunks):3} chunks"
        )

    if empty:
        raise IngestionError(
            "These documents produced no chunks and would be silently unsearchable:\n  "
            + "\n  ".join(empty)
            + "\n\nUsually the reader found no text: check the headings, or the extension."
        )
    return per_document


def ingest(documents_dir):
    """Rebuild the policy index from a folder of documents. Returns a short summary."""
    print(f"Reading {documents_dir}")

    # Labels such as access_level come from the manifest, not from the files
    entries = load_manifest(documents_dir)
    per_document = build_chunks(documents_dir, entries)
    total_chunks = sum(len(chunks) for _, chunks in per_document)
    print(f"\n{len(entries)} documents -> {total_chunks} chunks")

    # Nothing has been dropped, so it is safe to replace the index. Dropping it
    # any earlier would mean a bad manifest takes policy search down before the
    # run fails.
    print("Rebuilding the index ...")
    search_index.create_index()
    total = 0

    for entry, chunks in per_document:
        texts = [f"{entry['title']} - {chunk['section']}\n{chunk['content']}" for chunk in chunks]
        vectors = embeddings.embed(texts)                                      # 3. embed

        for chunk, vector in zip(chunks, vectors):
            chunk.update(
                title=entry["title"],
                filename=entry["filename"],
                access_level=entry["access_level"],
                status=entry["status"],
                embedding=vector,
            )
        search_index.add_chunks(chunks)                                        # 4. store
        total += len(chunks)

    current = sum(1 for e in entries if e["status"] == "current")
    summary = {"documents": len(entries), "chunks": total}
    print(
        f"{summary['documents']} documents, {summary['chunks']} chunks indexed "
        f"({current} current, {len(entries) - current} superseded and excluded from search)"
    )
    return summary


def handler(event, context):
    """AWS entry point: download from S3, then rebuild the index."""
    documents_dir = Path("/tmp/documents")
    download_documents(documents_dir)
    return ingest(documents_dir)


if __name__ == "__main__":
    ingest(config.DOCUMENTS_DIR)
