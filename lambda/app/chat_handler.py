"""The chat API: one Lambda function behind Amazon API Gateway.

API Gateway checks the Cognito token BEFORE this code runs. A request without a
valid token never reaches us. API Gateway then passes the token's claims in the
event, so the signed-in email comes from there: never from the request body,
never from a header the browser could fake.

Routes (defined in terraform/api_gateway.tf):

    GET  /api/health                             no sign-in needed
    GET  /api/me                                 who is signed in
    GET  /api/conversations                      their chats
    GET  /api/conversations/{id}/messages        one chat, if it's theirs
    POST /api/chat                               ask a question
"""

import base64
import json

from botocore.exceptions import BotoCoreError, ClientError

from app import assistant, chat_history, employees


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def signed_in_email(event):
    """The email from the verified Cognito token, as API Gateway passed it."""
    claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
    return claims.get("email")


def read_body(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    return json.loads(body)


def source_names(sources):
    names = set()
    for source in sources:
        names.add(f"{source['title']}, {source['section']}")
    return sorted(names)


def handler(event, context):
    route = event.get("routeKey", "")

    if route == "GET /api/health":
        return respond(200, {"status": "ok"})

    email = signed_in_email(event)
    if not email:
        return respond(401, {"detail": "Sign in first."})

    employee = employees.find_by_email(email)
    if employee is None:
        detail = "You don't have an HR assistant account. Contact People Operations."
        return respond(403, {"detail": detail})

    if route == "GET /api/me":
        return respond(200, employee)

    if route == "GET /api/conversations":
        return respond(200, chat_history.list_conversations(employee["employee_id"]))

    if route == "GET /api/conversations/{id}/messages":
        return get_messages(event, employee)

    if route == "POST /api/chat":
        return chat(event, employee)

    return respond(404, {"detail": "Not found."})


def get_messages(event, employee):
    try:
        conversation_id = int((event.get("pathParameters") or {}).get("id", ""))
    except ValueError:
        return respond(404, {"detail": "Conversation not found."})

    rows = chat_history.get_messages(conversation_id, employee["employee_id"])
    if not rows:
        # Someone else's chat looks exactly like a chat that doesn't exist
        return respond(404, {"detail": "Conversation not found."})
    for row in rows:
        row["sources"] = source_names(row["sources"])
    return respond(200, rows)


def chat(event, employee):
    try:
        body = read_body(event)
    except (ValueError, UnicodeDecodeError):
        return respond(400, {"detail": "The request wasn't valid JSON."})

    question = str(body.get("question") or "").strip()
    if not question:
        return respond(400, {"detail": "Type a question first."})

    conversation_id = body.get("conversation_id")
    history = []
    if conversation_id is not None:
        history = chat_history.get_messages(conversation_id, employee["employee_id"])
        if not history:
            return respond(404, {"detail": "Conversation not found."})

    try:
        answer, sources = assistant.answer(question, history, employee)
    except (BotoCoreError, ClientError) as error:
        print(f"assistant unavailable: {error!r}")  # goes to CloudWatch Logs
        detail = "The assistant is unavailable right now. Try again in a moment."
        return respond(502, {"detail": detail})

    if conversation_id is None:
        conversation_id = chat_history.start_conversation(employee["employee_id"], question)
    chat_history.add_message(conversation_id, "user", question)
    chat_history.add_message(conversation_id, "assistant", answer, sources)

    return respond(200, {
        "conversation_id": conversation_id,
        "answer": answer,
        "sources": source_names(sources),
    })
