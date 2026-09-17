-- Sample data, loaded once when the database is first created.

-- Which policy access levels each role can read.
INSERT INTO role_access (role, access_level) VALUES
    ('employee', 'general'),

    ('manager',  'general'),
    ('manager',  'manager_only'),

    ('hr',       'general'),
    ('hr',       'manager_only'),
    ('hr',       'hr_only'),

    ('exec',     'general'),
    ('exec',     'manager_only'),
    ('exec',     'hr_only'),
    ('exec',     'exec_only');


-- Twelve employees at Northwind Systems.
--
-- Managers come before the people who report to them, because manager_id must
-- point at a row that already exists. Every salary sits inside the band for
-- its level in Compensation Bands 2026.
--
--   Dana Whitfield       COO                   exec
--     Priya Raman        HR Manager            hr
--       Omar Haddad      Recruiter
--     Liam Fischer       Engineering Manager   manager
--       Amara Diallo     Software Engineer II
--       Noah Bennett     Senior Software Engineer
--       Elena Petrova    Staff Software Engineer
--       Sofia Martinez   Software Engineer I
--     Kenji Tanaka       Sales Manager         manager
--       Grace Okafor     Account Executive
--       Mateo Rossi      Sales Development Representative
--     Hannah Cho         Financial Analyst
INSERT INTO employees
    (employee_id, email, full_name, role, department, job_title, job_level,
     manager_id, location, hire_date, base_salary, bonus_target_percent, pto_days_remaining)
VALUES
    ('NW-1001', 'dana.whitfield@northwind.example', 'Dana Whitfield', 'exec',     'Executive',         'Chief Operating Officer',          'L8', NULL,      'New York, NY',        '2017-03-01', 312000, 20, 14.5),
    ('NW-1002', 'priya.raman@northwind.example',    'Priya Raman',    'hr',       'People Operations', 'HR Manager',                       'L6', 'NW-1001', 'Chicago, IL',         '2019-06-10', 198000, 15, 11.0),
    ('NW-1003', 'liam.fischer@northwind.example',   'Liam Fischer',   'manager',  'Engineering',       'Engineering Manager',              'L6', 'NW-1001', 'Austin, TX',          '2018-09-17', 214000, 15,  9.5),
    ('NW-1004', 'kenji.tanaka@northwind.example',   'Kenji Tanaka',   'manager',  'Sales',             'Sales Manager',                    'L5', 'NW-1001', 'Chicago, IL',         '2020-02-24', 171000, 10, 16.0),
    ('NW-1005', 'amara.diallo@northwind.example',   'Amara Diallo',   'employee', 'Engineering',       'Software Engineer II',             'L3', 'NW-1003', 'Austin, TX',          '2023-02-06', 118000,  5, 12.5),
    ('NW-1006', 'noah.bennett@northwind.example',   'Noah Bennett',   'employee', 'Engineering',       'Senior Software Engineer',         'L4', 'NW-1003', 'Remote - Denver, CO', '2021-05-03', 146000, 10, 20.0),
    ('NW-1007', 'elena.petrova@northwind.example',  'Elena Petrova',  'employee', 'Engineering',       'Staff Software Engineer',          'L5', 'NW-1003', 'Austin, TX',          '2020-10-12', 176000, 10,  7.0),
    ('NW-1008', 'sofia.martinez@northwind.example', 'Sofia Martinez', 'employee', 'Engineering',       'Software Engineer I',              'L2', 'NW-1003', 'Austin, TX',          '2025-01-13',  94000,  5, 15.0),
    ('NW-1009', 'grace.okafor@northwind.example',   'Grace Okafor',   'employee', 'Sales',             'Account Executive',                'L3', 'NW-1004', 'Chicago, IL',         '2022-08-15', 108000,  5, 18.5),
    ('NW-1010', 'mateo.rossi@northwind.example',    'Mateo Rossi',    'employee', 'Sales',             'Sales Development Representative', 'L1', 'NW-1004', 'Chicago, IL',         '2025-06-02',  72000,  5,  9.0),
    ('NW-1011', 'omar.haddad@northwind.example',    'Omar Haddad',    'employee', 'People Operations', 'Recruiter',                        'L3', 'NW-1002', 'Chicago, IL',         '2024-04-22', 101000,  5, 13.0),
    ('NW-1012', 'hannah.cho@northwind.example',     'Hannah Cho',     'employee', 'Finance',           'Financial Analyst',                'L3', 'NW-1001', 'New York, NY',        '2022-11-07', 112000,  5,  6.5);
