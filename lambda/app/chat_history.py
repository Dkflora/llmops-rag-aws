"""Save and load conversations, so chat history survives logging out.

The model remembers nothing between calls. The app keeps the history in Postgres
and sends it along with every new question.

Every query includes the employee's id, so nobody can open someone else's chat.
"""

from psycopg.types.json import Jsonb

from app import database


def start_conversation(employee_id, first_question):
    """Create a new conversation, named after its first question. Returns its id."""
    rows = database.query(
        "INSERT INTO conversations (employee_id, title) VALUES (%s, %s) RETURNING id",
        (employee_id, first_question[:60]),  # keep the title short for the sidebar
    )
    return rows[0]["id"]


def list_conversations(employee_id):
    """This employee's conversations, newest first (for the sidebar)."""
    return database.query(
        "SELECT id, title FROM conversations WHERE employee_id = %s ORDER BY id DESC",
        (employee_id,),
    )


def get_messages(conversation_id, employee_id):
    """All messages in a conversation, oldest first.

    The JOIN checks that the conversation belongs to this employee.
    If it doesn't, no messages come back.
    """
    return database.query(
        """
        SELECT m.role, m.content, m.sources
        FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
        WHERE m.conversation_id = %s AND c.employee_id = %s
        ORDER BY m.id
        """,
        (conversation_id, employee_id),
    )


def add_message(conversation_id, role, content, sources=None):
    """Save one message. role is "user" or "assistant".

    sources is the list of policy chunks shown under an answer, stored as JSON.
    """
    database.query(
        "INSERT INTO messages (conversation_id, role, content, sources) VALUES (%s, %s, %s, %s)",
        (conversation_id, role, content, Jsonb(sources or [])),
    )
