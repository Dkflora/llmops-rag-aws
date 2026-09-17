"""Turn text into vectors with Amazon Titan Text Embeddings.

Questions and documents must always be embedded by the same model, and the search
index is built with the size from config.EMBEDDING_SIZE. Change the model and you
have to rebuild the index, because the old vectors are the wrong shape.
"""

import json
from functools import cache

from app import config


@cache
def bedrock():
    import boto3

    return boto3.client("bedrock-runtime", region_name=config.AWS_REGION)


def embed(texts):
    """Return one vector (a list of numbers) per text."""
    vectors = []
    for text in texts:  # Titan embeds one text per request
        response = bedrock().invoke_model(
            modelId=config.EMBEDDING_MODEL,
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "inputText": text,
                "dimensions": config.EMBEDDING_SIZE,
                "normalize": True,
            }),
        )
        vectors.append(json.loads(response["body"].read())["embedding"])
    return vectors
