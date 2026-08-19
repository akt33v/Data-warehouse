-- SHOPGRAB ASSIGNMENT DDL
-- STEP 5: SEED REFERENCE DATA

SET DEFINE OFF;

INSERT INTO member_type (member_type_id, type_name, monthly_fee, benefits_desc)
VALUES (1, 'NORMAL', 0, 'Free registration plan');

INSERT INTO member_type (member_type_id, type_name, monthly_fee, benefits_desc)
VALUES (2, 'VIP', 6, 'RM6 monthly plan');

COMMIT;
