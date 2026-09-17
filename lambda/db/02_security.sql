-- Row-level security: the database itself decides whose employee records a query can see.
--
-- The application connects as hr_app. For that user, the employees table only contains
-- the rows the policy below allows for the person asking:
--
--     everyone   their own record
--     manager    plus their direct reports
--     hr         everyone
--
-- The app says who is asking at the start of each query:  set_config('app.viewer_id', ...)
-- If it forgets, current_viewer() is empty and the table looks empty. It fails closed.

-- The application's database user. setup_db replaces this password with one from Secrets Manager.
CREATE ROLE hr_app LOGIN PASSWORD 'hr_app_local_only';

GRANT SELECT ON employees, role_access TO hr_app;
GRANT SELECT, INSERT ON conversations, messages TO hr_app;
GRANT INSERT ON request_log, employee_lookup_log TO hr_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO hr_app;

-- Who is asking, as set by the app for this transaction
CREATE FUNCTION current_viewer() RETURNS text
LANGUAGE sql STABLE
AS $$ SELECT current_setting('app.viewer_id', true) $$;

-- Is the person asking in HR? This function runs as the table owner, so it can read
-- the asker's own role. The app can't claim a role: the database looks it up.
CREATE FUNCTION viewer_is_hr() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM employees
        WHERE employee_id = current_setting('app.viewer_id', true) AND role = 'hr'
    )
$$;

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

CREATE POLICY employees_visible_to_viewer ON employees
    FOR SELECT TO hr_app
    USING (
        employee_id = current_viewer()     -- your own record
        OR manager_id = current_viewer()   -- people who report to you
        OR viewer_is_hr()                  -- HR sees everyone
    );

-- Signing in happens before we know who is asking, so the policy would hide everyone.
-- This function returns one person's basic profile by email: no salary, no time off.
CREATE FUNCTION employee_by_email(p_email text)
RETURNS TABLE (employee_id text, full_name text, role text, department text, job_title text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT e.employee_id, e.full_name, e.role, e.department, e.job_title
    FROM employees e
    WHERE e.email = lower(p_email)
$$;

-- A manager's name is not secret, even when their salary is
CREATE FUNCTION employee_name(p_employee_id text) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT e.full_name FROM employees e WHERE e.employee_id = p_employee_id $$;

REVOKE ALL ON FUNCTION viewer_is_hr(), employee_by_email(text), employee_name(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION current_viewer(), viewer_is_hr(), employee_by_email(text), employee_name(text) TO hr_app;
