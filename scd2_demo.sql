-- SHOPGRAB DATA WAREHOUSE: SCD TYPE 2 DEMONSTRATION
-- This script demonstrates the Slowly Changing Dimension (Type 2) capabilities
-- of the DIM_MEMBER table. It shows the transition from a new record to an 
-- expired record when an attribute (like member_status) changes in the OLTP source.

SET DEFINE OFF;
SET SERVEROUTPUT ON FORMAT WRAPPED;
SET LINESIZE 200;
SET PAGESIZE 100;
COLUMN full_name FORMAT A20;
COLUMN email FORMAT A30;
COLUMN member_status FORMAT A15;
COLUMN effective_date FORMAT A15;
COLUMN expiry_date FORMAT A15;
COLUMN current_flag FORMAT A12;
cl scr
PROMPT ====================================================================;
PROMPT [DEMO 1] SCENARIO: A BRAND NEW MEMBER REGISTERS
PROMPT ====================================================================;

-- 1. Insert a brand new member into the OLTP table
INSERT INTO member (member_id, member_type_id, full_name, email,
                    phone_no, password_hash, registration_date, member_status)
VALUES (8888, 1, 'John Doe', 'john.doe@shopgrab.my',
        '0199999999', 'HASH', DATE '2024-01-01', 'ACTIVE');
COMMIT;

PROMPT >> 1. OLTP row inserted. Running ETL sync...;
EXEC sp_sync_dim_member;

PROMPT ;
PROMPT >> 2. State of DIM_MEMBER after first sync:;
SELECT member_id, full_name, email, member_status, 
       TO_CHAR(effective_date, 'YYYY-MM-DD') AS effective_date, 
       TO_CHAR(expiry_date, 'YYYY-MM-DD') AS expiry_date, 
       current_flag
FROM dim_member 
WHERE member_id = 8888;

PROMPT ;
PROMPT ====================================================================;
PROMPT [DEMO 2] SCENARIO: THE MEMBER CHANGES THEIR EMAIL AND STATUS
PROMPT ====================================================================;

-- 3. Update the member in the OLTP table
UPDATE member 
   SET email = 'john.new@shopgrab.my',
       member_status = 'SUSPENDED'
 WHERE member_id = 8888;
COMMIT;

PROMPT >> 3. OLTP row updated. Running ETL sync again...;
EXEC sp_sync_dim_member;

PROMPT ;
PROMPT >> 4. State of DIM_MEMBER after second sync (SCD2 in action):;
SELECT member_id, full_name, email, member_status, 
       TO_CHAR(effective_date, 'YYYY-MM-DD') AS effective_date, 
       TO_CHAR(expiry_date, 'YYYY-MM-DD') AS expiry_date, 
       current_flag
FROM dim_member 
WHERE member_id = 8888
ORDER BY effective_date;

PROMPT ;
PROMPT ====================================================================;
PROMPT [DEMO 3] SCENARIO: NO CHANGES MADE (IDEMPOTENT)
PROMPT ====================================================================;
PROMPT >> 5. Running ETL sync with no OLTP changes...;
EXEC sp_sync_dim_member;

PROMPT ;
PROMPT >> 6. State of DIM_MEMBER remains unchanged (no duplicate rows created):;
SELECT member_id, full_name, email, member_status, 
       TO_CHAR(effective_date, 'YYYY-MM-DD') AS effective_date, 
       TO_CHAR(expiry_date, 'YYYY-MM-DD') AS expiry_date, 
       current_flag
FROM dim_member 
WHERE member_id = 8888
ORDER BY effective_date;

-- Cleanup
DELETE FROM dim_member WHERE member_id = 8888;
DELETE FROM member WHERE member_id = 8888;
COMMIT;
