-- SHOPGRAB DATA WAREHOUSE ETL -- TEST SUITE
-- Tests for SCD Type 2 (DIM_MEMBER, DIM_MENU_ITEM) and incremental load.
--
-- HOW TO USE:
--   Run the full file: @scd2_tests
--   Each test section is self-contained. Every test inserts OLTP data,
--   calls the ETL proc / incremental script, asserts results, then ROLLS BACK
--   the OLTP change (via DELETE) so the warehouse reflects the clean state
--   again at the end.
--
-- ROLLBACK STRATEGY:
--   OLTP changes  -> explicit DELETE/UPDATE after each test assertion.
--   DW changes    -> explicitly DELETED (rows added by test procs) after assert.
--   The warehouse is returned to its pre-test state at the end of each test.
--   If a test fails mid-way, run the CLEANUP block at the bottom of this file.
--
-- PREREQUISITES:
--   @6_staging        -- views + control tables
--   @8_stored_procs   -- sp_sync_dim_member, sp_sync_dim_menu_item compiled
--   @7_init_load      -- warehouse already populated with baseline data
--
-- TEST INVENTORY:
--   TC-01  SCD2 NEW: brand-new member inserts as version 1 (current_flag='Y')
--   TC-02  SCD2 CHANGE: member status change expires old + inserts new version
--   TC-03  SCD2 NO-CHANGE: unchanged member does NOT produce new DW row
--   TC-04  SCD2 REJECT: dirty member (invalid status) logged, not loaded
--   TC-05  INCREMENTAL NEW ORDER: new OLTP order line appears in fact after run
--   TC-06  INCREMENTAL FACT UPDATE: changed quantity reflects in existing fact row

SET DEFINE OFF;
SET SERVEROUTPUT ON;
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

-- ============================================================================
-- GLOBAL TEST CONSTANTS
-- Uses member_id = 9999 and item_id = 9999 as test sentinels (must not exist
-- in real data; verified by TC-01 precondition check).
-- ============================================================================
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM member WHERE member_id = 9999;
    IF v_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20001,
            'Test sentinel member_id=9999 already exists. Clean up first.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('=== Pre-flight check passed ===');
END;
/

-- ============================================================================
-- TC-01: SCD2 NEW MEMBER
-- Inserts a brand-new OLTP member, runs proc, verifies one 'Y' row in DW.
-- ============================================================================
PROMPT;
PROMPT === TC-01: SCD2 NEW MEMBER ===;
DECLARE
    v_count   NUMBER;
    v_flag    VARCHAR2(1);
    v_eff     DATE;
    v_passed  BOOLEAN := FALSE;
BEGIN
    -- ARRANGE: insert test member into OLTP
    INSERT INTO member (member_id, member_type_id, full_name, email,
                        phone_no, password_hash, registration_date, member_status)
    VALUES (9999, 1, 'Test Member TC01', 'testmember.tc01@shopgrab.my',
            '0111111111', 'TESTHASH01', DATE '2024-01-15', 'ACTIVE');
    COMMIT;

    -- ACT: run SCD2 proc
    sp_sync_dim_member;

    -- ASSERT
    SELECT COUNT(*), MAX(current_flag), MAX(effective_date)
    INTO v_count, v_flag, v_eff
    FROM dim_member
    WHERE member_id = 9999;

    IF v_count = 1 AND v_flag = 'Y' AND v_eff = DATE '2024-01-15' THEN
        DBMS_OUTPUT.PUT_LINE('TC-01 PASS: 1 row inserted, current_flag=Y, effective_date=2024-01-15');
        v_passed := TRUE;
    ELSE
        DBMS_OUTPUT.PUT_LINE('TC-01 FAIL: count=' || v_count
            || ' flag=' || NVL(v_flag,'NULL') || ' eff=' || NVL(TO_CHAR(v_eff),'NULL'));
    END IF;

    -- ROLLBACK: remove test data from both OLTP and DW
    DELETE FROM dim_member    WHERE member_id = 9999;
    DELETE FROM member        WHERE member_id = 9999;
    DELETE FROM etl_batch_control WHERE source_name = 'MEMBER'
        AND batch_id = (SELECT MAX(batch_id) FROM etl_batch_control WHERE source_name='MEMBER');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('TC-01 cleanup done.');
END;
/

