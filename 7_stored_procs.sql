-- SHOPGRAB DATA WAREHOUSE ETL
-- STEP 8: REUSABLE SCD2 STORED PROCEDURES
-- Run ONCE after 6_staging.sql and before 7_init_load.sql / 10_incremental.sql.
--
-- sp_sync_dim_member    : SCD Type 2 load for DIM_MEMBER
-- sp_sync_dim_menu_item : SCD Type 2 load for DIM_MENU_ITEM
--
-- Both procs are called identically from the initial load and every subsequent
-- incremental run. The SCD2 diff logic (current_flag='Y' lookup, expire + insert
-- new version) is self-contained here; no duplication across scripts.
--
-- Data quality strategy (two layers):
--   Layer 1 (view-level)  : vw_stg_member / vw_stg_menu_item already filter
--                           structurally invalid rows before the proc sees them.
--   Layer 2 (proc-level)  : Each proc re-validates business rules, logs failures
--                           to etl_rejected_rows, and continues without aborting.
--                           DB errors caught via SAVEPOINT + inner EXCEPTION block.

SET DEFINE OFF;
SET SERVEROUTPUT ON;

-- ============================================================================
-- PROCEDURE: sp_sync_dim_member
-- Source    : vw_stg_member
-- Strategy  : SCD Type 2
--   - New business key         -> INSERT version 1 (effective = registration_date)
--   - Existing, changed attrs  -> expire current + INSERT new version (effective = today)
--   - Existing, unchanged      -> no write
--   - Invalid row              -> log to etl_rejected_rows, skip
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_sync_dim_member AS
    v_exists    NUMBER;
    v_changed   NUMBER;
    v_new       NUMBER := 0;
    v_upd       NUMBER := 0;
    v_skip      NUMBER := 0;
    v_batch_id  NUMBER;
    v_err_msg   VARCHAR2(400);
