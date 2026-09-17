"""Store and search policy chunks in Amazon OpenSearch Serverless.

The project this grew out of stored its chunks in pgvector, inside a Postgres
container that held nothing else: no employee records, no identity, one datastore.
The assistant answered from policy documents and said plainly that it could not see
anyone's personal record.

Two things change here, and it is worth keeping them apart:

  - The chunks move to OpenSearch Serverless, which is this file.
  - Employee records arrive for the first time, in Aurora, behind row-level
    security. That is new work, not a migration of something that existed.

Both are protected, and not in the same way, which is the reason they sit in
different services. A policy document carries one access level for the whole
document, and that filter is applied inside the vector search. An employee record
is protected row by row, by a rule Postgres evaluates from the org chart. One
coarse label on a chunk, one per row policy in the database: neither mechanism
substitutes for the other.

Two more things worth knowing about this file:

  - A NextGen OpenSearch Serverless collection chooses the vector engine itself.
    Our vectors are normalized, so "inner product" gives the same ranking as cosine
    similarity, and the collection scales to zero OCUs when nobody is asking anything.
  - Every request is signed with the Lambda's IAM role ("aoss" is OpenSearch
    Serverless). There is no password.
"""

import time
from functools import cache

from opensearchpy import AWSV4SignerAuth, OpenSearch, RequestsHttpConnection, helpers
from opensearchpy.exceptions import RequestError

from app import config


@cache
def client():
    import boto3

    credentials = boto3.Session().get_credentials()
    auth = AWSV4SignerAuth(credentials, config.AWS_REGION, "aoss")
    return OpenSearch(
        hosts=[config.SEARCH_URL],
        http_auth=auth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=60,
    )


def vector_field():
    """How the 1024 numbers from Titan are stored and compared.

    NextGen OpenSearch Serverless collections take space_type at the top level and pick
    the engine themselves. The local OpenSearch container still wants the old form, where
    you name the algorithm (hnsw) and the engine (faiss) yourself. Sending the old form to
    a NextGen collection is ignored at best, so the two cases are kept apart here.

    "innerproduct" rather than "cosinesimil" because our vectors are already normalized to
    length 1, and for unit vectors the two give the same ranking, with less arithmetic.
    """
    field = {
        "type": "knn_vector",
        "dimension": config.EMBEDDING_SIZE,
        "space_type": "innerproduct",
    }

    # Serverless collections choose the vector engine themselves, so no method
    # is specified here.
    return field


INDEX_BODY = {
    "settings": {"index": {"knn": True}},
    "mappings": {
        "properties": {
            "embedding": vector_field(),
            "access_level": {"type": "keyword"},  # general, manager_only, hr_only, exec_only
            "status": {"type": "keyword"},        # current or superseded
            "title": {"type": "keyword"},
            "section": {"type": "keyword"},
            "filename": {"type": "keyword"},
            "content": {"type": "text"},
        }
    },
}


def create_index():
    """Delete the policy index if it exists, and create it again, empty."""
    if client().indices.exists(index=config.POLICY_INDEX):
        client().indices.delete(index=config.POLICY_INDEX)

    # OpenSearch Serverless can take a few seconds to finish deleting, so retry the create
    for attempt in range(20):
        try:
            client().indices.create(index=config.POLICY_INDEX, body=INDEX_BODY)
            return
        except RequestError as error:
            if "already_exists" not in str(error):
                raise
            time.sleep(3)
    raise RuntimeError("The old index was still being deleted. Run ingestion again in a minute.")


def add_chunks(chunks):
    """Store a list of chunks in one request."""
    actions = [{"_index": config.POLICY_INDEX, "_source": chunk} for chunk in chunks]
    helpers.bulk(client(), actions)
    # OpenSearch Serverless makes new chunks searchable by itself, usually
    # within a minute. There is no refresh call to force it, so a search run
    # straight after an ingest can come back short.


def search(vector, access_levels):
    """Find the closest chunks among current documents this person may read.

    The filter runs inside the vector search, so restricted text is never returned.
    """
    response = client().search(
        index=config.POLICY_INDEX,
        body={
            "size": config.RESULTS_PER_SEARCH,
            "_source": {"excludes": ["embedding"]},
            "query": {
                "knn": {
                    "embedding": {
                        "vector": vector,
                        "k": config.RESULTS_PER_SEARCH,
                        "filter": {
                            "bool": {
                                "filter": [
                                    {"terms": {"access_level": access_levels}},
                                    {"term": {"status": "current"}},
                                ]
                            }
                        },
                    }
                }
            },
        },
    )
    return response["hits"]["hits"]


def keyword_search(text, access_levels):
    """Match the words themselves, for the questions vectors are bad at.

    An embedding model has almost nothing to work with in a code: "L5", "PTO",
    "401k", "NW-POL-010". They are tokens, not meaning, so a question about one
    scores barely above small talk. BM25 matches them exactly.

    The access filter is repeated here, and that is the important line in this
    function. A keyword search without it would be a second way into the index
    with no lock on it, returning hr_only text to anyone who typed the right
    word. Two searches, one access rule.
    """
    response = client().search(
        index=config.POLICY_INDEX,
        body={
            "size": config.RESULTS_PER_SEARCH,
            "_source": {"excludes": ["embedding"]},
            "query": {
                "bool": {
                    "must": [{"match": {"content": text}}],
                    "filter": [
                        {"terms": {"access_level": access_levels}},
                        {"term": {"status": "current"}},
                    ],
                }
            },
        },
    )
    return response["hits"]["hits"]