-- ============================================================================
-- TC-02: SCD2 CHANGE DETECTION
-- Inserts member, does initial load, changes status in OLTP, re-runs proc.
-- Expects: old row expired (current_flag='N'), new row inserted (current_flag='Y').
-- ============================================================================
PROMPT;
PROMPT === TC-02: SCD2 CHANGE DETECTION ===;
DECLARE
    v_total   NUMBER;
    v_active  NUMBER;
    v_expired NUMBER;
    v_new_status VARCHAR2(20);
BEGIN
    -- ARRANGE: insert member + initial DW load
    INSERT INTO member (member_id, member_type_id, full_name, email,
                        phone_no, password_hash, registration_date, member_status)
    VALUES (9999, 1, 'Test Member TC02', 'testmember.tc02@shopgrab.my',
            '0122222222', 'TESTHASH02', DATE '2023-06-01', 'ACTIVE');
    COMMIT;
    sp_sync_dim_member;   -- load initial version

    -- Verify baseline: 1 current row
    SELECT COUNT(*) INTO v_active
    FROM dim_member WHERE member_id = 9999 AND current_flag = 'Y';

    IF v_active <> 1 THEN
        DBMS_OUTPUT.PUT_LINE('TC-02 SETUP FAIL: expected 1 current row, got ' || v_active);
    ELSE
        -- ACT: change status in OLTP
        UPDATE member SET member_status = 'DEACTIVATED' WHERE member_id = 9999;
        COMMIT;
        sp_sync_dim_member;   -- incremental sync

        -- ASSERT
        SELECT COUNT(*) INTO v_total   FROM dim_member WHERE member_id = 9999;
        SELECT COUNT(*) INTO v_active  FROM dim_member WHERE member_id = 9999 AND current_flag = 'Y';
        SELECT COUNT(*) INTO v_expired FROM dim_member WHERE member_id = 9999 AND current_flag = 'N';
        SELECT MAX(member_status) INTO v_new_status
        FROM dim_member WHERE member_id = 9999 AND current_flag = 'Y';

        IF v_total = 2 AND v_active = 1 AND v_expired = 1
           AND v_new_status = 'DEACTIVATED'
        THEN
            DBMS_OUTPUT.PUT_LINE('TC-02 PASS: 2 rows total (1 expired, 1 current=DEACTIVATED)');
        ELSE
            DBMS_OUTPUT.PUT_LINE('TC-02 FAIL: total=' || v_total
                || ' active=' || v_active || ' expired=' || v_expired
                || ' new_status=' || NVL(v_new_status,'NULL'));
        END IF;
    END IF;

    -- ROLLBACK
    DELETE FROM dim_member WHERE member_id = 9999;
    DELETE FROM member     WHERE member_id = 9999;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('TC-02 cleanup done.');
END;
/

-- ============================================================================
-- TC-03: SCD2 NO CHANGE (IDEMPOTENT)
-- Inserts member, syncs twice without any OLTP change.
-- Expects: still exactly 1 DW row after second sync.
-- ============================================================================
PROMPT;
PROMPT === TC-03: SCD2 NO CHANGE (idempotent) ===;
DECLARE
    v_before  NUMBER;
    v_after   NUMBER;
BEGIN
    -- ARRANGE
    INSERT INTO member (member_id, member_type_id, full_name, email,
                        phone_no, password_hash, registration_date, member_status)
    VALUES (9999, 1, 'Test Member TC03', 'testmember.tc03@shopgrab.my',
            '0133333333', 'TESTHASH03', DATE '2022-03-10', 'ACTIVE');
    COMMIT;
    sp_sync_dim_member;   -- first sync

    SELECT COUNT(*) INTO v_before FROM dim_member WHERE member_id = 9999;

    -- ACT: second sync, no OLTP change
    sp_sync_dim_member;

    SELECT COUNT(*) INTO v_after FROM dim_member WHERE member_id = 9999;

    -- ASSERT
    IF v_before = 1 AND v_after = 1 THEN
        DBMS_OUTPUT.PUT_LINE('TC-03 PASS: row count stayed at 1 after second sync (no spurious insert)');
    ELSE
        DBMS_OUTPUT.PUT_LINE('TC-03 FAIL: before=' || v_before || ' after=' || v_after);
    END IF;

    -- ROLLBACK
    DELETE FROM dim_member WHERE member_id = 9999;
    DELETE FROM member     WHERE member_id = 9999;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('TC-03 cleanup done.');
