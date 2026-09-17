-- The tables. Run first: by the Postgres container locally, by the setup Lambda on Aurora.
-- Policy text and vectors live in OpenSearch Serverless. Everything else lives here.

-- Who works here and what they are paid. No passwords: Cognito handles sign-in.
CREATE TABLE employees (
    employee_id          TEXT PRIMARY KEY,
    email                TEXT NOT NULL UNIQUE,
    full_name            TEXT NOT NULL,
    role                 TEXT NOT NULL,          -- employee, manager, hr or exec
    department           TEXT NOT NULL,
    job_title            TEXT NOT NULL,
    job_level            TEXT NOT NULL,          -- L1 to L8
    manager_id           TEXT REFERENCES employees (employee_id),
    location             TEXT NOT NULL,
    hire_date            DATE NOT NULL,
    base_salary          INTEGER NOT NULL,
    bonus_target_percent INTEGER NOT NULL,
    pto_days_remaining   NUMERIC(4, 1) NOT NULL
);

-- Which policy documents each role may read
CREATE TABLE role_access (
    role         TEXT NOT NULL,
    access_level TEXT NOT NULL,                  -- general, manager_only, hr_only or exec_only
    PRIMARY KEY (role, access_level)
);

-- Chat history: one conversation has many messages
CREATE TABLE conversations (
    id          BIGSERIAL PRIMARY KEY,
    employee_id TEXT NOT NULL REFERENCES employees (employee_id),
    title       TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE messages (
    id              BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    role            TEXT NOT NULL,               -- user or assistant
    content         TEXT NOT NULL,
    sources         JSONB NOT NULL DEFAULT '[]',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Request log: one row per question, to monitor speed, cost and tool use
CREATE TABLE request_log (
    id            BIGSERIAL PRIMARY KEY,
    employee_id   TEXT NOT NULL REFERENCES employees (employee_id),
    question      TEXT NOT NULL,
    tools_used    TEXT[] NOT NULL,
    input_tokens  INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    latency_ms    INTEGER NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Audit log: who looked at which employee records, and when
CREATE TABLE employee_lookup_log (
    id           BIGSERIAL PRIMARY KEY,
    viewer_id    TEXT NOT NULL REFERENCES employees (employee_id),
    returned_ids TEXT[] NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
