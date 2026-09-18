"""Evaluation, inside AWS: ask questions with known answers and score the assistant.

    aws lambda invoke --function-name northwind-evaluate response.json
    aws lambda invoke --function-name northwind-evaluate \
        --cli-binary-format raw-in-base64-out --payload '{"similarity_report": true}' response.json

Run it after every change to the prompt, the thresholds, the chunking or the model.
The similarity report prints the scores you need to set MIN_BEST_SIMILARITY for Titan.
"""

import json

from app import assistant, config, embeddings, employees, retrieval, search_index

QUESTIONS_FILE = config.DATA_DIR / "evaluation_questions.json"

SMALL_TALK = ["hello there", "thanks!", "ok", "tell me a joke"]
REAL_QUESTIONS = [
    "How many vacation days can I carry over?",
    "What is the mileage reimbursement rate?",
    "Can I work from another country?",
    "What is the salary band for an L5 role?",
]


def normalize(text):
    return text.lower().replace(",", "").replace("$", "").replace("*", "")


def check(case, answer, sources):
    problems = []
    text = normalize(answer)
    for fact in case.get("must_include", []):
        if normalize(fact) not in text:
            problems.append(f"missing '{fact}'")
    for fact in case.get("must_not_include", []):
        if normalize(fact) in text:
            problems.append(f"leaked '{fact}'")
    if case.get("source") and case["source"] not in {source["title"] for source in sources}:
        problems.append(f"didn't use '{case['source']}'")
    return problems


def run_evaluation(only=""):
    cases = json.loads(QUESTIONS_FILE.read_text(encoding="utf-8"))
    # {"only": "meal"} re-runs just the questions containing that word
    if only:
        cases = [case for case in cases if only.lower() in case["question"].lower()]
    results = []
    for case in cases:
        employee = employees.find_by_email(case["email"])
        # "history" replays earlier turns, so follow-ups are tested the way people ask them
        answer, sources = assistant.answer(case["question"], case.get("history", []), employee)
        problems = check(case, answer, sources)
        results.append({
            "who": employee["full_name"],
            "question": case["question"],
            "problems": problems,
            # So a failure can be read without re-asking the question
            "answer": answer,
            "sources": sorted({source["title"] for source in sources}),
        })

        status = "PASS" if not problems else "FAIL"
        reason = "; ".join(problems)
        name = employee["full_name"]
        short_question = case["question"][:52]
        print(f"{status}  {name:15} {short_question:52}  {reason}")

    passed = 0
    failures = []
    for result in results:
        if result["problems"]:
            failures.append(result)
        else:
            passed += 1

    print(f"\n{passed} of {len(results)} passed")
    return {"passed": passed, "total": len(results), "failures": failures}


def similarity_report():
    """Score small talk and real questions, so the relevance floor can be measured.

    Every access level is allowed here, because this is about how close the
    question is to the text, not about who may read it.
    """
    levels = ["general", "manager_only", "hr_only", "exec_only"]
    groups = {"small_talk": SMALL_TALK, "real_questions": REAL_QUESTIONS}
    report = {}

    for label, questions in groups.items():
        scores = {}
        for question in questions:
            question_vector = embeddings.embed([question])[0]
            hits = search_index.search(question_vector, levels)
            if hits:
                best = round(retrieval.similarity_from_score(hits[0]["_score"]), 3)
            else:
                best = None
            scores[question] = best
            print(f"{label:15} {best}  {question}")
        report[label] = scores

    print("Set MIN_BEST_SIMILARITY between the highest small-talk score")
    print("and the lowest real-question score.")
    return report


def search_probe(query, old_version=False):
    """What retrieval returns for one query, to see why an answer went wrong.

        --payload '{"search": "2024 PTO carryover", "old_version": true}'
    """
    chunks = retrieval.search_policies(query, "employee", old_version=old_version)
    return [
        {key: chunk.get(key) for key in ("title", "section", "version", "status", "similarity")}
        for chunk in chunks
    ]


def handler(event, context):
    if (event or {}).get("search"):
        return search_probe(event["search"], event.get("old_version", False))
    if (event or {}).get("similarity_report"):
        return similarity_report()
    return run_evaluation((event or {}).get("only", ""))


if __name__ == "__main__":
    result = run_evaluation()
    raise SystemExit(0 if result["passed"] == result["total"] else 1)