END;
/

-- ============================================================================
-- TC-04: SCD2 DIRTY DATA REJECTION
-- Inserts member with invalid status 'PROBATION' (not in allowed list).
-- Expects: NOT loaded to DIM_MEMBER; logged in ETL_REJECTED_ROWS.
-- NOTE: bypasses OLTP CHECK constraint by disabling it temporarily.
-- ============================================================================
PROMPT;
PROMPT === TC-04: SCD2 DIRTY DATA REJECTION ===;
DECLARE
    v_dw_count      NUMBER;
    v_reject_count  NUMBER;
BEGIN
    -- ARRANGE: disable constraint to allow dirty data through
    EXECUTE IMMEDIATE 'ALTER TABLE member DISABLE CONSTRAINT ck_member_status';

    INSERT INTO member (member_id, member_type_id, full_name, email,
                        phone_no, password_hash, registration_date, member_status)
    VALUES (9999, 1, 'Dirty Member TC04', 'dirty.tc04@shopgrab.my',
            '0144444444', 'TESTHASH04', DATE '2021-01-01', 'PROBATION');
    COMMIT;
    -- NOTE: constraint stays DISABLED while dirty row exists;
    -- will be re-enabled in cleanup AFTER the row is deleted.

    -- ACT
    sp_sync_dim_member;

    -- ASSERT
    SELECT COUNT(*) INTO v_dw_count
    FROM dim_member WHERE member_id = 9999;

    SELECT COUNT(*) INTO v_reject_count
    FROM etl_rejected_rows
    WHERE source_name = 'MEMBER'
      AND source_row_ref = 'member_id=9999'
      AND validation_rule = 'INVALID_STATUS_VALUE'
      AND rejected_date >= TRUNC(SYSDATE);

    IF v_dw_count = 0 AND v_reject_count >= 1 THEN
        DBMS_OUTPUT.PUT_LINE('TC-04 PASS: dirty row NOT in DW; found ' || v_reject_count
            || ' reject log entry(ies)');
    ELSE
        DBMS_OUTPUT.PUT_LINE('TC-04 FAIL: dw_rows=' || v_dw_count
            || ' reject_entries=' || v_reject_count);
    END IF;

    -- ROLLBACK: delete dirty row first, THEN re-enable constraint
    DELETE FROM etl_rejected_rows WHERE source_name='MEMBER' AND source_row_ref='member_id=9999';
    EXECUTE IMMEDIATE 'ALTER TABLE member DISABLE CONSTRAINT ck_member_status';
    DELETE FROM member WHERE member_id = 9999;
    EXECUTE IMMEDIATE 'ALTER TABLE member ENABLE CONSTRAINT ck_member_status';
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('TC-04 cleanup done.');
END;
/

-- ============================================================================
-- TC-05: INCREMENTAL LOAD -- NEW ORDER LINE
-- Inserts a new OLTP order item linked to existing member/restaurant/item.
-- Runs 10_incremental equivalent (MERGE fact), verifies row appears in DW.
-- ============================================================================
PROMPT;
PROMPT === TC-05: INCREMENTAL -- NEW ORDER LINE ===;
DECLARE
    v_order_id       NUMBER := 99999;
    v_member_id      NUMBER;
    v_rest_id        NUMBER;
    v_item_id        NUMBER;
    v_pay_id         NUMBER := 99999;
    v_fact_count     NUMBER;
    v_member_key     NUMBER;
    v_rest_key       NUMBER;
    v_item_key       NUMBER;
