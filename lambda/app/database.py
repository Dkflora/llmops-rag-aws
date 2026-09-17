"""Talk to PostgreSQL: Aurora Serverless v2.

Row-level security
------------------
Employee records are new in this system: the project this grew out of held no
personal data at all. So there is no old WHERE clause being replaced here. The
database decides from the start. Before a query that reads employee records,
we tell Postgres who is asking:

    SELECT set_config('app.viewer_id', 'NW-1005', true)

The policy in db/02_security.sql then hides every row that person may not see.
Forget to say who is asking, and the query simply returns nothing.
"""

from urllib.parse import quote

import psycopg
from psycopg import sql
from psycopg.rows import dict_row

from app import config, secrets


def connection_url(admin=False):
    """The app connects as hr_app (row-level security applies). Setup connects as the admin user.

    On Lambda the passwords come from Secrets Manager. DATABASE_URL overrides
    that, which is how the tests reach Aurora from your own machine.
    """
    override = config.DATABASE_ADMIN_URL if admin else config.DATABASE_URL
    if override:
        return override

    secret = secrets.read_secret(config.DB_ADMIN_SECRET_ARN if admin else config.DB_APP_SECRET_ARN)
    user = quote(secret["username"], safe="")
    password = quote(secret["password"], safe="")  # protects passwords containing @ : / #
    # connect_timeout is generous: Aurora Serverless can take a few seconds to wake up from zero
    host = config.DB_HOST
    name = config.DB_NAME
    # connect_timeout is generous: Aurora Serverless can take a few seconds to wake from zero.
    options = "sslmode=require&connect_timeout=25"
    return f"postgresql://{user}:{password}@{host}:5432/{name}?{options}"


def query(statement, params=None, viewer_id=None):
    """Run one SQL statement as the app user and return its rows as dictionaries.

    viewer_id  the employee_id of the person asking. Row-level security uses it.
    """
    with psycopg.connect(connection_url(), row_factory=dict_row) as connection:
        if viewer_id is not None:
            # true = only for this transaction, so it can never leak into another request
            connection.execute("SELECT set_config('app.viewer_id', %s, true)", (viewer_id,))
        cursor = connection.execute(statement, params)
        return cursor.fetchall() if cursor.description else []


def run_admin_script(script):
    """Run a whole SQL file as the admin user. Only the setup function does this."""
    with psycopg.connect(connection_url(admin=True)) as connection:
        connection.execute(script)


def run_admin_query(statement, params=None):
    """Run one SQL statement as the admin user and return its rows."""
    with psycopg.connect(connection_url(admin=True), row_factory=dict_row) as connection:
        cursor = connection.execute(statement, params)
        return cursor.fetchall() if cursor.description else []


def set_app_user_password(password):
    """Give hr_app its real password from Secrets Manager.

    ALTER ROLE can't take a normal %s parameter, so psycopg quotes the value safely instead.
    """
    statement = sql.SQL("ALTER ROLE hr_app WITH PASSWORD {}").format(sql.Literal(password))
    with psycopg.connect(connection_url(admin=True)) as connection:
        connection.execute(statement)