BEGIN
    -- Register batch
    SELECT etl_batch_id_seq.NEXTVAL INTO v_batch_id FROM dual;
    INSERT INTO etl_batch_control (batch_id, source_name, batch_status, row_count)
    VALUES (v_batch_id, 'MEMBER', 'PENDING',
            (SELECT COUNT(*) FROM vw_stg_member));
    COMMIT;

    FOR r IN (SELECT * FROM vw_stg_member) LOOP

        -- Layer 2 business-rule validation (belt-and-suspenders over the view)
        IF r.member_id IS NULL OR r.full_name IS NULL OR r.email IS NULL
           OR r.member_type IS NULL OR r.member_status IS NULL
           OR r.member_status NOT IN ('ACTIVE','DEACTIVATED','SUSPENDED')
        THEN
            INSERT INTO etl_rejected_rows (
                reject_id, batch_id, source_name, source_row_ref,
                reject_reason, validation_rule, raw_snapshot
            ) VALUES (
                etl_reject_id_seq.NEXTVAL, v_batch_id, 'MEMBER',
                'member_id=' || NVL(TO_CHAR(r.member_id), 'NULL'),
                CASE
                    WHEN r.member_id     IS NULL THEN 'NULL member_id'
                    WHEN r.full_name     IS NULL THEN 'NULL full_name'
                    WHEN r.email         IS NULL THEN 'NULL email'
                    WHEN r.member_type   IS NULL THEN 'NULL member_type'
                    WHEN r.member_status IS NULL THEN 'NULL member_status'
                    ELSE 'Invalid member_status: ' || r.member_status
                END,
                CASE
                    WHEN r.member_id     IS NULL THEN 'NULL_REQUIRED_FIELD'
                    WHEN r.full_name     IS NULL THEN 'NULL_REQUIRED_FIELD'
                    WHEN r.email         IS NULL THEN 'NULL_REQUIRED_FIELD'
                    WHEN r.member_type   IS NULL THEN 'NULL_REQUIRED_FIELD'
                    WHEN r.member_status IS NULL THEN 'NULL_REQUIRED_FIELD'
                    ELSE 'INVALID_STATUS_VALUE'
                END,
                'id='     || NVL(TO_CHAR(r.member_id), 'NULL')
                || '|name='   || NVL(r.full_name,   'NULL')
                || '|email='  || NVL(r.email,        'NULL')
                || '|type='   || NVL(r.member_type,  'NULL')
                || '|status=' || NVL(r.member_status, 'NULL')
            );
            v_skip := v_skip + 1;
            CONTINUE;
        END IF;

        SAVEPOINT sp_member;
        BEGIN
            SELECT COUNT(*) INTO v_exists
            FROM dim_member
            WHERE member_id = r.member_id AND current_flag = 'Y';

            IF v_exists = 0 THEN
                -- Brand-new business key: insert version 1
                INSERT INTO dim_member (
                    member_key, member_id, full_name, email, member_type, member_status,
                    effective_date, expiry_date, current_flag
                ) VALUES (
                    dim_member_seq.NEXTVAL, r.member_id, r.full_name, r.email,
                    r.member_type, r.member_status,
                    r.registration_date, DATE '9999-12-31', 'Y'
                );
                v_new := v_new + 1;
            ELSE
                -- Existing key: check for attribute changes
                -- NVL guards handle NULL <-> value transitions correctly
                SELECT COUNT(*) INTO v_changed
                FROM dim_member
                WHERE member_id = r.member_id AND current_flag = 'Y'
                  AND (NVL(full_name,    '~') <> NVL(r.full_name,    '~')
                       OR NVL(email,        '~') <> NVL(r.email,        '~')
                       OR NVL(member_type,  '~') <> NVL(r.member_type,  '~')
                       OR NVL(member_status,'~') <> NVL(r.member_status,'~'));

                IF v_changed > 0 THEN
                    -- Expire current version
                    UPDATE dim_member
                       SET expiry_date = TRUNC(SYSDATE) - 1,
                           current_flag = 'N'
                     WHERE member_id = r.member_id AND current_flag = 'Y';

                    -- Insert new version
                    INSERT INTO dim_member (
                        member_key, member_id, full_name, email, member_type, member_status,
                        effective_date, expiry_date, current_flag
                    ) VALUES (
                        dim_member_seq.NEXTVAL, r.member_id, r.full_name, r.email,
                        r.member_type, r.member_status,
                        TRUNC(SYSDATE), DATE '9999-12-31', 'Y'
                    );
                    v_upd := v_upd + 1;
                END IF;
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                v_err_msg := SUBSTR(SQLERRM, 1, 400);
                ROLLBACK TO sp_member;
                INSERT INTO etl_rejected_rows (
                    reject_id, batch_id, source_name, source_row_ref,
                    reject_reason, validation_rule, raw_snapshot
                ) VALUES (
                    etl_reject_id_seq.NEXTVAL, v_batch_id, 'MEMBER',
                    'member_id=' || r.member_id,
                    v_err_msg,
                    'DB_CONSTRAINT_ERROR',
                    'id=' || r.member_id || '|name=' || r.full_name
                    || '|email=' || r.email || '|status=' || r.member_status
                );
                v_skip := v_skip + 1;
        END;
    END LOOP;

    -- Finalise batch record
    UPDATE etl_batch_control
       SET batch_status   = 'PROCESSED',
           valid_count    = v_new + v_upd,
           rejected_count = v_skip,
           processed_date = SYSDATE
     WHERE batch_id = v_batch_id AND source_name = 'MEMBER';
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('DIM_MEMBER: ' || v_new || ' new, '
        || v_upd || ' updated (SCD2), ' || v_skip || ' rejected.');
END sp_sync_dim_member;
/

-- ============================================================================
-- PROCEDURE: sp_sync_dim_menu_item
-- Source    : vw_stg_menu_item
-- Strategy  : SCD Type 2
--   - New business key         -> INSERT version 1 (effective = 2000-01-01 epoch,
--                                 as menu_item has no OLTP creation date)
--   - Existing, changed attrs  -> expire current + INSERT new version (effective = today)
--   - Existing, unchanged      -> no write
--   - Invalid row              -> log to etl_rejected_rows, skip
-- ============================================================================
CREATE OR REPLACE PROCEDURE sp_sync_dim_menu_item AS
    v_exists    NUMBER;
    v_changed   NUMBER;
    v_new       NUMBER := 0;
    v_upd       NUMBER := 0;
    v_skip      NUMBER := 0;
    v_batch_id  NUMBER;
    v_err_msg   VARCHAR2(400);