BEGIN
    -- Pick any existing dimension keys for join
    SELECT MIN(member_id) INTO v_member_id FROM dim_member WHERE current_flag = 'Y';
    SELECT MIN(restaurant_id) INTO v_rest_id FROM dim_restaurant;
    SELECT MIN(item_id) INTO v_item_id FROM dim_menu_item WHERE current_flag = 'Y';

    -- ARRANGE: insert minimal OLTP order (PICKUP = no address_id required)
    -- ck_order_total: total_amount = subtotal + delivery_fee - discount_amount
    INSERT INTO customer_order (order_id, member_id, restaurant_id,
                                order_datetime, order_type, order_status, subtotal,
                                discount_amount, delivery_fee, total_amount, payment_status)
    VALUES (v_order_id, v_member_id, v_rest_id,
            SYSDATE - 1, 'PICKUP', 'COMPLETED', 25.00, 0, 0, 25.00, 'PAID');

    INSERT INTO payment (payment_id, order_id, payment_method, payment_status, payment_amount)
    VALUES (v_pay_id, v_order_id, 'FPX', 'SUCCESS', 25.00);

    INSERT INTO order_item (order_item_id, order_id, item_id, quantity, unit_price, subtotal)
    VALUES (99999, v_order_id, v_item_id, 1, 25.00, 25.00);
    COMMIT;

    -- Sync payment dim first (MERGE)
    MERGE INTO dim_payment tgt
    USING (SELECT v_pay_id AS payment_id, 'FPX' AS payment_method,
                  'SUCCESS' AS payment_status FROM dual) src
    ON (tgt.payment_id = src.payment_id)

    WHEN NOT MATCHED THEN INSERT (payment_key, payment_id, payment_method, payment_status)
    VALUES (dim_pay_seq.NEXTVAL, src.payment_id, src.payment_method, src.payment_status);
    COMMIT;

    -- ACT: run fact MERGE (same logic as 10_incremental PART 7)
    MERGE INTO fact_order_sales tgt
    USING (
        SELECT s.order_id, dmi.item_key, dd.date_key, dm.member_key,
               dr.restaurant_key,
               NVL(dv.voucher_key, -1)           AS voucher_key,
               NVL(ddc.delivery_company_key, -1)  AS delivery_company_key,
               dp.payment_key,
               s.quantity, s.unit_price, s.subtotal,
               s.discount_amount_prorated, s.delivery_fee_prorated, s.total_amount
        FROM vw_stg_order_sales s
        JOIN dim_date dd  ON dd.full_date = TRUNC(s.order_datetime)
        JOIN dim_member dm ON dm.member_id = s.member_id AND dm.current_flag = 'Y'
        JOIN dim_restaurant dr ON dr.restaurant_id = s.restaurant_id
        JOIN dim_menu_item dmi ON dmi.item_id = s.item_id AND dmi.current_flag = 'Y'
        LEFT JOIN dim_voucher dv ON dv.voucher_id = s.voucher_id
        LEFT JOIN dim_delivery_company ddc ON ddc.delivery_company_id = s.delivery_company_id
        JOIN dim_payment dp ON dp.payment_id = s.payment_id
        WHERE s.order_id = v_order_id
    ) src
    ON (tgt.order_id = src.order_id AND tgt.item_key = src.item_key)
    WHEN NOT MATCHED THEN INSERT (
        order_id, date_key, member_key, restaurant_key, item_key,
        voucher_key, delivery_company_key, payment_key,
        quantity, unit_price, subtotal,
        discount_amount_prorated, delivery_fee_prorated, total_amount
    ) VALUES (
        src.order_id, src.date_key, src.member_key, src.restaurant_key, src.item_key,
        src.voucher_key, src.delivery_company_key, src.payment_key,
        src.quantity, src.unit_price, src.subtotal,
        src.discount_amount_prorated, src.delivery_fee_prorated, src.total_amount
    );
    COMMIT;

    -- ASSERT
    SELECT COUNT(*) INTO v_fact_count
    FROM fact_order_sales WHERE order_id = v_order_id;

    IF v_fact_count = 1 THEN
        DBMS_OUTPUT.PUT_LINE('TC-05 PASS: new order line appeared in FACT_ORDER_SALES');
    ELSE
        DBMS_OUTPUT.PUT_LINE('TC-05 FAIL: fact_count=' || v_fact_count);
    END IF;

    -- ROLLBACK
    DELETE FROM fact_order_sales WHERE order_id = v_order_id;
    DELETE FROM dim_payment      WHERE payment_id = v_pay_id;
    DELETE FROM order_item       WHERE order_item_id = 99999;
    DELETE FROM payment          WHERE payment_id = v_pay_id;
    DELETE FROM customer_order   WHERE order_id = v_order_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('TC-05 cleanup done.');
END;
/

