"""Search the policies, but only the documents this person's role may read."""

import re

from app import config, database, embeddings, search_index

# Phrases that ask for a version no longer in force. Deliberately narrow: "prior approval"
# or "before booking" are ordinary questions and must not pull superseded figures in.
OLD_VERSION = re.compile(
    r"\b(old|older|previous|former|outdated|superseded)\s+(\w+\s+){0,3}?(policy|policies|version|rules?|handbook)\b"
    r"|\bsuperseded\b|\blast year'?s\b|\bused to\b|\bprevious version\b",
    re.IGNORECASE,
)


def asks_for_old_version(question):
    """True for "the 2024 expense policy" or "the old time off rules". Any year before
    the current policy year counts."""
    years = [int(year) for year in re.findall(r"\b(20\d\d)\b", question)]
    if any(year < config.CURRENT_POLICY_YEAR for year in years):
        return True
    return bool(OLD_VERSION.search(question))


# Country names as people type them. Region codes match "region" in manifest.json.
REGIONS = {
    "uk": re.compile(r"\b(uk|u\.k\.|united kingdom|britain|british|england|london)\b", re.I),
    "de": re.compile(r"\b(germany|german|deutschland|berlin|munich)\b", re.I),
}
# "US" only in capitals, or "us" next to a place word, so the pronoun in "tell us" does not count.
US_CAPITALS = re.compile(r"\bUS\b|\bU\.S\.")
US_WORDS = re.compile(r"\busa\b|united states|\bamerica\b|\bus (employees?|office|staff|based)\b", re.I)


def regions_named(text):
    """Which countries a question names: "what about in the UK" -> ["uk"]."""
    found = [region for region, pattern in REGIONS.items() if pattern.search(text)]
    if US_CAPITALS.search(text) or US_WORDS.search(text):
        found.append("us")
    return found


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


def search_policies(question, role, old_version=False):
    """Return the policy chunks that answer the question, for this role.

    old_version (or a question that names an older year) adds the closest passages
    from superseded documents. They come from a search of their own, because the
    current version of the same policy is usually the nearer match and would push
    them out of a shared result list.
    """
    levels = allowed_access_levels(role)
    if not levels:
        return []

    old = old_version or asks_for_old_version(question)
    question_vector = embeddings.embed([question])[0]
    results = _current_matches(question, question_vector, levels)

    # A country named in the question gets that country's documents first. Wording
    # differs by country ("primary caregiver" in the US policy, "maternity pay" in the
    # UK one), so without this the right country's passage can miss the cut.
    regions = regions_named(question)
    if regions:
        local = _extra_matches(question_vector, levels, regions=regions)
        seen = {chunk["content"] for chunk in local}
        results = local + [chunk for chunk in results if chunk["content"] not in seen]

    if old:
        results += _extra_matches(question_vector, levels, statuses=["superseded"])
    return results


def _extra_matches(question_vector, levels, **filters):
    """The closest few passages under an extra filter (a country, or superseded only)."""
    hits = search_index.search(question_vector, levels, **filters)
    chunks = []
    for hit in hits[:3]:
        chunk = hit["_source"]
        chunk["similarity"] = round(similarity_from_score(hit["_score"]), 3)
        if chunk["similarity"] >= config.MIN_BEST_SIMILARITY:
            chunks.append(chunk)
    return chunks


def _current_matches(question, question_vector, levels):
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