BEGIN
    -- Register batch
    SELECT etl_batch_id_seq.NEXTVAL INTO v_batch_id FROM dual;
    INSERT INTO etl_batch_control (batch_id, source_name, batch_status, row_count)
    VALUES (v_batch_id, 'MENU_ITEM', 'PENDING',
            (SELECT COUNT(*) FROM vw_stg_menu_item));
    COMMIT;

    FOR r IN (SELECT * FROM vw_stg_menu_item) LOOP

        -- Layer 2 business-rule validation (belt-and-suspenders over the view)
        IF r.item_id IS NULL OR r.item_name IS NULL OR r.item_category IS NULL THEN
            INSERT INTO etl_rejected_rows (
                reject_id, batch_id, source_name, source_row_ref,
                reject_reason, validation_rule, raw_snapshot
            ) VALUES (
                etl_reject_id_seq.NEXTVAL, v_batch_id, 'MENU_ITEM',
                'item_id=' || NVL(TO_CHAR(r.item_id), 'NULL'),
                CASE
                    WHEN r.item_id       IS NULL THEN 'NULL item_id'
                    WHEN r.item_name     IS NULL THEN 'NULL item_name'
                    ELSE 'NULL item_category'
                END,
                'NULL_REQUIRED_FIELD',
                'id='   || NVL(TO_CHAR(r.item_id), 'NULL')
                || '|name=' || NVL(r.item_name,     'NULL')
                || '|cat='  || NVL(r.item_category, 'NULL')
                || '|type=' || NVL(r.item_type,     'NULL')
            );
            v_skip := v_skip + 1;
            CONTINUE;
        END IF;

        SAVEPOINT sp_menu;
        BEGIN
            SELECT COUNT(*) INTO v_exists
            FROM dim_menu_item
            WHERE item_id = r.item_id AND current_flag = 'Y';

            IF v_exists = 0 THEN
                -- Brand-new business key: insert version 1
                -- Epoch 2000-01-01 used as effective_date (no OLTP creation date)
                INSERT INTO dim_menu_item (
                    item_key, item_id, item_name, item_category, item_type,
                    budget_meal, super_deal, effective_date, expiry_date, current_flag
                ) VALUES (
                    dim_menu_seq.NEXTVAL, r.item_id, r.item_name, r.item_category, r.item_type,
                    r.budget_meal, r.super_deal, DATE '2000-01-01', DATE '9999-12-31', 'Y'
                );
                v_new := v_new + 1;
            ELSE
                -- Existing key: check for attribute changes
                -- NVL guards handle NULL <-> value transitions correctly
                SELECT COUNT(*) INTO v_changed
                FROM dim_menu_item
                WHERE item_id = r.item_id AND current_flag = 'Y'
                  AND (NVL(item_name,     '~') <> NVL(r.item_name,     '~')
                       OR NVL(item_category,'~') <> NVL(r.item_category,'~')
                       OR NVL(item_type,   '~') <> NVL(r.item_type,    '~')
                       OR NVL(budget_meal, '~') <> NVL(r.budget_meal,  '~')
                       OR NVL(super_deal,  '~') <> NVL(r.super_deal,   '~'));

                IF v_changed > 0 THEN
                    -- Expire current version
                    UPDATE dim_menu_item
                       SET expiry_date = TRUNC(SYSDATE) - 1,
                           current_flag = 'N'
                     WHERE item_id = r.item_id AND current_flag = 'Y';

                    -- Insert new version
                    INSERT INTO dim_menu_item (
                        item_key, item_id, item_name, item_category, item_type,
                        budget_meal, super_deal, effective_date, expiry_date, current_flag
                    ) VALUES (
                        dim_menu_seq.NEXTVAL, r.item_id, r.item_name, r.item_category, r.item_type,
                        r.budget_meal, r.super_deal, TRUNC(SYSDATE), DATE '9999-12-31', 'Y'
                    );
                    v_upd := v_upd + 1;
                END IF;
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                v_err_msg := SUBSTR(SQLERRM, 1, 400);
                ROLLBACK TO sp_menu;
                INSERT INTO etl_rejected_rows (
                    reject_id, batch_id, source_name, source_row_ref,
                    reject_reason, validation_rule, raw_snapshot
                ) VALUES (
                    etl_reject_id_seq.NEXTVAL, v_batch_id, 'MENU_ITEM',
                    'item_id=' || r.item_id,
                    v_err_msg,
                    'DB_CONSTRAINT_ERROR',
                    'id=' || r.item_id || '|name=' || r.item_name
                    || '|cat=' || r.item_category
                );
                v_skip := v_skip + 1;
        END;
    END LOOP;

    -- Finalise batch record
    UPDATE etl_batch_control
       SET batch_status   = 'PROCESSED',
           valid_count    = v_new + v_upd,
           rejected_count = v_skip,
           processed_date = SYSDATE
     WHERE batch_id = v_batch_id AND source_name = 'MENU_ITEM';
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('DIM_MENU_ITEM: ' || v_new || ' new, '
        || v_upd || ' updated (SCD2), ' || v_skip || ' rejected.');
END sp_sync_dim_menu_item;
/

PROMPT ======= Stored procedures compiled: sp_sync_dim_member, sp_sync_dim_menu_item =======;

-- Verify both compiled without errors
SELECT object_name, status
FROM user_objects
WHERE object_type = 'PROCEDURE'
  AND object_name IN ('SP_SYNC_DIM_MEMBER', 'SP_SYNC_DIM_MENU_ITEM');