-- ============================================================================
-- TC-06: INCREMENTAL FACT UPDATE (quantity change)
-- Loads an order into fact, then changes quantity in OLTP, re-merges.
-- Expects: fact row quantity reflects the updated value.
-- ============================================================================
PROMPT;
PROMPT === TC-06: INCREMENTAL FACT UPDATE ===;
DECLARE
    v_order_id   NUMBER := 99998;
    v_member_id  NUMBER;
    v_rest_id    NUMBER;
    v_item_id    NUMBER;
    v_pay_id     NUMBER := 99998;
    v_qty_before NUMBER;
    v_qty_after  NUMBER;
    v_item_key   NUMBER;
BEGIN
    SELECT MIN(member_id) INTO v_member_id FROM dim_member WHERE current_flag = 'Y';
    SELECT MIN(restaurant_id) INTO v_rest_id FROM dim_restaurant;
    SELECT MIN(item_id) INTO v_item_id FROM dim_menu_item WHERE current_flag = 'Y';
    SELECT MIN(item_key) INTO v_item_key FROM dim_menu_item WHERE item_id = v_item_id AND current_flag = 'Y';

    -- ARRANGE: insert initial order (PICKUP = no address_id required)
    -- ck_order_total: total_amount = subtotal + delivery_fee - discount_amount
    INSERT INTO customer_order (order_id, member_id, restaurant_id,
                                order_datetime, order_type, order_status, subtotal,
                                discount_amount, delivery_fee, total_amount, payment_status)
    VALUES (v_order_id, v_member_id, v_rest_id,
            SYSDATE - 2, 'PICKUP', 'COMPLETED', 15.00, 0, 0, 15.00, 'PAID');

    INSERT INTO payment (payment_id, order_id, payment_method, payment_status, payment_amount)
    VALUES (v_pay_id, v_order_id, 'EWALLET', 'SUCCESS', 15.00);

    INSERT INTO order_item (order_item_id, order_id, item_id, quantity, unit_price, subtotal)
    VALUES (99998, v_order_id, v_item_id, 1, 15.00, 15.00);
    COMMIT;

    -- Seed DIM_PAYMENT
    MERGE INTO dim_payment tgt
    USING (SELECT v_pay_id AS payment_id, 'EWALLET' AS payment_method,
                  'SUCCESS' AS payment_status FROM dual) src
    ON (tgt.payment_id = src.payment_id)

    WHEN NOT MATCHED THEN INSERT (payment_key, payment_id, payment_method, payment_status)
    VALUES (dim_pay_seq.NEXTVAL, src.payment_id, src.payment_method, src.payment_status);

    -- Initial fact load
    MERGE INTO fact_order_sales tgt
    USING (
        SELECT s.order_id, dmi.item_key, dd.date_key, dm.member_key,
               dr.restaurant_key, NVL(dv.voucher_key,-1) AS voucher_key,
               NVL(ddc.delivery_company_key,-1) AS delivery_company_key,
               dp.payment_key, s.quantity, s.unit_price, s.subtotal,
               s.discount_amount_prorated, s.delivery_fee_prorated, s.total_amount
        FROM vw_stg_order_sales s
        JOIN dim_date dd ON dd.full_date = TRUNC(s.order_datetime)
        JOIN dim_member dm ON dm.member_id = s.member_id AND dm.current_flag = 'Y'
        JOIN dim_restaurant dr ON dr.restaurant_id = s.restaurant_id
        JOIN dim_menu_item dmi ON dmi.item_id = s.item_id AND dmi.current_flag = 'Y'
        LEFT JOIN dim_voucher dv ON dv.voucher_id = s.voucher_id
        LEFT JOIN dim_delivery_company ddc ON ddc.delivery_company_id = s.delivery_company_id
        JOIN dim_payment dp ON dp.payment_id = s.payment_id
        WHERE s.order_id = v_order_id
    ) src
    ON (tgt.order_id = src.order_id AND tgt.item_key = src.item_key)
    WHEN NOT MATCHED THEN INSERT (
        order_id, date_key, member_key, restaurant_key, item_key,
        voucher_key, delivery_company_key, payment_key,
        quantity, unit_price, subtotal,
        discount_amount_prorated, delivery_fee_prorated, total_amount
    ) VALUES (
        src.order_id, src.date_key, src.member_key, src.restaurant_key, src.item_key,
        src.voucher_key, src.delivery_company_key, src.payment_key,
        src.quantity, src.unit_price, src.subtotal,
        src.discount_amount_prorated, src.delivery_fee_prorated, src.total_amount
    );
    COMMIT;

    SELECT quantity INTO v_qty_before
    FROM fact_order_sales WHERE order_id = v_order_id AND item_key = v_item_key;

    -- ACT: change quantity in OLTP
    -- ck_order_total must stay: total = subtotal + delivery_fee - discount
    UPDATE order_item
       SET quantity = 3, subtotal = 45.00
     WHERE order_item_id = 99998;
    UPDATE customer_order
       SET subtotal = 45.00, total_amount = 45.00  -- delivery_fee=0, discount=0
     WHERE order_id = v_order_id;
    COMMIT;

    -- Re-merge (incremental update path)
    MERGE INTO fact_order_sales tgt
    USING (
        SELECT s.order_id, dmi.item_key, dd.date_key, dm.member_key,
               dr.restaurant_key, NVL(dv.voucher_key,-1) AS voucher_key,
               NVL(ddc.delivery_company_key,-1) AS delivery_company_key,
               dp.payment_key, s.quantity, s.unit_price, s.subtotal,
               s.discount_amount_prorated, s.delivery_fee_prorated, s.total_amount
        FROM vw_stg_order_sales s
        JOIN dim_date dd ON dd.full_date = TRUNC(s.order_datetime)
        JOIN dim_member dm ON dm.member_id = s.member_id AND dm.current_flag = 'Y'
        JOIN dim_restaurant dr ON dr.restaurant_id = s.restaurant_id
        JOIN dim_menu_item dmi ON dmi.item_id = s.item_id AND dmi.current_flag = 'Y'
        LEFT JOIN dim_voucher dv ON dv.voucher_id = s.voucher_id
        LEFT JOIN dim_delivery_company ddc ON ddc.delivery_company_id = s.delivery_company_id
        JOIN dim_payment dp ON dp.payment_id = s.payment_id
        WHERE s.order_id = v_order_id
    ) src
    ON (tgt.order_id = src.order_id AND tgt.item_key = src.item_key)
    WHEN MATCHED THEN UPDATE SET
        tgt.quantity = src.quantity, tgt.subtotal = src.subtotal,
        tgt.total_amount = src.total_amount
      WHERE tgt.quantity <> src.quantity OR tgt.subtotal <> src.subtotal;
    COMMIT;

    SELECT quantity INTO v_qty_after
    FROM fact_order_sales WHERE order_id = v_order_id AND item_key = v_item_key;

    -- ASSERT
    IF v_qty_before = 1 AND v_qty_after = 3 THEN
        DBMS_OUTPUT.PUT_LINE('TC-06 PASS: quantity updated from 1 to 3 in DW');
    ELSE
        DBMS_OUTPUT.PUT_LINE('TC-06 FAIL: qty_before=' || v_qty_before
            || ' qty_after=' || v_qty_after);
    END IF;

    -- ROLLBACK
    DELETE FROM fact_order_sales WHERE order_id = v_order_id;
    DELETE FROM dim_payment      WHERE payment_id = v_pay_id;
    DELETE FROM order_item       WHERE order_item_id = 99998;
    DELETE FROM payment          WHERE payment_id = v_pay_id;
    DELETE FROM customer_order   WHERE order_id = v_order_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('TC-06 cleanup done.');
END;
/

-- ============================================================================
-- EMERGENCY CLEANUP
-- Run manually if any test aborted mid-execution:
--   @scd2_tests_cleanup   (or paste block below)
-- ============================================================================
PROMPT;
PROMPT === TEST SUITE COMPLETE ===;
PROMPT If tests aborted mid-run, execute the emergency cleanup block below:;
PROMPT;
/*
-- EMERGENCY CLEANUP (paste and run if needed):
DELETE FROM fact_order_sales  WHERE order_id IN (99998, 99999);
DELETE FROM dim_payment       WHERE payment_id IN (99998, 99999);
DELETE FROM dim_member        WHERE member_id = 9999;
DELETE FROM etl_rejected_rows WHERE source_row_ref = 'member_id=9999';
DELETE FROM order_item        WHERE order_item_id IN (99998, 99999);
DELETE FROM payment           WHERE payment_id IN (99998, 99999);
DELETE FROM customer_order    WHERE order_id IN (99998, 99999);
BEGIN
    EXECUTE IMMEDIATE 'ALTER TABLE member ENABLE CONSTRAINT ck_member_status';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
DELETE FROM member WHERE member_id = 9999;
COMMIT;
*/
