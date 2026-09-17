"""Search the policies, but only the documents this person's role may read."""

from app import config, database, embeddings, search_index


def allowed_access_levels(role):
    """Which access levels a role may read, from the role_access table."""
    rows = database.query(
        "SELECT access_level FROM role_access WHERE role = %s ORDER BY access_level",
        (role,),
    )
    return [row["access_level"] for row in rows]


def similarity_from_score(score):
    """Turn an OpenSearch inner-product score back into plain similarity (1.0 = same meaning).

    OpenSearch reports   score = 1 + similarity        when similarity >= 0
                         score = 1 / (1 - similarity)  when similarity < 0
    """
    if score >= 1:
        return score - 1
    return 1 - 1 / score


def search_policies(question, role):
    """Return the policy chunks that answer the question, for this role."""
    levels = allowed_access_levels(role)
    if not levels:
        return []

    question_vector = embeddings.embed([question])[0]
    hits = search_index.search(question_vector, levels)

    results = []
    for hit in hits:
        chunk = hit["_source"]
        chunk["similarity"] = round(similarity_from_score(hit["_score"]), 3)
        results.append(chunk)

    # Vector search always returns its closest chunks, even for "hello".
    # If even the best match is weak, this wasn't a policy question.
    if not results or results[0]["similarity"] < config.MIN_BEST_SIMILARITY:
        # Before giving up, try matching the words themselves. A question about
        # a code ("the L5 band", "my PTO", "NW-POL-010") is nearly invisible to
        # an embedding model and obvious to a keyword search. Measured here:
        # "What is the salary band for an L5 role?" scores 0.361, against 0.565
        # to 0.656 for questions phrased in ordinary words.
        return _keyword_fallback(question, levels)

    # Keep the best match, and any others that are nearly as good. The floor is
    # applied to every chunk, not only the best one: without that, a question
    # that only just clears the floor admits everything within the gap of it.
    best = results[0]["similarity"]
    cutoff = max(config.MIN_BEST_SIMILARITY, best - config.MAX_GAP_FROM_BEST)
    return [chunk for chunk in results if chunk["similarity"] >= cutoff]


def _keyword_fallback(question, levels):
    """Words rather than meaning, for when the vectors found nothing convincing."""
    hits = search_index.keyword_search(question, levels)
    if not hits:
        return []

    # BM25 scores are not similarities and the two are not comparable, so these
    # carry the floor value instead. Nothing downstream ranks them against a
    # vector result; they are only ever returned on their own.
    chunks = []
    for hit in hits:
        chunk = hit["_source"]
        chunk["similarity"] = config.MIN_BEST_SIMILARITY
        chunk["matched_by"] = "keyword"
        chunks.append(chunk)
    return chunks[: config.RESULTS_PER_SEARCH]
