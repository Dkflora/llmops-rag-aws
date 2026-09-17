"""Find the signed-in employee, and read the employee records they may see.

Notice what's missing from visible_records(): there is no WHERE clause.
Row-level security in Aurora (db/02_security.sql) removes every row this person
may not see:

    everyone   sees their own record
    manager    also sees their direct reports
    hr         sees everyone

Even a bug in this file, or a clever question to the model, can't widen that:
the database never returns the rows.
"""

from app import database


def find_by_email(email):
    """Return the employee with this email, or None.

    Signing in happens before we know who is asking, so row-level security would
    hide everyone. employee_by_email() is a database function that returns just
    one person's basic profile: no salary.
    """
    email = (email or "").strip().strip("`'\"<>").lower()
    if not email:
        return None
    rows = database.query("SELECT * FROM employee_by_email(%s)", (email,))
    return rows[0] if rows else None


def visible_records(viewer):
    """Every employee record the viewer may see. Each lookup is written to the audit log."""
    rows = database.query(
        """
        SELECT employee_id, full_name, job_title, job_level, department, location, hire_date,
               employee_name(manager_id) AS manager,
               base_salary, bonus_target_percent, pto_days_remaining
        FROM employees
        ORDER BY full_name
        """,
        viewer_id=viewer["employee_id"],  # row-level security uses this
    )

    database.query(
        "INSERT INTO employee_lookup_log (viewer_id, returned_ids) VALUES (%s, %s)",
        (viewer["employee_id"], [row["employee_id"] for row in rows]),
    )
    return rows
