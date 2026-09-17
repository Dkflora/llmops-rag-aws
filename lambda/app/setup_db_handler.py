"""Run once after `terraform apply`: tables, row-level security and demo data in Aurora.

    aws lambda invoke --function-name northwind-setup-db response.json

Safe to run twice: every statement in db/*.sql is written to be repeatable.
"""

from pathlib import Path

from app import config, database, secrets

DB_DIR = Path(__file__).parent.parent / "db"
SCRIPTS = ["01_schema.sql", "02_security.sql", "03_seed_data.sql"]


def handler(event, context):
    # Safe to run twice: if the tables already exist, change nothing
    rows = database.run_admin_query("SELECT to_regclass('public.employees') IS NOT NULL AS ready")
    exists = rows[0]["ready"]

    if exists:
        print("tables already exist, skipping the SQL scripts")
    else:
        for name in SCRIPTS:
            database.run_admin_script((DB_DIR / name).read_text(encoding="utf-8"))
            print(f"ran {name}")

    # The app user's real password lives in Secrets Manager, never in a SQL file
    app_password = secrets.read_secret(config.DB_APP_SECRET_ARN)["password"]
    database.set_app_user_password(app_password)
    print("set the hr_app password from Secrets Manager")

    employees = database.run_admin_query("SELECT count(*) AS n FROM employees")[0]["n"]
    print(f"{employees} employees in the database")
    return {"employees": employees, "scripts_ran": not exists}
