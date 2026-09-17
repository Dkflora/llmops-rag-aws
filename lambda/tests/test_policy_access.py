"""Which policy text each role can retrieve from OpenSearch.

Needs the index built by the ingest function, and a reachable database.
See "Run the tests" in the README.
"""

from app import retrieval


def titles(results):
    return {result["title"] for result in results}


def test_score_conversion():
    assert retrieval.similarity_from_score(1.75) == 0.75
    assert retrieval.similarity_from_score(1.0) == 0.0
    assert retrieval.similarity_from_score(0.5) == -1.0


def test_role_access_comes_from_the_database():
    assert retrieval.allowed_access_levels("employee") == ["general"]
    assert retrieval.allowed_access_levels("hacker") == []


def test_employee_never_gets_restricted_text():
    results = retrieval.search_policies("What is the salary band for an L5 role?", "employee")
    assert all(result["access_level"] == "general" for result in results)


def test_hr_can_read_compensation_bands():
    results = retrieval.search_policies("What is the salary band for an L5 role?", "hr")
    assert "Compensation Bands 2026" in titles(results)


def test_superseded_policy_is_never_returned():
    results = retrieval.search_policies("What is the mileage reimbursement rate?", "exec")
    assert results
    assert all(result["filename"] != "expense_policy_2024.pdf" for result in results)


def test_small_talk_finds_nothing():
    for text in ["hello there", "thanks!", "ok", "tell me a joke"]:
        assert retrieval.search_policies(text, "exec") == [], text


def test_only_relevant_documents_come_back():
    results = retrieval.search_policies("How many vacation days can I carry over?", "exec")
    assert titles(results) == {"Time Off and Leave Policy"}
